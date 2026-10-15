#!/usr/bin/env python3
"""Builds the heads and hairstyles for Neon Getaway's 3D people.

Heads are sculpted from soft shapes (cranium, cheekbones, jaw, chin, brow ridge, nose, lips,
ears) and meshed like the bodies (tools/make_bodies.py). Each head also carries feature masks
in its texture layout (shading, lips, brows, beard, stubble, eye whites, iris, pupil, lash line,
catchlight) so the app can paint any skin, eye, lip and hair colour onto the same face.

Hairstyles are shells grown from the skull, cut at a hairline, plus style volumes (bob, long,
ponytail, bun, locs, curls).

Everything is in metres relative to the head joint (world y 1.555 in the bind pose).

Output (NeonGetaway/Scene/Bodies):
  head_f{frame}.bin  NGH1: mesh (pos, normal, uv) + 10 deflated mask planes
  hair_s{style}.bin  NGR1: mesh (pos, normal, uv)
"""
import os
import struct
import sys
import zlib

import numpy as np
from skimage import measure
from scipy.interpolate import PchipInterpolator
import fast_simplification

sys.path.insert(0, os.path.dirname(__file__))
from make_bodies import smin, ellipsoid, round_cone  # noqa: E402

HEAD_Y = 1.555
TOP, BOT = 1.80, 1.48           # head texture height range (v down)
HAIR_TOP, HAIR_BOT = 1.83, 1.36
MASK = 512
CHANNELS = ["shade", "lips", "brows", "beard", "stubble", "white", "iris", "pupil", "lash", "glint", "scalp"]


def smax(a, b, k):
    return -smin(-a, -b, k)


def sphere(p, c, r):
    return np.linalg.norm(p - np.asarray(c), axis=1) - r


def box(p, c, h):
    q = np.abs(p - np.asarray(c)) - np.asarray(h)
    return np.linalg.norm(np.maximum(q, 0), axis=1) + np.minimum(np.max(q, axis=1), 0)


def smooth01(x):
    x = np.clip(x, 0, 1)
    return x * x * (3 - 2 * x)


class Head:
    def __init__(self, frame):
        self.curvy = frame == 1

    def skull(self, p):
        """Cranium + face + jaw without the features (also the base for hair)."""
        f = self.curvy
        d = ellipsoid(p, (0, 1.68, 0.014), (0.081, 0.089, 0.097))
        d = smin(d, ellipsoid(p, (0, 1.632, -0.022), (0.067 if f else 0.069, 0.086, 0.08)), 0.03)
        d = smin(d, ellipsoid(p, (0, 1.588, -0.024), (0.053 if f else 0.062, 0.048 if f else 0.05, 0.064 if f else 0.068)), 0.03)
        return d

    def sdf(self, p):
        f = self.curvy
        d = self.skull(p)
        d = smin(d, ellipsoid(p, (0, 1.558, -0.064), (0.022 if f else 0.027, 0.024, 0.022)), 0.02)       # chin
        for s in (-1, 1):
            d = smin(d, ellipsoid(p, (s * 0.046, 1.641, -0.057), (0.026, 0.019, 0.022)), 0.02)       # cheekbones
        d = smin(d, ellipsoid(p, (0, 1.68, -0.073), (0.056, 0.011 if f else 0.013, 0.015)), 0.015)  # brow ridge
        for s in (-1, 1):
            d = smax(d, -sphere(p, (s * 0.031, 1.657, -0.099), 0.0145), 0.008)                    # eye sockets
            d = smin(d, ellipsoid(p, (s * 0.031, 1.657, -0.086), (0.0135, 0.0085, 0.006)), 0.004)  # eyeball under lids
        d = smin(d, round_cone(p, (0, 1.673, -0.086), (0, 1.626, -0.104), 0.0066, 0.0098), 0.012)  # nose bridge
        d = smin(d, sphere(p, (0, 1.621, -0.104), 0.011 if f else 0.012), 0.008)                # nose tip
        for s in (-1, 1):
            d = smin(d, ellipsoid(p, (s * 0.0125, 1.614, -0.095), (0.0095, 0.0078, 0.0088)), 0.006)  # nostril wings
        d = smin(d, ellipsoid(p, (0, 1.592, -0.077), (0.032, 0.022, 0.018)), 0.02)                # muzzle
        d = smin(d, ellipsoid(p, (0, 1.5955, -0.0925), (0.021, 0.0068 if f else 0.0058, 0.0092 if f else 0.0085)), 0.004)
        d = smin(d, ellipsoid(p, (0, 1.5848, -0.090), (0.0185, 0.0082 if f else 0.0072, 0.0098 if f else 0.0092)), 0.004)
        d = smax(d, -ellipsoid(p, (0, 1.5903, -0.101), (0.02, 0.0011, 0.012)), 0.0015)            # mouth line
        for s in (-1, 1):
            ear = ellipsoid(p, (s * 0.077, 1.645, 0.006), (0.011, 0.031, 0.02))
            ear = smax(ear, -ellipsoid(p, (s * 0.087, 1.643, 0.002), (0.004, 0.018, 0.01)), 0.003)
            d = smin(d, ear, 0.008)
        d = smin(d, round_cone(p, (0, 1.49, 0.016), (0, 1.6, 0.016), 0.039 if f else 0.044, 0.039 if f else 0.044), 0.02)
        return d


# ---------------------------------------------------------------- meshing helpers


def mesh_sdf(fn, lo, hi, step, target):
    xs = np.arange(lo[0], hi[0] + step, step)
    ys = np.arange(lo[1], hi[1] + step, step)
    zs = np.arange(lo[2], hi[2] + step, step)
    X, Y, Z = np.meshgrid(xs, ys, zs, indexing="ij")
    pts = np.stack([X.ravel(), Y.ravel(), Z.ravel()], 1)
    vol = np.concatenate([fn(pts[i:i + 300_000]) for i in range(0, len(pts), 300_000)]).reshape(X.shape)
    v, f, _, _ = measure.marching_cubes(vol, 0.0, spacing=(step, step, step))
    v += np.asarray(lo)
    if len(v) > target:
        v, f = fast_simplification.simplify(v.astype(np.float32), f.astype(np.int64), target_reduction=1 - target / len(v), agg=7)
    v = v.astype(np.float64)
    for _ in range(3):
        n = grad(fn, v)
        v = v - n * fn(v)[:, None]
    return v, f, grad(fn, v)


def grad(fn, v, e=0.0008):
    g = np.zeros_like(v)
    for i in range(3):
        o = np.zeros(3); o[i] = e
        g[:, i] = fn(v + o) - fn(v - o)
    return g / np.maximum(np.linalg.norm(g, axis=1, keepdims=True), 1e-9)


def cyl_uv(v, top, bot):
    phi = np.arctan2(v[:, 0], -v[:, 2])
    return 0.5 + phi / (2 * np.pi), np.clip((top - v[:, 1]) / (top - bot), 0, 1)


def split_seam(v, n, f, u, vv):
    """Duplicate vertices where triangles cross the seam at the back so u doesn't wrap."""
    nv, nn, uv, remap = list(v), list(n), [(a, b) for a, b in zip(u, vv)], {}
    f = f.copy()
    for t in range(len(f)):
        us = u[f[t]]
        if us.max() - us.min() > 0.5:
            for c in range(3):
                k = f[t, c]
                if u[k] < 0.5:
                    if k not in remap:
                        remap[k] = len(nv)
                        nv.append(v[k]); nn.append(n[k]); uv.append((min(1.0, u[k] + 1.0), vv[k]))
                    f[t, c] = remap[k]
    return np.array(nv), np.array(nn), np.array(uv), f


# ---------------------------------------------------------------- face masks


def surface_points(head, size):
    """For each texel, the head surface point it shows (marching in from outside)."""
    us = (np.arange(size) + 0.5) / size
    vs = (np.arange(size) + 0.5) / size
    U, V = np.meshgrid(us, vs)
    phi = (U - 0.5) * 2 * np.pi
    y = TOP - V * (TOP - BOT)
    d = np.stack([np.sin(phi), np.zeros_like(phi), -np.cos(phi)], -1).reshape(-1, 3)
    base = np.stack([np.zeros_like(y), y, np.zeros_like(y)], -1).reshape(-1, 3)
    r = np.full(len(d), 0.16)
    lo = np.zeros(len(d))
    hit = np.zeros(len(d), bool)
    # Step inward until inside, then bisect.
    for r_try in np.arange(0.16, 0.0, -0.004):
        p = base + d * r_try
        inside = head.sdf(p) < 0
        newly = inside & ~hit
        lo[newly] = r_try
        hit |= inside
    hi = lo + 0.004
    for _ in range(12):
        mid = (lo + hi) / 2
        ins = head.sdf(base + d * mid[:, None]) < 0
        lo = np.where(ins, mid, lo)
        hi = np.where(ins, hi, mid)
    p = base + d * lo[:, None]
    return p, hit


def face_masks(head, size=MASK):
    p, hit = surface_points(head, size)
    x, y, z = p[:, 0], p[:, 1], p[:, 2]
    ax = np.abs(x)
    front = z < -0.03
    f = head.curvy
    out = {}

    # Shading: occlusion from the field plus soft modelling.
    n = grad(head.sdf, p)
    occ = np.zeros(len(p)); w = 1.0
    for i in range(1, 6):
        h = 0.004 * i
        dd = head.sdf(p + n * h)
        occ += (h - np.minimum(dd, h)) * w
        w *= 0.7
    shade = np.clip(1 - 22 * occ, 0.55, 1.0)
    # Under-brow and nose-side shadows, a little light on cheeks.
    shade *= 1 - 0.08 * np.exp(-((ax - 0.031) ** 2 / 0.0003 + (y - 1.668) ** 2 / 0.00006)) * front
    out["shade"] = shade

    # Eyes (front projection around each eye centre).
    ex, ey = 0.031, 1.6575
    outer = ax - ex                              # >0 towards the ear
    hw = 0.0148 if f else 0.0142
    t = np.clip(outer / hw, -1.2, 1.2)
    upper = ey + (0.0068 if f else 0.0062) * np.clip(1 - t ** 2, 0, 1) ** 0.75 + 0.0008 * t   # outer corner a touch higher
    lower = ey - 0.0046 * np.clip(1 - t ** 2, 0, 1) ** 0.9 + 0.0006 * t
    inside_eye = (np.abs(t) < 1) & (y < upper) & (y > lower) & front
    soft_edge = np.minimum(np.clip((upper - y) / 0.0006, 0, 1), np.clip((y - lower) / 0.0006, 0, 1))
    white = inside_eye * soft_edge * np.clip((1 - np.abs(t)) / 0.08, 0, 1)
    out["white"] = white
    ir = 0.0068 if f else 0.0065
    dist = np.sqrt((ax - ex) ** 2 + (y - (ey + 0.0004)) ** 2)
    out["iris"] = white * np.clip((ir - dist) / 0.0006, 0, 1)
    out["pupil"] = white * np.clip((ir * 0.42 - dist) / 0.0006, 0, 1) + 0.35 * out["iris"] * np.clip((dist - ir * 0.7) / (ir * 0.3), 0, 1)
    gx = ex - 0.0018                     # catchlight up and towards the nose
    gdist = np.sqrt((ax - gx) ** 2 + (y - (ey + 0.0022)) ** 2)
    out["glint"] = white * np.clip((0.0012 - gdist) / 0.0005, 0, 1)
    # Lash line along the upper lid (with a little flick on curvy frames), lower lid faint.
    lash_w = 0.0011 if f else 0.0008
    lash = (np.abs(t) < (1.18 if f else 1.04)) & front
    up_line = upper + (0.0012 * np.clip(t - 0.8, 0, 1) / 0.3 if f else 0)
    lash_v = lash * np.clip(1 - np.abs(y - up_line - lash_w * 0.4) / lash_w, 0, 1)
    low_v = (np.abs(t) < 0.95) * front * np.clip(1 - np.abs(y - lower) / 0.0005, 0, 1) * 0.35
    out["lash"] = np.maximum(lash_v, low_v)

    # Brows: an arch above each eye, thicker towards the nose, tapering at the tail.
    bt = (ax - 0.012) / 0.04                       # 0 at the inner end, 1 at the tail
    by = 1.6735 + 0.0055 * np.sin(np.clip(bt, 0, 1) * np.pi * 0.85) - 0.002 * bt
    thick = (0.0028 if f else 0.0038) * (1 - 0.6 * np.clip(bt, 0, 1))
    brow = (bt > 0) & (bt < 1) & front
    out["brows"] = brow * np.clip(1 - np.abs(y - by) / thick, 0, 1) ** 0.6 * np.clip(bt / 0.08, 0, 1) * np.clip((1 - bt) / 0.1, 0, 1)

    # Lips: upper lip with a cupid's bow, fuller lower lip.
    lw = 0.0215 if f else 0.0205
    lt = np.clip(ax / lw, 0, 1.2)
    mouth_y = 1.5903
    bow = 0.0012 * np.exp(-((ax - 0.006) ** 2) / 0.00002) - 0.0008 * np.exp(-(ax ** 2) / 0.000008)
    up_top = mouth_y + (0.0062 if f else 0.0052) * np.clip(1 - lt ** 2, 0, 1) ** 0.6 + bow
    lo_bot = mouth_y - (0.0085 if f else 0.007) * np.clip(1 - lt ** 2, 0, 1) ** 0.55
    lips = (lt < 1) & (y < up_top) & (y > lo_bot) & front
    out["lips"] = lips * np.minimum(np.clip((up_top - y) / 0.0007, 0, 1), np.clip((y - lo_bot) / 0.0009, 0, 1)) \
        * np.clip((1 - lt) / 0.1, 0, 1)

    # Beard: jaw, chin, sideburns and a moustache, soft-edged; not the lips or upper cheeks.
    phi = np.abs(np.arctan2(x, -z))
    cheek_line = 1.613 - 0.01 * np.clip((0.04 - ax) / 0.04, 0, 1)
    burn = smooth01((phi - 1.1) / 0.12) * smooth01((1.52 - phi) / 0.06)
    side_line = cheek_line + (1.662 - cheek_line) * burn
    beard = smooth01((side_line - y) / 0.008) * smooth01((y - 1.505) / 0.03) * smooth01((1.66 - phi) / 0.3)
    hole = np.sqrt((ax / (lw + 0.004)) ** 2 + ((y - (mouth_y - 0.001)) / 0.0105) ** 2)
    beard *= smooth01((hole - 0.92) / 0.18)
    mous = smooth01(((lw + 0.006) - ax) / 0.006) * smooth01((y - (mouth_y + 0.0058)) / 0.002) \
        * smooth01(((mouth_y + 0.0148) - y) / 0.003) * front
    out["beard"] = np.maximum(beard, mous)
    out["stubble"] = out["beard"]
    # Scalp under the hair (tinted with the hair colour so hairlines blend).
    line = hairline(np.arctan2(x, -z))
    out["scalp"] = smooth01((y - (line - 0.004)) / 0.014)

    planes = {}
    for k in CHANNELS:
        a = np.clip(out[k], 0, 1).reshape(size, size)
        a[~hit.reshape(size, size)] = 0 if k != "shade" else 1
        planes[k] = np.round(a * 255).astype(np.uint8)
    return planes


# ---------------------------------------------------------------- hair

def hairline(phi, lowered=0.0):
    """Height of the hairline around the head (phi 0 = front)."""
    ap = np.abs(phi)
    xs = np.array([0.0, 0.5, 0.95, 1.2, 1.45, 1.75, 2.1, 2.5, np.pi])
    ys = np.array([1.726, 1.72, 1.7, 1.668, 1.684, 1.672, 1.632, 1.598, 1.588])
    return PchipInterpolator(xs, ys)(ap) - lowered


def hair_sdf(head, style):
    skull = head.skull
    def face_box(p, h=1.695):
        """The face and the front of the neck, kept clear of hair."""
        cy = (h + 1.5) / 2
        oval = (np.sqrt((p[:, 0] / 0.067) ** 2 + (np.maximum(p[:, 1] - 1.6, 0) / (h - 1.6)) ** 2) - 1) * 0.067
        slot = np.maximum(oval, -0.0 - p[:, 2] * 0 + (p[:, 2] + 0.03))     # only in front (z < -0.03)
        neck = box(p, (0, 1.4, -0.08), (0.062, 0.2, 0.08))
        return smin(slot, neck, 0.01)

    def shell(p, t, lowered=0.0, lift=0.0):
        phi = np.arctan2(p[:, 0], -p[:, 2])
        line = hairline(phi, lowered)
        thick = t + lift * smooth01((p[:, 1] - 1.72) / 0.05) * np.clip(np.cos(phi) * 0.6 + 0.6, 0, 1)
        thick = thick * (0.3 + 0.7 * smooth01((p[:, 1] - line) / 0.03))
        d = skull(p) - thick
        cut = line - p[:, 1]
        return smax(d, cut, 0.004)

    def fn(p):
        if style == 0:    # short: close at the sides, more on top with a little lift at the front
            return shell(p, 0.004 + 0.011 * smooth01((p[:, 1] - 1.69) / 0.06), lift=0.01)
        if style == 1:    # buzz
            return shell(p, 0.0028)
        if style == 2:    # curls: a rounded volume with bumps
            phi = np.arctan2(p[:, 0], -p[:, 2])
            bumps = 0.0045 * np.sin(p[:, 0] * 260) * np.sin(p[:, 1] * 240) * np.sin(p[:, 2] * 250)
            return shell(p, 0.026 + 0.008 * smooth01((p[:, 1] - 1.66) / 0.08), lowered=-0.004) - bumps
        if style == 3:    # long: the head's outline carried down past the shoulders, open at the face
            d = shell(p, 0.011, lift=0.004)
            q = p[:, [0, 2]] - [0, 0.012]
            drop = np.clip((1.66 - p[:, 1]) / 0.26, 0, 1)
            rx, rz = 0.094 + 0.012 * drop, 0.104 + 0.006 * drop
            curtain = (np.sqrt((q[:, 0] / rx) ** 2 + (q[:, 1] / rz) ** 2) - 1) * 0.095
            phi = np.arctan2(p[:, 0], -p[:, 2])
            ends = 1.39 + 0.07 * smooth01((0.9 - np.abs(phi)) / 0.9)       # longer at the back
            curtain = smax(curtain, ends - p[:, 1], 0.015)
            curtain = smax(curtain, p[:, 1] - 1.70, 0.03)
            d = smin(d, curtain, 0.02)
            return smax(d, -face_box(p, 1.71), 0.008)
        if style == 4:    # bun
            d = shell(p, 0.0055)
            d = smin(d, sphere(p, (0, 1.748, 0.075), 0.036), 0.012)
            return d
        if style == 5:    # locs
            d = shell(p, 0.012)
            for k in range(16):
                a = 0.95 + (2 * np.pi - 1.9) * k / 15
                top = np.array([np.sin(a) * 0.085, 1.665, -np.cos(a) * 0.088 + 0.012])
                bot = top * np.array([1.18, 0, 1.18]) + np.array([0, 1.45 + 0.02 * (k % 3), 0.01])
                d = smin(d, round_cone(p, top, bot, 0.0105, 0.009), 0.006)
            return smax(d, -face_box(p, 1.70), 0.004)
        if style == 6:    # bob with bangs: to the jaw, flaring a little
            phi = np.arctan2(p[:, 0], -p[:, 2])
            flare = 0.016 + 0.018 * smooth01((1.665 - p[:, 1]) / 0.08)
            d = skull(p) - flare
            # Fill below the skull at the sides and back down to the cut.
            col = ellipsoid(p, (0, 1.64, 0.012), (0.098, 0.13, 0.112))
            d = smin(d, col, 0.02)
            line = np.where(np.abs(phi) < 0.75, 1.684, 1.565)
            d = smax(d, line - p[:, 1], 0.004)
            return smax(d, -face_box(p, 1.684), 0.006)
        if style == 7:    # ponytail
            d = shell(p, 0.0055)
            d = smin(d, sphere(p, (0, 1.70, 0.1), 0.02), 0.01)
            tail = round_cone(p, (0, 1.70, 0.105), (0, 1.62, 0.13), 0.022, 0.028)
            tail = smin(tail, round_cone(p, (0, 1.62, 0.13), (0, 1.47, 0.115), 0.028, 0.01), 0.01)
            return smin(d, tail, 0.012)
        raise ValueError(style)
    return fn


# ---------------------------------------------------------------- output


def write_head(path, v, n, uv, f, planes):
    with open(path, "wb") as fh:
        fh.write(b"NGH1")
        fh.write(struct.pack("<IIII", 1, len(v), len(f), MASK))
        fh.write((v - [0, HEAD_Y, 0]).astype("<f4").tobytes())
        fh.write(n.astype("<f4").tobytes())
        fh.write(uv.astype("<f4").tobytes())
        fh.write(f.astype("<u2").tobytes())
        raw = b"".join(planes[k].tobytes() for k in CHANNELS)
        co = zlib.compressobj(9, zlib.DEFLATED, -15)
        comp = co.compress(raw) + co.flush()
        fh.write(struct.pack("<I", len(comp)))
        fh.write(comp)


def write_hair(path, v, n, uv, f):
    with open(path, "wb") as fh:
        fh.write(b"NGR1")
        fh.write(struct.pack("<III", 1, len(v), len(f)))
        fh.write((v - [0, HEAD_Y, 0]).astype("<f4").tobytes())
        fh.write(n.astype("<f4").tobytes())
        fh.write(uv.astype("<f4").tobytes())
        fh.write(f.astype("<u2").tobytes())


def make_head(frame):
    head = Head(frame)
    v, f, n = mesh_sdf(head.sdf, (-0.1, 1.48, -0.13), (0.1, 1.8, 0.13), 0.0022, 4200)
    keep = v[:, 1] > 1.495
    # Drop the bottom of the neck stub (hidden in the body).
    idx = np.full(len(v), -1); idx[keep] = np.arange(keep.sum())
    f = f[np.all(keep[f], axis=1)]
    f = idx[f]; v = v[keep]; n = n[keep]
    u, vv = cyl_uv(v, TOP, BOT)
    v, n, uv, f = split_seam(v, n, f, u, vv)
    return head, v, n, uv, f


def make_hair(style):
    head = Head(0)
    fn = hair_sdf(head, style)
    v, f, n = mesh_sdf(fn, (-0.15, 1.36, -0.15), (0.15, 1.84, 0.19), 0.0024, 3600)
    u, vv = cyl_uv(v, HAIR_TOP, HAIR_BOT)
    return split_seam(v, n, f, u, vv)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "NeonGetaway", "Scene", "Bodies")
    os.makedirs(out, exist_ok=True)
    only = os.environ.get("ONLY", "")
    for frame in (0, 1):
        if only and only != f"head{frame}" and only != "heads":
            continue
        head, v, n, uv, f = make_head(frame)
        planes = face_masks(head)
        write_head(os.path.join(out, f"head_f{frame}.bin"), v, n, uv, f, planes)
        print("head", frame, len(v), len(f))
    for style in range(8):
        if only and only != f"hair{style}" and only != "hair":
            continue
        v, n, uv, f = make_hair(style)
        assert len(v) < 65536
        write_hair(os.path.join(out, f"hair_s{style}.bin"), v, n, uv, f)
        print("hair", style, len(v), len(f))


if __name__ == "__main__":
    main()
