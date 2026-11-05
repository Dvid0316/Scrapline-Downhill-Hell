#!/usr/bin/env python3
"""Generate Scrapline's placeholder combat sound effects.

100% synthesized here (noise + sine partials + envelopes). No samples, no
downloads, no third-party code. Output: 16-bit mono WAVs in audio/sfx/.

    python3 tools/gen_sfx.py            # writes audio/sfx/*.wav

Deterministic (fixed seeds), so re-running produces identical files.
These are placeholders: swap in better recordings later, keeping the filenames.
"""
import math
import os
import random
import struct
import wave

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio", "sfx")


def write(name, samples, peak_db=-1.0):
    peak = max(1e-9, max(abs(s) for s in samples))
    gain = (10 ** (peak_db / 20.0)) / peak
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * gain)) * 32767)) for s in samples))
    print("wrote", os.path.relpath(path), "%.2fs" % (len(samples) / SR))


def n_samples(sec):
    return int(sec * SR)


class Lowpass:
    """One-pole low-pass filter."""
    def __init__(self, cutoff):
        self.a = 1.0 - math.exp(-2.0 * math.pi * cutoff / SR)
        self.y = 0.0

    def __call__(self, x):
        self.y += self.a * (x - self.y)
        return self.y


class Highpass:
    def __init__(self, cutoff):
        self.lp = Lowpass(cutoff)

    def __call__(self, x):
        return x - self.lp(x)


def soft_clip(x, drive=1.0):
    return math.tanh(x * drive)


def fade_tail(samples, ms=8):
    n = n_samples(ms / 1000.0)
    for i in range(1, n + 1):
        samples[-i] *= (i - 1) / n
    return samples


def mg_shot():
    """Heavy MG round: sharp crack, chesty thump, short mechanical tail."""
    rng = random.Random(1)
    out = []
    crack_lp, body_lp, tail_lp = Lowpass(5200), Lowpass(900), Lowpass(450)
    hp = Highpass(2500)
    phase = 0.0
    for i in range(n_samples(0.24)):
        t = i / SR
        w = rng.uniform(-1, 1)
        crack = crack_lp(w) * math.exp(-t / 0.012)
        click = hp(w) * math.exp(-t / 0.002) * 0.8
        freq = 55 + 110 * math.exp(-t / 0.018)
        phase += 2 * math.pi * freq / SR
        thump = math.sin(phase) * math.exp(-t / 0.05) * 1.1
        body = body_lp(w) * math.exp(-t / 0.035) * 0.9
        tail = tail_lp(w) * math.exp(-t / 0.09) * 0.35
        out.append(soft_clip(crack * 1.4 + click + thump + body + tail, 1.6))
    return fade_tail(out)


def impact_metal():
    """Bullet on armour: noisy tick + inharmonic ringing partials."""
    rng = random.Random(2)
    partials = [(1870, 0.07, 0.5), (2930, 0.05, 0.35), (4410, 0.04, 0.25), (6150, 0.025, 0.18), (980, 0.09, 0.3)]
    hp = Highpass(1800)
    out = []
    for i in range(n_samples(0.32)):
        t = i / SR
        tick = hp(rng.uniform(-1, 1)) * math.exp(-t / 0.004)
        ring = sum(a * math.sin(2 * math.pi * f * t) * math.exp(-t / d) for f, d, a in partials)
        out.append(soft_clip(tick * 1.2 + ring, 1.3))
    return fade_tail(out)


def impact_dirt():
    """Round into earth/gravel: dull thud + grit."""
    rng = random.Random(3)
    lp, grit = Lowpass(700), Lowpass(3500)
    out = []
    for i in range(n_samples(0.18)):
        t = i / SR
        w = rng.uniform(-1, 1)
        thud = lp(w) * math.exp(-t / 0.03) * 2.0 + math.sin(2 * math.pi * 95 * t) * math.exp(-t / 0.025)
        g = grit(w) * math.exp(-t / 0.012) * 0.5
        out.append(thud + g)
    return fade_tail(out)


def impact_wood():
    """Round into a crate: knocky resonant thock."""
    rng = random.Random(4)
    lp = Lowpass(2400)
    out = []
    for i in range(n_samples(0.2)):
        t = i / SR
        knock = (math.sin(2 * math.pi * 310 * t) * 0.8 + math.sin(2 * math.pi * 720 * t) * 0.4) * math.exp(-t / 0.03)
        crack = lp(rng.uniform(-1, 1)) * math.exp(-t / 0.008) * 1.2
        out.append(knock + crack)
    return fade_tail(out)


def explosion():
    """Barrel/bunker blast: sub boom + rumbling brown noise + crackle."""
    rng = random.Random(5)
    lp1, lp2 = Lowpass(380), Lowpass(160)
    brown = 0.0
    phase = 0.0
    out = []
    crackles = sorted(rng.uniform(0.02, 0.9) for _ in range(70))
    ci = 0
    crack_env = 0.0
    hp = Highpass(1500)
    for i in range(n_samples(1.8)):
        t = i / SR
        w = rng.uniform(-1, 1)
        brown = 0.985 * brown + w * 0.15
        attack = min(1.0, t / 0.004)
        rumble = lp1(brown) * math.exp(-t / 0.45) * 3.0 * attack
        deep = lp2(w) * math.exp(-t / 0.25) * 2.0 * attack
        freq = 32 + 40 * math.exp(-t / 0.08)
        phase += 2 * math.pi * freq / SR
        boom = math.sin(phase) * math.exp(-t / 0.3) * 1.3 * attack
        while ci < len(crackles) and crackles[ci] <= t:
            crack_env = rng.uniform(0.3, 1.0) * math.exp(-t / 0.5)
            ci += 1
        crack_env *= 0.996
        crackle = hp(w) * crack_env * 0.6
        out.append(soft_clip(rumble + deep + boom + crackle, 1.4))
    return fade_tail(out, 40)


def crate_break():
    """Crate destroyed: a few splintering cracks over ~0.35 s."""
    rng = random.Random(6)
    events = [0.0, 0.035, 0.07, 0.12, 0.2]
    lp = Lowpass(3000)
    out = []
    for i in range(n_samples(0.45)):
        t = i / SR
        w = rng.uniform(-1, 1)
        s = 0.0
        for k, e in enumerate(events):
            if t >= e:
                dt = t - e
                s += math.exp(-dt / (0.015 + 0.01 * k)) * (1.0 - 0.12 * k)
        body = math.sin(2 * math.pi * 180 * t) * math.exp(-t / 0.06) * 0.6
        out.append(soft_clip(lp(w) * s * 1.6 + body, 1.2))
    return fade_tail(out)


if __name__ == "__main__":
    write("mg_shot.wav", mg_shot())
    write("impact_metal.wav", impact_metal(), -3)
    write("impact_dirt.wav", impact_dirt(), -3)
    write("impact_wood.wav", impact_wood(), -3)
    write("explosion.wav", explosion())
    write("crate_break.wav", crate_break(), -2)
