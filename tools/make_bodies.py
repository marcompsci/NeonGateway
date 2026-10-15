#!/usr/bin/env python3
"""Builds the skinned body meshes for Neon Getaway's 3D people.

Each body is one smooth, continuous surface (torso, neck, arms with hands, legs with feet in
shoes) made from a signed distance field of soft anatomical shapes, meshed with marching cubes,
simplified, and given:
  * bone weights for the rig in Scene/Human3D.swift (same joint order),
  * a UV atlas (torso / left arm / right arm / left leg / right leg as cylinders) that the app
    paints clothes, skin and shoes onto,
  * baked ambient occlusion as a vertex shade.

The mesh is built in a relaxed A-pose (arms out, legs a little apart) so arms and legs don't
fuse with the body; the app binds with the same angles and poses from there.

Output: NeonGetaway/Scene/Bodies/body_b{build}_f{frame}_{hi|lo}.bin

Usage: python3 tools/make_bodies.py [outdir] [--preview dir]
"""
import os
import struct
import sys

import numpy as np
from scipy.interpolate import PchipInterpolator
from scipy import sparse
from skimage import measure
import fast_simplification

BUILDS = [0.9, 1.0, 1.08, 1.18]   # slim, average, athletic, broad
ARM_OUT = 0.42                    # bind-pose arm spread (rad)
LEG_OUT = 0.06                    # bind-pose leg spread (rad)
BONES = ["hips", "spine", "chest", "neck", "head", "shoulderL", "elbowL", "shoulderR", "elbowR",
         "thighL", "kneeL", "thighR", "kneeR"]
B = {n: i for i, n in enumerate(BONES)}

# Atlas rects (u0, v0, w, h) in texture space, v down.
RECTS = {"torso": (0.0, 0.0, 0.5, 0.5), "armL": (0.5, 0.0, 0.25, 0.5), "armR": (0.75, 0.0, 0.25, 0.5),
         "legL": (0.0, 0.5, 0.5, 0.5), "legR": (0.5, 0.5, 0.5, 0.5)}
# Height range painted into each region's rect (top, bottom) in rest-pose metres.
VRANGE = {"torso": (1.70, 0.75), "armL": (1.56, 0.62), "armR": (1.56, 0.62), "legL": (1.02, -0.02), "legR": (1.02, -0.02)}
REGIONS = ["torso", "armL", "armR", "legL", "legR"]

# ---------------------------------------------------------------- SDF primitives


def smin(a, b, k):
    if k <= 0:
        return np.minimum(a, b)
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b * (1 - h) + a * h - k * h * (1 - h)


def ellipsoid(p, c, r):
    q = (p - np.asarray(c)) / np.asarray(r)
    k0 = np.linalg.norm(q, axis=1)
    k1 = np.linalg.norm(q / np.asarray(r), axis=1)
    return k0 * (k0 - 1) / np.maximum(k1, 1e-9)


def round_cone(p, a, b, r1, r2):
    """Tapered capsule from a (radius r1) to b (radius r2) (iq)."""
    a = np.asarray(a, float); b = np.asarray(b, float)
    ba = b - a
    l2 = ba @ ba
    rr = r1 - r2
    a2 = l2 - rr * rr
    il2 = 1.0 / l2
    pa = p - a
    y = pa @ ba
    z = y - l2
    xv = pa * l2 - np.outer(y, ba)
    x2 = np.einsum("ij,ij->i", xv, xv)
    y2 = y * y * l2
    z2 = z * z * l2
    k = np.sign(rr) * rr * rr * x2
    out = (np.sqrt(x2 * a2 * il2) + y * rr) * il2 - r1
    m1 = np.sign(z) * a2 * z2 > k
    m2 = np.sign(y) * a2 * y2 < k
    out = np.where(m1, np.sqrt(x2 + z2) * il2 - r2, out)
    out = np.where(m2 & ~m1, np.sqrt(x2 + y2) * il2 - r1, out)
    return out


def rot_z(p, centre, ang):
    """Rotate points about the Z axis through `centre` by `ang` (SceneKit's euler z)."""
    c, s = np.cos(ang), np.sin(ang)
    q = p - centre
    return np.stack([q[:, 0] * c - q[:, 1] * s, q[:, 0] * s + q[:, 1] * c, q[:, 2]], axis=1) + centre


# ---------------------------------------------------------------- the body

TORSO = {
    # y, half width, half depth back, half depth front (wide = 1)
    0: [(0.80, .110, .060, .050), (0.84, .148, .090, .080), (0.90, .164, .106, .090), (0.96, .166, .104, .094), (1.02, .156, .094, .096),
        (1.08, .146, .090, .098), (1.14, .150, .092, .100), (1.22, .160, .097, .106), (1.30, .170, .100, .112),
        (1.36, .174, .100, .110), (1.42, .172, .094, .088), (1.46, .150, .082, .070), (1.50, .092, .064, .056),
        (1.53, .058, .056, .050)],
    1: [(0.80, .118, .066, .050), (0.84, .156, .100, .080), (0.90, .180, .118, .090), (0.96, .178, .112, .092), (1.02, .158, .098, .090),
        (1.08, .132, .086, .086), (1.14, .134, .086, .088), (1.22, .144, .090, .094), (1.30, .150, .092, .098),
        (1.36, .152, .092, .094), (1.42, .148, .088, .080), (1.46, .132, .078, .066), (1.50, .086, .060, .052),
        (1.53, .054, .052, .048)],
}


class Body:
    def __init__(self, build, frame):
        self.wide = BUILDS[build]
        self.curvy = frame == 1
        w = self.wide
        t = np.array(TORSO[frame])
        self.ty0, self.ty1 = t[0, 0], t[-1, 0]
        self.f_hw = PchipInterpolator(t[:, 0], t[:, 1] * w)
        self.f_back = PchipInterpolator(t[:, 0], t[:, 2] * w ** 0.6)
        self.f_front = PchipInterpolator(t[:, 0], t[:, 3] * w ** 0.6)
        self.armX = float(self.f_hw(1.42)) + 0.012
        self.legX = 0.086 * w * (1.08 if self.curvy else 1.0)
        self.armS = w ** 0.8 * (0.88 if self.curvy else 1.0)
        self.legS = w ** 0.7 * (1.06 if self.curvy else 1.0)
        self.joints = {
            "hips": (0, 0.95, 0), "spine": (0, 1.03, 0), "chest": (0, 1.21, 0), "neck": (0, 1.48, 0),
            "head": (0, 1.555, 0),
            "shoulderL": (-self.armX, 1.44, 0), "elbowL": (-self.armX, 1.16, 0),
            "shoulderR": (self.armX, 1.44, 0), "elbowR": (self.armX, 1.16, 0),
            "thighL": (-self.legX, 0.91, 0), "kneeL": (-self.legX, 0.48, 0),
            "thighR": (self.legX, 0.91, 0), "kneeR": (self.legX, 0.48, 0),
        }

    # Torso: lofted ellipses with separate front/back depth.
    def torso(self, p):
        y = np.clip(p[:, 1], self.ty0, self.ty1)
        hw = self.f_hw(y)
        rz = np.where(p[:, 2] < 0, self.f_front(y), self.f_back(y))
        q = np.sqrt((p[:, 0] / hw) ** 2 + (p[:, 2] / rz) ** 2)
        d = (q - 1) * np.minimum(hw, rz)
        d = np.maximum(d, self.ty0 - p[:, 1])
        d = np.maximum(d, p[:, 1] - self.ty1)
        return d

    def arm_parts(self, p, side):
        """Distances for (deltoid, upper arm, forearm+hand) of one arm, in the arm's own frame."""
        s = self.armS
        sh = np.array([side * self.armX, 1.44, 0.0])
        q = rot_z(p, sh, -side * ARM_OUT)   # undo the bind spread: evaluate in the hanging frame
        x = side * self.armX
        delt = ellipsoid(q, (x + side * 0.006, 1.425, 0.002), (0.056 * s, 0.072 * s, 0.058 * s))
        upper = round_cone(q, (x, 1.42, 0.0), (x, 1.17, 0.006), 0.047 * s, 0.037 * s)
        bicep = ellipsoid(q, (x, 1.30, -0.008), (0.044 * s, 0.075, 0.046 * s))
        upper = smin(upper, bicep, 0.02)
        fore = round_cone(q, (x, 1.16, 0.006), (x, 0.935, 0.0), 0.039 * s, 0.025 * s)
        fmus = ellipsoid(q, (x, 1.09, -0.002), (0.041 * s, 0.075, 0.040 * s))
        fore = smin(fore, fmus, 0.02)
        # Hand: palm faces the thigh (thin in x), thumb forward, fingers together and slightly curled.
        hs = 0.95 if self.curvy else 1.0
        palm = ellipsoid(q, (x, 0.87, -0.004), (0.017 * hs, 0.05 * hs, 0.039 * hs))
        hand = smin(fore, palm, 0.018)
        for i, fz in enumerate([-0.024, -0.008, 0.008, 0.023]):
            ln = [0.072, 0.08, 0.076, 0.064][i] * hs
            tip = (x - side * 0.004, 0.84 - ln, fz * hs + 0.006)
            f = round_cone(q, (x, 0.845, fz * hs), tip, 0.0095 * hs, 0.0078 * hs)
            hand = smin(hand, f, 0.006)
        thumb = round_cone(q, (x - side * 0.004, 0.895, -0.03 * hs), (x - side * 0.008, 0.835, -0.052 * hs), 0.012 * hs, 0.0085 * hs)
        hand = smin(hand, thumb, 0.012)
        return delt, upper, hand

    def leg_parts(self, p, side):
        s = self.legS
        hip = np.array([side * self.legX, 0.91, 0.0])
        q = rot_z(p, hip, -(side * LEG_OUT))
        x = side * self.legX
        thigh = round_cone(q, (x, 0.92, 0.004), (x, 0.5, 0.0), 0.094 * s, 0.05 * s)
        quad = ellipsoid(q, (x + side * 0.004, 0.74, -0.012), (0.072 * s, 0.14, 0.072 * s))
        thigh = smin(thigh, quad, 0.03)
        knee = ellipsoid(q, (x, 0.475, -0.006), (0.044 * s, 0.05, 0.046 * s))
        thigh = smin(thigh, knee, 0.035)
        shin = round_cone(q, (x, 0.47, 0.002), (x, 0.085, 0.006), 0.046 * s, 0.029 * s)
        calf = ellipsoid(q, (x + side * 0.004, 0.33, 0.016), (0.048 * s, 0.1, 0.05 * s))
        shin = smin(shin, calf, 0.03)
        # Shoe: heel and toe box, flat sole at y = 0.
        heel = ellipsoid(q, (x, 0.05, 0.03), (0.041, 0.05, 0.052))
        toe = ellipsoid(q, (x - side * 0.004, 0.04, -0.085), (0.047, 0.04, 0.098))
        shoe = smin(heel, toe, 0.03)
        shoe = np.maximum(shoe, -q[:, 1])
        shin = smin(shin, shoe, 0.025)
        return thigh, shin

    def parts(self, p):
        """All labelled pieces: list of (label, distance, blend k)."""
        out = []
        torso = self.torso(p)
        gs = self.wide ** 0.7 * (1.12 if self.curvy else 1.0)
        for side in (-1, 1):
            g = ellipsoid(p, (side * 0.068 * self.wide, 0.9, 0.046 * gs), (0.084 * gs, 0.09 * gs, 0.07 * gs))
            torso = smin(torso, g, 0.04)
        if self.curvy:
            for side in (-1, 1):
                br = ellipsoid(p, (side * 0.062, 1.30, -0.076 * self.wide ** 0.6), (0.066, 0.064, 0.056))
                torso = smin(torso, br, 0.05)
        else:
            for side in (-1, 1):
                pec = ellipsoid(p, (side * 0.07 * self.wide, 1.34, -0.066 * self.wide ** 0.6), (0.075, 0.055, 0.045))
                torso = smin(torso, pec, 0.05)
        out.append(("torso", torso, 0.0))
        nr = 0.051 if self.curvy else 0.058
        neck = round_cone(p, (0, 1.45, 0.01), (0, 1.64, 0.016), nr, nr * 0.9)
        out.append(("neck", neck, 0.035))
        for side, tag in ((-1, "L"), (1, "R")):
            trap = round_cone(p, (0, 1.54, 0.022), (side * (self.armX - 0.03), 1.465, 0.012), 0.036, 0.034)
            out.append(("trap" + tag, trap, 0.045))
            delt, upper, hand = self.arm_parts(p, side)
            out.append(("delt" + tag, delt, 0.035))
            out.append(("upper" + tag, upper, 0.02))
            out.append(("fore" + tag, hand, 0.02))
            thigh, shin = self.leg_parts(p, side)
            out.append(("thigh" + tag, thigh, 0.06))
            out.append(("shin" + tag, shin, 0.02))
        return out

    def sdf(self, p, labels=False):
        parts = self.parts(p)
        d = parts[0][1]
        for _, di, k in parts[1:]:
            d = smin(d, di, k)
        if labels:
            raw = np.stack([di for _, di, _ in parts], axis=1)
            return d, [n for n, _, _ in parts], raw
        return d

    def sdf_chunked(self, p, n=400_000):
        return np.concatenate([self.sdf(p[i:i + n]) for i in range(0, len(p), n)])


# ---------------------------------------------------------------- meshing


def build_mesh(body, step):
    lo = np.array([-0.62, -0.012, -0.24])
    hi = np.array([0.62, 1.70, 0.2])
    xs = np.arange(lo[0], hi[0] + step, step)
    ys = np.arange(lo[1], hi[1] + step, step)
    zs = np.arange(lo[2], hi[2] + step, step)
    X, Y, Z = np.meshgrid(xs, ys, zs, indexing="ij")
    pts = np.stack([X.ravel(), Y.ravel(), Z.ravel()], axis=1)
    vol = body.sdf_chunked(pts).reshape(X.shape)
    verts, faces, _, _ = measure.marching_cubes(vol, 0.0, spacing=(step, step, step))
    verts += lo
    return verts.astype(np.float64), faces


def simplify(verts, faces, target):
    reduction = 1 - target / len(verts)
    v, f = fast_simplification.simplify(verts.astype(np.float32), faces.astype(np.int64), target_reduction=reduction, agg=7)
    return v.astype(np.float64), f


def project_to_surface(body, v, iters=3):
    for _ in range(iters):
        d = body.sdf(v)
        n = gradient(body, v)
        v = v - n * d[:, None]
    return v


def gradient(body, v, e=0.0015):
    g = np.zeros_like(v)
    for i in range(3):
        o = np.zeros(3); o[i] = e
        g[:, i] = body.sdf(v + o) - body.sdf(v - o)
    return g / np.maximum(np.linalg.norm(g, axis=1, keepdims=True), 1e-9)


def ambient_occlusion(body, v, n):
    occ = np.zeros(len(v))
    w = 1.0
    for i in range(1, 7):
        h = 0.012 * i
        d = body.sdf(v + n * h)
        occ += (h - np.minimum(d, h)) * w
        w *= 0.7
    return np.clip(1.0 - 9.0 * occ, 0.45, 1.0)


# ---------------------------------------------------------------- weights


def torso_bones(y):
    """Weights along the spine by height (mirrors the old tube rig)."""
    W = np.zeros((len(y), len(BONES)))

    def blend(mask, t, a, b):
        t = np.clip(t, 0, 1)
        W[mask, B[a]] += 1 - t[mask]
        W[mask, B[b]] += t[mask]
    m = y < 1.0; W[m, B["hips"]] = 1
    m = (y >= 1.0) & (y < 1.12); blend(m, (y - 1.0) / 0.12, "hips", "spine")
    m = (y >= 1.12) & (y < 1.26); blend(m, (y - 1.12) / 0.14, "spine", "chest")
    m = (y >= 1.26) & (y < 1.48); W[m, B["chest"]] = 1
    m = (y >= 1.48) & (y < 1.56); blend(m, (y - 1.48) / 0.08, "chest", "neck")
    m = y >= 1.56; blend(m, (y - 1.56) / 0.07, "neck", "head")
    return W


def weights_for(body, v, label_names, raw):
    lab = np.array(label_names)[np.argmin(raw, axis=1)]
    W = torso_bones(v[:, 1])   # torso and neck default
    for side, tag in ((-1, "L"), (1, "R")):
        sh = np.array(body.joints["shoulder" + tag])
        hip = np.array(body.joints["thigh" + tag])
        qa = rot_z(v, sh, -side * ARM_OUT)        # arm-local (hanging) coordinates
        ql = rot_z(v, hip, -side * LEG_OUT)
        S, E = B["shoulder" + tag], B["elbow" + tag]
        T, K = B["thigh" + tag], B["knee" + tag]

        def setrow(mask, pairs):
            W[mask] = 0
            for bone, wt in pairs:
                W[mask, bone] += wt[mask] if isinstance(wt, np.ndarray) else wt

        m = lab == "trap" + tag
        f = np.clip((np.abs(v[:, 0]) - 0.05) / (body.armX - 0.05), 0, 1) * 0.45
        setrow(m, [(B["chest"], 1 - f), (S, f)])
        m = lab == "delt" + tag
        f = np.clip((np.abs(v[:, 0]) - (body.armX - 0.05)) / 0.07, 0, 1)
        setrow(m, [(B["chest"], (1 - f) * 0.5), (S, 0.5 + 0.5 * f)])
        m = lab == "upper" + tag
        t = np.clip((1.24 - qa[:, 1]) / 0.12, 0, 1) * 0.5
        setrow(m, [(S, 1 - t), (E, t)])
        m = lab == "fore" + tag
        t = np.clip((qa[:, 1] - 1.1) / 0.12, 0, 1) * 0.5
        setrow(m, [(E, 1 - t), (S, t)])
        m = lab == "thigh" + tag
        top = np.clip((ql[:, 1] - 0.86) / 0.1, 0, 1) * 0.5
        bot = np.clip((0.56 - ql[:, 1]) / 0.1, 0, 1) * 0.5
        setrow(m, [(T, 1 - top - bot), (B["hips"], top), (K, bot)])
        m = lab == "shin" + tag
        t = np.clip((ql[:, 1] - 0.42) / 0.1, 0, 1) * 0.5
        setrow(m, [(K, 1 - t), (T, t)])
    # Inner thigh / crotch on the torso label: share with the nearer thigh.
    m = (lab == "torso") & (v[:, 1] < 0.9)
    f = np.clip((0.9 - v[:, 1]) / 0.08, 0, 1) * 0.6
    for tag, sgn in (("L", -1), ("R", 1)):
        mm = m & (np.sign(v[:, 0]) == sgn)
        W[mm] *= (1 - f[mm])[:, None]
        W[mm, B["thigh" + tag]] += f[mm]
    return W, lab


def smooth_weights(W, faces, n, iters):
    i = np.concatenate([faces[:, 0], faces[:, 1], faces[:, 2], faces[:, 1], faces[:, 2], faces[:, 0]])
    j = np.concatenate([faces[:, 1], faces[:, 2], faces[:, 0], faces[:, 0], faces[:, 1], faces[:, 2]])
    A = sparse.coo_matrix((np.ones(len(i)), (i, j)), shape=(n, n)).tocsr()
    A.data[:] = 1
    deg = np.asarray(A.sum(axis=1)).ravel()
    for _ in range(iters):
        W = 0.5 * W + 0.5 * (A @ W) / np.maximum(deg, 1)[:, None]
    return W


def top4(W):
    idx = np.argsort(-W, axis=1)[:, :4]
    w = np.take_along_axis(W, idx, axis=1)
    w = np.maximum(w, 0)
    w /= np.maximum(w.sum(axis=1, keepdims=True), 1e-9)
    return idx.astype(np.uint8), w


# ---------------------------------------------------------------- UVs


def region_of(lab):
    r = np.full(len(lab), "torso", dtype=object)
    for tag in ("L", "R"):
        r[np.isin(lab, ["delt" + tag, "upper" + tag, "fore" + tag])] = "arm" + tag
        r[np.isin(lab, ["thigh" + tag, "shin" + tag])] = "leg" + tag
    return r


def rest_coords(body, v, region):
    """Rest-pose (arms hanging, legs straight) coordinates of each vertex for its region."""
    if region.startswith("arm"):
        tag = region[-1]
        side = -1 if tag == "L" else 1
        return rot_z(v, np.array(body.joints["shoulder" + tag]), -side * ARM_OUT)
    if region.startswith("leg"):
        tag = region[-1]
        side = -1 if tag == "L" else 1
        return rot_z(v, np.array(body.joints["thigh" + tag]), -side * LEG_OUT)
    return v


def uv_for(body, q, region):
    if region == "torso":
        cx = 0.0
    elif region.startswith("arm"):
        cx = (-1 if region[-1] == "L" else 1) * body.armX
    else:
        cx = (-1 if region[-1] == "L" else 1) * body.legX
    phi = np.arctan2(q[:, 0] - cx, -q[:, 2])       # 0 at the front
    u = 0.5 + phi / (2 * np.pi)
    top, bot = VRANGE[region]
    vv = np.clip((top - q[:, 1]) / (top - bot), 0, 1)
    return u, vv


def build_uvs(body, verts, faces, lab):
    vreg = region_of(lab)
    # Triangle region: majority vote (ties to the limb).
    tri_reg = []
    for f in faces:
        rs = [vreg[k] for k in f]
        best = max(set(rs), key=lambda r: (rs.count(r), r != "torso"))
        tri_reg.append(best)
    tri_reg = np.array(tri_reg)
    new_v, new_uv, remap = [], [], {}
    new_faces = np.zeros_like(faces)
    rest = {r: rest_coords(body, verts, r) for r in REGIONS}
    uvs = {r: uv_for(body, rest[r], r) for r in REGIONS}
    for t, f in enumerate(faces):
        r = tri_reg[t]
        us = [uvs[r][0][k] for k in f]
        wrap = max(us) - min(us) > 0.5
        for c, k in enumerate(f):
            u = uvs[r][0][k]
            hi = wrap and u < 0.5
            key = (k, r, hi)
            if key not in remap:
                uu = min(1.0, u + 1.0) if hi else u
                x0, y0, w, h = RECTS[r]
                pad = 0.004
                remap[key] = len(new_v)
                new_v.append(k)
                new_uv.append((x0 + pad + (w - 2 * pad) * uu, y0 + pad + (h - 2 * pad) * uvs[r][1][k]))
            new_faces[t, c] = remap[key]
    return np.array(new_v), np.array(new_uv), new_faces, tri_reg


# ---------------------------------------------------------------- output


def write(path, body, verts, normals, uvs, ao, bidx, bw, faces):
    with open(path, "wb") as fh:
        fh.write(b"NGB1")
        fh.write(struct.pack("<III", 1, len(verts), len(faces)))
        for name in BONES:
            fh.write(struct.pack("<3f", *body.joints[name]))
        fh.write(struct.pack("<2f", ARM_OUT, LEG_OUT))
        fh.write(verts.astype("<f4").tobytes())
        fh.write(normals.astype("<f4").tobytes())
        fh.write(uvs.astype("<f4").tobytes())
        fh.write(np.round(ao * 255).astype(np.uint8).tobytes())
        pad = (-len(verts)) % 4
        fh.write(b"\0" * pad)
        fh.write(bidx.astype(np.uint8).tobytes())
        fh.write(np.round(bw * 255).astype(np.uint8).tobytes())
        fh.write(faces.astype("<u2").tobytes())


def make(build, frame, lod, step=0.005):
    body = Body(build, frame)
    v, f = build_mesh(body, step)
    target = 7000 if lod == "hi" else 2600
    v, f = simplify(v, f, target)
    v = project_to_surface(body, v)
    n = gradient(body, v)
    ao = ambient_occlusion(body, v, n)
    _, names, raw = body.sdf(v, labels=True)
    W, lab = weights_for(body, v, names, raw)
    W = smooth_weights(W, f, len(v), 6 if lod == "hi" else 4)
    keep, uvs, faces, tri_reg = build_uvs(body, v, f, lab)
    bidx, bw = top4(W[keep])
    return body, v[keep], n[keep], uvs, ao[keep], bidx, bw, faces, tri_reg


def main():
    out = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else \
        os.path.join(os.path.dirname(__file__), "..", "NeonGetaway", "Scene", "Bodies")
    os.makedirs(out, exist_ok=True)
    only = os.environ.get("ONLY")
    for build in range(4):
        for frame in range(2):
            for lod in ("hi", "lo"):
                name = f"body_b{build}_f{frame}_{lod}"
                if only and only not in name:
                    continue
                body, v, n, uv, ao, bi, bw, faces, _ = make(build, frame, lod)
                assert len(v) < 65536
                write(os.path.join(out, name + ".bin"), body, v, n, uv, ao, bi, bw, faces)
                print(name, len(v), "verts", len(faces), "tris")


if __name__ == "__main__":
    main()
