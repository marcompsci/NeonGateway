import AVFoundation
import os

/// One-shot sounds the game can play.
enum SoundCue: Sendable {
    case hit, pickup, spotted, success, failure, busted
    case shot, door, knock
}

/// Every sound in the game is synthesized here: a buzzy engine whose pitch follows speed, a
/// two-tone siren while patrols are chasing, and short blips for events. No audio files.
/// The audio session is `.ambient`, so the silent switch mutes it and music apps keep playing.
@MainActor
final class SynthAudio {
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private let shared = OSAllocatedUnfairLock(initialState: Mix())
    private(set) var isRunning = false

    /// Mirrors the Settings "Sound" toggle.
    var enabled = true {
        didSet { if !enabled { stop() } }
    }

    func start() {
        guard enabled, !isRunning else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            return
        }
        if source == nil {
            let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
            let node = Self.makeSourceNode(format: format, renderer: Renderer(shared: shared, sampleRate: 44_100))
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            source = node
        }
        do {
            try engine.start()
            isRunning = true
        } catch {
            isRunning = false
        }
    }

    /// Built outside the main actor so the render closure carries no main-actor isolation:
    /// it runs on the real-time audio thread.
    nonisolated private static func makeSourceNode(format: AVAudioFormat, renderer: Renderer) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, bufferList in
            renderer.render(frames: Int(frameCount), into: bufferList)
            return noErr
        }
    }

    func stop() {
        shared.withLock { $0 = Mix() }
        guard isRunning else { return }
        engine.pause()
        isRunning = false
    }

    /// Engine hum: `speed` 0...1 of top speed. `running` false silences it (paused, results).
    func setEngine(speed: Double, running: Bool) {
        shared.withLock {
            $0.engineOn = running
            $0.engineLevel = Float(min(max(speed, 0), 1))
        }
    }

    func setSiren(_ on: Bool) {
        shared.withLock { $0.sirenOn = on }
    }

    func play(_ cue: SoundCue) {
        guard isRunning else { return }
        let tones: [Tone]
        switch cue {
        case .hit:
            tones = [Tone(from: 90, to: 60, duration: 0.09, volume: 0.35, wave: .noise)]
        case .pickup:
            tones = [Tone(from: 660, to: 660, duration: 0.07, volume: 0.18, wave: .square),
                     Tone(from: 990, to: 990, duration: 0.10, volume: 0.18, wave: .square, delay: 0.07)]
        case .spotted:
            tones = [Tone(from: 880, to: 620, duration: 0.18, volume: 0.16, wave: .square)]
        case .success:
            tones = [Tone(from: 523, to: 523, duration: 0.1, volume: 0.2, wave: .square),
                     Tone(from: 659, to: 659, duration: 0.1, volume: 0.2, wave: .square, delay: 0.1),
                     Tone(from: 784, to: 784, duration: 0.1, volume: 0.2, wave: .square, delay: 0.2),
                     Tone(from: 1047, to: 1047, duration: 0.25, volume: 0.2, wave: .square, delay: 0.3)]
        case .failure:
            tones = [Tone(from: 440, to: 220, duration: 0.5, volume: 0.2, wave: .square)]
        case .busted:
            tones = [Tone(from: 220, to: 110, duration: 0.6, volume: 0.25, wave: .square),
                     Tone(from: 300, to: 300, duration: 0.15, volume: 0.15, wave: .noise)]
        case .shot:
            tones = [Tone(from: 180, to: 70, duration: 0.07, volume: 0.3, wave: .noise)]
        case .door:
            tones = [Tone(from: 140, to: 110, duration: 0.05, volume: 0.2, wave: .square),
                     Tone(from: 90, to: 90, duration: 0.05, volume: 0.2, wave: .noise, delay: 0.05)]
        case .knock:
            tones = [Tone(from: 330, to: 160, duration: 0.12, volume: 0.18, wave: .square)]
        }
        shared.withLock { $0.pending.append(contentsOf: tones) }
    }
}

// MARK: - Audio-thread side

struct Tone: Sendable {
    enum Wave: Sendable { case sine, square, noise }
    var from: Float
    var to: Float
    var duration: Float
    var volume: Float
    var wave: Wave
    var delay: Float = 0
}

/// What the main thread asks for; the audio thread copies it once per buffer.
struct Mix: Sendable {
    var engineOn = false
    var engineLevel: Float = 0
    var sirenOn = false
    var pending: [Tone] = []
}

/// Oscillator state. Only ever touched on the audio render thread, hence `@unchecked`.
private final class Renderer: @unchecked Sendable {
    private let shared: OSAllocatedUnfairLock<Mix>
    private let sampleRate: Float
    private var enginePhase: Float = 0
    private var engineGain: Float = 0
    private var lowPass: Float = 0
    private var sirenPhase: Float = 0
    private var sirenClock: Float = 0
    private var sirenGain: Float = 0
    private var active: [(tone: Tone, time: Float, phase: Float)] = []
    private var noise: UInt32 = 0x1234_5678

    init(shared: OSAllocatedUnfairLock<Mix>, sampleRate: Float) {
        self.shared = shared
        self.sampleRate = sampleRate
    }

    private func nextNoise() -> Float {
        noise ^= noise << 13
        noise ^= noise >> 17
        noise ^= noise << 5
        return Float(noise) / Float(UInt32.max) * 2 - 1
    }

    func render(frames: Int, into bufferList: UnsafeMutablePointer<AudioBufferList>) {
        let mix = shared.withLock { state -> Mix in
            let copy = state
            state.pending.removeAll()
            return copy
        }
        for tone in mix.pending { active.append((tone, -tone.delay, 0)) }

        let dt = 1 / sampleRate
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        for frame in 0..<frames {
            var sample: Float = 0

            // Engine: a soft-filtered sawtooth from 45 Hz idle up to 150 Hz flat out.
            let engineTarget: Float = mix.engineOn ? 0.05 + 0.07 * mix.engineLevel : 0
            engineGain += (engineTarget - engineGain) * 0.0008
            let freq = 45 + 105 * mix.engineLevel
            enginePhase += freq * dt
            if enginePhase >= 1 { enginePhase -= 1 }
            let saw = enginePhase * 2 - 1
            lowPass += (saw - lowPass) * 0.08
            sample += lowPass * engineGain

            // Siren: alternate two pitches every 0.45 s.
            sirenGain += ((mix.sirenOn ? 0.07 : 0) - sirenGain) * 0.0005
            if sirenGain > 0.0005 {
                sirenClock += dt
                let high = Int(sirenClock / 0.45) % 2 == 0
                sirenPhase += (high ? 880 : 650) * dt
                if sirenPhase >= 1 { sirenPhase -= 1 }
                sample += sin(sirenPhase * 2 * .pi) * sirenGain
            }

            // One-shots.
            var i = 0
            while i < active.count {
                var entry = active[i]
                entry.time += dt
                if entry.time >= 0 {
                    let tone = entry.tone
                    let progress = entry.time / tone.duration
                    if progress >= 1 {
                        active.remove(at: i)
                        continue
                    }
                    let f = tone.from + (tone.to - tone.from) * progress
                    entry.phase += f * dt
                    if entry.phase >= 1 { entry.phase -= 1 }
                    let envelope = min(1, entry.time / 0.005) * (1 - progress)
                    let wave: Float
                    switch tone.wave {
                    case .sine: wave = sin(entry.phase * 2 * .pi)
                    case .square: wave = entry.phase < 0.5 ? 1 : -1
                    case .noise: wave = nextNoise()
                    }
                    sample += wave * tone.volume * envelope
                }
                active[i] = entry
                i += 1
            }

            sample = max(-1, min(1, sample))
            for buffer in buffers {
                buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = sample
            }
        }
    }
}
