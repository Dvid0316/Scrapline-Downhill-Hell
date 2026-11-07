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
    """Bullet on armour: short dull clank (low-mid partials, fast decay).

    Earlier version used ringing 2-6 kHz partials, which at 11 rps sounded
    like a bell ("ding ding ding"). This one is mostly a thunk + gritty
    noise burst so it sits under the gun instead of on top of it.
    """
    rng = random.Random(2)
    partials = [(410, 0.022, 0.55), (655, 0.016, 0.4), (1040, 0.010, 0.25), (1530, 0.006, 0.12)]
    noise_lp = Lowpass(2600)
    hp = Highpass(300)
    out = []
    phase = 0.0
    for i in range(n_samples(0.16)):
        t = i / SR
        w = rng.uniform(-1, 1)
        grit = hp(noise_lp(w)) * math.exp(-t / 0.009) * 1.3
        freq = 120 + 90 * math.exp(-t / 0.01)
        phase += 2 * math.pi * freq / SR
        thunk = math.sin(phase) * math.exp(-t / 0.028) * 0.9
        clank = sum(a * math.sin(2 * math.pi * f * t + f) * math.exp(-t / d) for f, d, a in partials)
        out.append(soft_clip(grit + thunk + clank, 1.4))
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


def cannon_shot():
    """Player cannon: deep concussive boom with a sharp crack on top and a
    short rumbling tail. Heavier and longer than the MG, shorter than an
    explosion, so it reads as 'big gun' without masking the impacts."""
    rng = random.Random(8)
    crack_lp, body_lp, tail_lp = Lowpass(4200), Lowpass(700), Lowpass(220)
    hp = Highpass(1800)
    phase = 0.0
    brown = 0.0
    out = []
    for i in range(n_samples(0.75)):
        t = i / SR
        w = rng.uniform(-1, 1)
        brown = 0.98 * brown + w * 0.2
        attack = min(1.0, t / 0.002)
        crack = hp(crack_lp(w)) * math.exp(-t / 0.01) * 1.8
        body = body_lp(w) * math.exp(-t / 0.05) * 2.2 * attack
        freq = 48 + 70 * math.exp(-t / 0.04)
        phase += 2 * math.pi * freq / SR
        thump = math.sin(phase) * math.exp(-t / 0.16) * 1.6 * attack
        tail = tail_lp(brown) * math.exp(-t / 0.22) * 2.5
        out.append(soft_clip(crack + body + thump + tail, 1.6))
    return fade_tail(out, 30)


def enemy_shot():
    """Enemy rifle-calibre round: thinner, snappier 'pap' than the player's MG,
    so you can hear incoming fire without it fighting your own gun."""
    rng = random.Random(7)
    crack_lp, body_lp = Lowpass(6500), Lowpass(1400)
    hp = Highpass(1800)
    out = []
    for i in range(n_samples(0.14)):
        t = i / SR
        w = rng.uniform(-1, 1)
        crack = hp(crack_lp(w)) * math.exp(-t / 0.006) * 1.6
        body = body_lp(w) * math.exp(-t / 0.018) * 1.1
        ring = math.sin(2 * math.pi * 1250 * t) * math.exp(-t / 0.01) * 0.25
        out.append(soft_clip(crack + body + ring, 1.5))
    return fade_tail(out)


def wave_horn():
    """Wave incoming: two blasts of a low, slightly dissonant train-style horn."""
    out = []
    dur = 1.5
    blasts = [(0.0, 0.55), (0.75, 1.45)]
    lp = Lowpass(1800)
    for i in range(n_samples(dur)):
        t = i / SR
        env = 0.0
        for a, b in blasts:
            if a <= t <= b:
                env = min(1.0, (t - a) / 0.04) * min(1.0, (b - t) / 0.08)
        s = 0.0
        for f, amp in ((147.0, 1.0), (185.0, 0.8), (220.0, 0.6)):
            # Sawtooth-ish: a few harmonics each.
            for h in (1, 2, 3, 4):
                s += amp / h * math.sin(2 * math.pi * f * h * t + h)
        out.append(soft_clip(lp(s * env * 0.35), 1.3))
    return fade_tail(out, 30)


def wave_clear():
    """Wave cleared: a quick rising three-note chime."""
    out = []
    notes = [(0.0, 523.25), (0.11, 659.25), (0.22, 783.99)]
    for i in range(n_samples(0.9)):
        t = i / SR
        s = 0.0
        for start, f in notes:
            if t >= start:
                dt = t - start
                e = min(1.0, dt / 0.005) * math.exp(-dt / 0.28)
                s += (math.sin(2 * math.pi * f * dt) + 0.3 * math.sin(4 * math.pi * f * dt)) * e
        out.append(s * 0.5)
    return fade_tail(out, 20)


def kamikaze_beep():
    """Kamikaze arming: short piercing double beep."""
    out = []
    for i in range(n_samples(0.22)):
        t = i / SR
        on = (t < 0.07) or (0.11 <= t < 0.18)
        e = 1.0 if on else 0.0
        s = (math.sin(2 * math.pi * 1760 * t) + 0.5 * math.sin(2 * math.pi * 2640 * t)) * e
        out.append(s * 0.6)
    return fade_tail(out)


def tesla_zap():
    """Tesla coil arc: buzzy crackle with a falling electric whine."""
    rnd = random.Random(77)
    hp = Highpass(900)
    out = []
    n = n_samples(0.32)
    for i in range(n):
        t = i / SR
        e = min(1.0, t / 0.003) * math.exp(-t / 0.09)
        f = 140 + 90 * math.exp(-t / 0.05)
        buzz = 1.0 if math.sin(2 * math.pi * f * t) > 0 else -1.0  # square-ish 50-60 Hz family
        crack = hp(rnd.uniform(-1, 1)) * (1.0 if rnd.random() < 0.35 else 0.2)
        whine = math.sin(2 * math.pi * (2400 - 1600 * t / 0.32) * t) * 0.25
        out.append(soft_clip((buzz * 0.45 + crack * 0.9 + whine) * e, 1.4))
    return fade_tail(out, 15)


def rocket_launch():
    """Rocket pod: punchy pop, then a hissing whoosh that tails off."""
    rnd = random.Random(31)
    lp = Lowpass(2600)
    out = []
    n = n_samples(0.7)
    for i in range(n):
        t = i / SR
        pop = math.sin(2 * math.pi * 95 * t) * math.exp(-t / 0.03)
        hiss = lp(rnd.uniform(-1, 1)) * min(1.0, t / 0.02) * math.exp(-t / 0.28)
        out.append(soft_clip(pop * 0.9 + hiss * 1.3, 1.2))
    return fade_tail(out, 20)


def upgrade_pick():
    """Upgrade chosen: bright rising arpeggio with a shimmer on top."""
    out = []
    notes = [(0.0, 523.25), (0.07, 659.25), (0.14, 783.99), (0.21, 1046.5)]
    for i in range(n_samples(1.0)):
        t = i / SR
        s = 0.0
        for start, f in notes:
            if t >= start:
                dt = t - start
                e = min(1.0, dt / 0.004) * math.exp(-dt / 0.35)
                s += (math.sin(2 * math.pi * f * dt) + 0.35 * math.sin(2 * math.pi * 2 * f * dt)
                      + 0.15 * math.sin(2 * math.pi * 3.01 * f * dt)) * e
        out.append(s * 0.4)
    return fade_tail(out, 25)


if __name__ == "__main__":
    write("mg_shot.wav", mg_shot())
    write("impact_metal.wav", impact_metal(), -3)
    write("impact_dirt.wav", impact_dirt(), -3)
    write("impact_wood.wav", impact_wood(), -3)
    write("explosion.wav", explosion())
    write("crate_break.wav", crate_break(), -2)
    write("enemy_shot.wav", enemy_shot(), -3)
    write("cannon_shot.wav", cannon_shot(), -1)
    write("wave_horn.wav", wave_horn(), -2)
    write("wave_clear.wav", wave_clear(), -4)
    write("kamikaze_beep.wav", kamikaze_beep(), -6)
    write("tesla_zap.wav", tesla_zap(), -4)
    write("rocket_launch.wav", rocket_launch(), -3)
    write("upgrade_pick.wav", upgrade_pick(), -4)
