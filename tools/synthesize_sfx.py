"""
Synthesizes original, copyright-free placeholder sound effects for
IKEA of the Damned using pure DSP (numpy) -- no samples, no external
audio, nothing lifted from anywhere. Every file maps 1:1 to a Config.Sounds
or per-monster Config field.

Run: python3 synthesize_sfx.py <output_dir>
"""

import sys
import wave
import numpy as np

SR = 22050


def to_pcm16(signal):
    signal = np.clip(signal, -1.0, 1.0)
    return (signal * 32767).astype(np.int16)


def save_wav(path, signal):
    data = to_pcm16(signal)
    with wave.open(path, "w") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(data.tobytes())


def t_axis(duration):
    return np.linspace(0, duration, int(SR * duration), endpoint=False)


def sine(freq, duration, phase=0.0):
    t = t_axis(duration)
    return np.sin(2 * np.pi * freq * t + phase)


def sine_sweep(f0, f1, duration, curve="linear"):
    t = t_axis(duration)
    n = len(t)
    if curve == "exp":
        freqs = f0 * (f1 / f0) ** (t / duration)
    else:
        freqs = np.linspace(f0, f1, n)
    phase = 2 * np.pi * np.cumsum(freqs) / SR
    return np.sin(phase)


def white_noise(duration, seed=0):
    rng = np.random.default_rng(seed)
    return rng.uniform(-1, 1, int(SR * duration))


def one_pole_lowpass(signal, alpha):
    out = np.zeros_like(signal)
    acc = 0.0
    for i, x in enumerate(signal):
        acc += alpha * (x - acc)
        out[i] = acc
    return out


def one_pole_highpass(signal, alpha):
    return signal - one_pole_lowpass(signal, alpha)


def env_ad(duration, attack, decay_curve=3.0):
    t = t_axis(duration)
    n = len(t)
    a_n = max(1, int(SR * attack))
    a_n = min(a_n, n)
    env = np.ones(n)
    env[:a_n] = np.linspace(0, 1, a_n)
    rel = np.linspace(0, 1, n - a_n) if n - a_n > 0 else np.array([])
    env[a_n:] = (1 - rel) ** decay_curve
    return env


def env_adsr(duration, attack, decay, sustain_level, release):
    t = t_axis(duration)
    n = len(t)
    a_n = int(SR * attack)
    d_n = int(SR * decay)
    r_n = int(SR * release)
    s_n = max(0, n - a_n - d_n - r_n)
    env = np.concatenate([
        np.linspace(0, 1, max(a_n, 1)),
        np.linspace(1, sustain_level, max(d_n, 1)),
        np.full(s_n, sustain_level),
        np.linspace(sustain_level, 0, max(r_n, 1)),
    ])[:n]
    if len(env) < n:
        env = np.pad(env, (0, n - len(env)))
    return env


def mix(*signals):
    n = max(len(s) for s in signals)
    out = np.zeros(n)
    for s in signals:
        out[: len(s)] += s
    peak = np.max(np.abs(out))
    if peak > 1e-6:
        out = out / peak * 0.95
    return out


def normalize(signal, target=0.9):
    peak = np.max(np.abs(signal))
    if peak < 1e-6:
        return signal
    return signal / peak * target


def loop_crossfade(signal, fade_samples):
    fade_samples = min(fade_samples, len(signal) // 4)
    head = signal[:fade_samples]
    tail = signal[-fade_samples:]
    fade_in = np.linspace(0, 1, fade_samples)
    fade_out = 1 - fade_in
    blended = tail * fade_out + head * fade_in
    return np.concatenate([blended, signal[fade_samples:-fade_samples]])


# ---------------------------------------------------------------- Global SFX

def sfx_store_ambience():
    dur = 6.0
    t = t_axis(dur)
    drone = (
        0.5 * np.sin(2 * np.pi * 55 * t + 0.3 * np.sin(2 * np.pi * 0.07 * t))
        + 0.3 * np.sin(2 * np.pi * 82.4 * t + 0.4 * np.sin(2 * np.pi * 0.05 * t))
        + 0.2 * np.sin(2 * np.pi * 110 * t)
    )
    hum = one_pole_lowpass(white_noise(dur, seed=1), 0.02) * 0.15
    flicker = 1.0 + 0.03 * np.sin(2 * np.pi * 0.6 * t) * (white_noise(dur, seed=2) > 0.97)
    sig = (drone + hum) * flicker
    sig = normalize(sig, 0.5)
    return loop_crossfade(sig, int(SR * 0.5))


def sfx_heartbeat():
    dur = 1.0
    lub = sine(60, 0.18) * env_ad(0.18, 0.005, 4)
    dub_gap = np.zeros(int(SR * 0.12))
    dub = sine(52, 0.14) * env_ad(0.14, 0.005, 4) * 0.8
    tail = np.zeros(int(SR * dur) - len(lub) - len(dub_gap) - len(dub))
    sig = np.concatenate([lub, dub_gap, dub, tail])
    return normalize(sig, 0.9)


def sfx_round_start():
    notes = [440.0, 554.37, 659.25, 880.0]
    parts = []
    for i, f in enumerate(notes):
        d = 0.35
        tone = sine(f, d) * env_ad(d, 0.01, 2.5)
        pad = np.zeros(int(SR * 0.08 * i))
        parts.append(np.concatenate([pad, tone]))
    sig = mix(*parts)
    return normalize(sig, 0.85)


def sfx_intermission_start():
    dur = 1.6
    sweep = sine_sweep(90, 140, dur, curve="exp")
    overtone = sine_sweep(180, 280, dur, curve="exp") * 0.35
    env = env_ad(dur, 0.6, 1.5)
    sig = (sweep + overtone) * env
    return normalize(sig, 0.8)


def sfx_exit_unlocked():
    clunk = one_pole_lowpass(white_noise(0.12, seed=3), 0.15) * env_ad(0.12, 0.002, 6)
    notes = [523.25, 659.25, 783.99, 1046.5]
    parts = [clunk]
    for i, f in enumerate(notes):
        d = 0.3
        tone = sine(f, d) * env_ad(d, 0.005, 3)
        pad = np.zeros(int(SR * (0.1 + 0.09 * i)))
        parts.append(np.concatenate([pad, tone]))
    sig = mix(*parts)
    return normalize(sig, 0.9)


def sfx_escape_success():
    notes = [523.25, 659.25, 783.99]
    parts = []
    for i, f in enumerate(notes):
        d = 0.22
        tone = sine(f, d) * env_ad(d, 0.005, 3)
        pad = np.zeros(int(SR * 0.07 * i))
        parts.append(np.concatenate([pad, tone]))
    sig = mix(*parts)
    return normalize(sig, 0.9)


def sfx_caught():
    dur = 0.35
    boom = sine(70, dur) * env_ad(dur, 0.002, 5)
    crack = one_pole_lowpass(white_noise(dur, seed=4), 0.35) * env_ad(dur, 0.001, 8)
    sig = mix(boom, crack)
    return normalize(sig, 0.95)


def sfx_ui_click():
    dur = 0.06
    tone = sine(1200, dur) * env_ad(dur, 0.001, 6)
    return normalize(tone, 0.6)


def sfx_minigame_success():
    notes = [880.0, 1108.7]
    parts = []
    for i, f in enumerate(notes):
        d = 0.18
        tone = sine(f, d) * env_ad(d, 0.003, 3)
        pad = np.zeros(int(SR * 0.09 * i))
        parts.append(np.concatenate([pad, tone]))
    sig = mix(*parts)
    return normalize(sig, 0.85)


def sfx_minigame_fail():
    notes = [220.0, 174.6]
    parts = []
    for i, f in enumerate(notes):
        d = 0.22
        tone = sine(f, d) * env_ad(d, 0.003, 2.5)
        pad = np.zeros(int(SR * 0.1 * i))
        parts.append(np.concatenate([pad, tone]))
    sig = mix(*parts)
    return normalize(sig, 0.8)


GLOBAL_SFX = {
    "store_ambience": sfx_store_ambience,
    "heartbeat": sfx_heartbeat,
    "round_start": sfx_round_start,
    "intermission_start": sfx_intermission_start,
    "exit_unlocked": sfx_exit_unlocked,
    "escape_success": sfx_escape_success,
    "caught": sfx_caught,
    "ui_click": sfx_ui_click,
    "minigame_success": sfx_minigame_success,
    "minigame_fail": sfx_minigame_fail,
}

# ---------------------------------------------------------------- Monsters

MONSTERS = {
    # id: footstepPitch (reused as the character's base-pitch cue)
    "george": 1.15,
    "peppa": 1.05,
    "thomas": 0.80,
    "barney": 0.60,
    "grinch": 0.95,
    "po": 0.90,
    "spongebob": 1.10,
    "dora": 1.00,
}


def monster_chase(pitch, seed):
    base = 220 * pitch
    dur = 0.7
    sweep = sine_sweep(base * 0.7, base * 2.2, dur, curve="exp")
    noise = one_pole_lowpass(white_noise(dur, seed=seed), 0.25)
    env = env_ad(dur, 0.01, 3)
    sig = (sweep * 0.8 + noise * 0.5) * env
    return normalize(sig, 0.9)


def monster_jumpscare(pitch, seed):
    base = 220 * pitch
    dur = 0.9
    if pitch < 0.85:
        # heavier monster: a roar -- distorted low tone + tremolo
        t = t_axis(dur)
        tone = np.sin(2 * np.pi * base * 0.5 * t)
        tremolo = 1.0 + 0.4 * np.sin(2 * np.pi * 11 * t)
        roar = np.tanh(3.0 * tone * tremolo)
        noise = one_pole_lowpass(white_noise(dur, seed=seed), 0.2) * 0.4
        env = env_adsr(dur, 0.02, 0.15, 0.7, 0.4)
        sig = (roar * 0.8 + noise) * env
    else:
        # lighter monster: a shriek -- resonant sweep + vibrato sine
        sweep = sine_sweep(base * 1.5, base * 4.0, dur, curve="exp")
        t = t_axis(dur)
        vibrato = np.sin(2 * np.pi * base * 3 * t + 6 * np.sin(2 * np.pi * 18 * t))
        noise = one_pole_highpass(white_noise(dur, seed=seed), 0.3) * 0.3
        env = env_adsr(dur, 0.01, 0.1, 0.8, 0.35)
        sig = (sweep * 0.6 + vibrato * 0.5 + noise) * env
    return normalize(sig, 0.95)


def monster_idle(pitch, seed):
    base = 220 * pitch
    dur = 0.55
    t = t_axis(dur)
    if pitch >= 1.0:
        # playful tell: rapid tremolo "giggle"/chatter
        tone = np.sin(2 * np.pi * base * 1.5 * t)
        tremolo = 0.5 + 0.5 * (np.sin(2 * np.pi * 14 * t) > 0)
        sig = tone * tremolo * env_ad(dur, 0.02, 2)
    else:
        # heavier tell: low contented grumble/hum
        tone = np.sin(2 * np.pi * base * 0.6 * t) + 0.3 * np.sin(2 * np.pi * base * 0.9 * t)
        wobble = 1.0 + 0.15 * np.sin(2 * np.pi * 4 * t)
        sig = tone * wobble * env_ad(dur, 0.05, 1.5)
    return normalize(sig, 0.8)


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    seed = 100
    manifest = []

    for name, fn in GLOBAL_SFX.items():
        sig = fn()
        path = f"{out_dir}/{name}.wav"
        save_wav(path, sig)
        manifest.append(path)

    for mid, pitch in MONSTERS.items():
        seed += 1
        save_wav(f"{out_dir}/chase_{mid}.wav", monster_chase(pitch, seed))
        seed += 1
        save_wav(f"{out_dir}/jumpscare_{mid}.wav", monster_jumpscare(pitch, seed))
        seed += 1
        save_wav(f"{out_dir}/idle_{mid}.wav", monster_idle(pitch, seed))
        manifest += [f"chase_{mid}.wav", f"jumpscare_{mid}.wav", f"idle_{mid}.wav"]

    print(f"Generated {len(GLOBAL_SFX) + 3 * len(MONSTERS)} files into {out_dir}")


if __name__ == "__main__":
    main()
