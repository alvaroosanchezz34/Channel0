#!/usr/bin/env python3
"""
Generates CHANNEL 0's original sound effects procedurally (numpy synthesis, no samples, no
third-party recordings) into assets/audio/, using the file names listed in
src/shared/Config/AudioConfig.luau.

    python3 scripts/generate_audio.py            # writes .ogg (needs ffmpeg with libvorbis)
    python3 scripts/generate_audio.py --wav      # writes .wav only

Roblox cannot load local files: upload each file through the Creator Hub (or Studio's Asset
Manager) and paste the returned id into AudioConfig as "rbxassetid://<number>". See
docs/ASSETS.md.

Every sound is deterministic (fixed seeds), so regenerating gives identical files. Loops are
built to repeat seamlessly (their tails are crossfaded into their heads).
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import wave

import numpy as np

RATE = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "audio")
CONFIG = os.path.join(ROOT, "src", "shared", "Config", "AudioConfig.luau")


# ---------------------------------------------------------------- building blocks


def t(seconds: float) -> np.ndarray:
    return np.arange(int(seconds * RATE)) / RATE


def rng(seed: int) -> np.random.Generator:
    return np.random.default_rng(seed)


def white(seconds: float, seed: int) -> np.ndarray:
    return rng(seed).uniform(-1, 1, int(seconds * RATE))


def lowpass_fast(x: np.ndarray, cutoff: float, passes: int = 2) -> np.ndarray:
    """FFT brick-ish low-pass with a soft knee; fast enough for long beds."""
    spectrum = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1 / RATE)
    gain = 1 / (1 + (freqs / max(cutoff, 1)) ** (2 * passes))
    return np.fft.irfft(spectrum * gain, len(x))


def highpass_fast(x: np.ndarray, cutoff: float) -> np.ndarray:
    return x - lowpass_fast(x, cutoff)


def bandpass_fast(x: np.ndarray, low: float, high: float) -> np.ndarray:
    return lowpass_fast(highpass_fast(x, low), high)


def env(n: int, attack: float, release: float, curve: float = 2.0) -> np.ndarray:
    """Attack/exponential-release envelope over n samples."""
    e = np.ones(n)
    a = max(1, int(attack * RATE))
    e[:a] = np.linspace(0, 1, a)
    r = max(1, int(release * RATE))
    r = min(r, n)
    e[-r:] *= np.linspace(1, 0, r) ** curve
    return e


def decay(n: int, seconds: float) -> np.ndarray:
    return np.exp(-np.arange(n) / (seconds * RATE))


def normalize(x: np.ndarray, peak: float = 0.89) -> np.ndarray:
    m = np.max(np.abs(x))
    return x if m == 0 else x / m * peak


def seamless(x: np.ndarray, fade: float = 0.5) -> np.ndarray:
    """Crossfades the tail into the head so the clip loops without a click."""
    n = int(fade * RATE)
    head, body, tail = x[:n], x[n:-n] if len(x) > 2 * n else x[n:], x[-n:]
    ramp = np.linspace(0, 1, n)
    joined = head * ramp + tail * (1 - ramp)
    return np.concatenate([joined, body])


def tone(freq: float, seconds: float, phase: float = 0.0) -> np.ndarray:
    return np.sin(2 * np.pi * freq * t(seconds) + phase)


def mains_hum(seconds: float, base: float = 60.0, harmonics=(1, 0.5, 0.35, 0.2, 0.12)) -> np.ndarray:
    x = np.zeros(int(seconds * RATE))
    for i, amp in enumerate(harmonics, start=1):
        x += amp * tone(base * i, seconds, i * 0.7)
    return x


def pad(x: np.ndarray, seconds: float) -> np.ndarray:
    return np.concatenate([x, np.zeros(int(seconds * RATE))])


def mix(*parts: np.ndarray) -> np.ndarray:
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def at(x: np.ndarray, offset: float, total: float) -> np.ndarray:
    out = np.zeros(int(total * RATE))
    start = int(offset * RATE)
    end = min(len(out), start + len(x))
    out[start:end] += x[: end - start]
    return out


def click(seed: int, length: float = 0.012, cutoff: float = 6000) -> np.ndarray:
    n = int(length * RATE)
    return lowpass_fast(white(length, seed), cutoff) * decay(n, length / 4)


def thump(freq: float, seconds: float, seed: int) -> np.ndarray:
    n = int(seconds * RATE)
    sweep = freq * (1 + 1.5 * decay(n, 0.02))
    phase = 2 * np.pi * np.cumsum(sweep) / RATE
    body = np.sin(phase) * decay(n, seconds / 4)
    return body + 0.3 * lowpass_fast(white(seconds, seed), 900) * decay(n, 0.03)


# ---------------------------------------------------------------- the sounds


def amb_station_hum():
    s = 12.0
    hum = mains_hum(s) * 0.5
    air = lowpass_fast(white(s, 1), 220) * 2.5
    wobble = 1 + 0.05 * tone(0.25, s)
    return seamless(normalize((hum + air) * wobble, 0.7))


def amb_ventilation():
    s = 12.0
    air = bandpass_fast(white(s, 2), 120, 1400)
    flutter = 1 + 0.15 * tone(0.5, s) + 0.05 * tone(3.0, s)
    rattle = bandpass_fast(white(s, 3), 2000, 3500) * 0.05 * (tone(0.25, s) > 0.92)
    return seamless(normalize(air * flutter + rattle, 0.7))


def amb_basement_drone():
    s = 14.0
    low = 0.6 * tone(41, s) + 0.4 * tone(41.6, s) + 0.25 * tone(82.3, s)
    rumble = lowpass_fast(white(s, 4), 90) * 3
    drip_env = np.zeros(int(s * RATE))
    for when in (2.3, 7.9, 11.4):
        d = tone(1900, 0.08) * decay(int(0.08 * RATE), 0.015) * 0.2
        drip_env += at(d, when, s)
    return seamless(normalize(low * (1 + 0.2 * tone(0.07, s)) + rumble + drip_env, 0.7))


def amb_exterior_wind():
    s = 14.0
    w = white(s, 5)
    gust = 0.55 + 0.45 * np.sin(2 * np.pi * 0.09 * t(s)) * np.sin(2 * np.pi * 0.037 * t(s) + 1)
    wind = bandpass_fast(w, 150, 900) * gust
    whistle = bandpass_fast(white(s, 6), 700, 760) * 3 * np.clip(gust - 0.6, 0, 1)
    return seamless(normalize(wind + whistle, 0.75))


def amb_studio_tone():
    s = 12.0
    room = lowpass_fast(white(s, 7), 400) * 1.5 + 0.1 * mains_hum(s, 60, (0.4, 0.2, 0.1))
    return seamless(normalize(room, 0.5))


def amb_tape_hiss():
    s = 10.0
    hiss = highpass_fast(white(s, 8), 3000)
    wow = 1 + 0.08 * tone(0.6, s)
    return seamless(normalize(hiss * wow, 0.5))


def pos_fluorescent_buzz():
    s = 8.0
    x = t(s)
    saw = 2 * ((120 * x) % 1) - 1
    buzz = lowpass_fast(saw, 3000) * 0.5 + 0.3 * tone(120, s)
    ticks = (rng(9).uniform(0, 1, len(x)) > 0.99995).astype(float)
    ticks = np.convolve(ticks, click(10, 0.006), mode="same")
    return seamless(normalize(buzz + ticks * 0.5, 0.7))


def pos_crt_whine():
    s = 8.0
    whine = tone(15734, s) * 0.6 + tone(7867, s) * 0.15
    return seamless(normalize(whine * (1 + 0.03 * tone(0.3, s)), 0.5))


def pos_rack_fans():
    s = 10.0
    air = bandpass_fast(white(s, 11), 200, 2500)
    blade = 0.3 * tone(237, s) + 0.15 * tone(474, s)
    return seamless(normalize(air + blade * (1 + 0.1 * tone(0.2, s)), 0.7))


def pos_generator():
    s = 10.0
    x = t(s)
    engine = np.sign(np.sin(2 * np.pi * 30 * x)) * 0.4 + 0.5 * tone(60, s) + 0.3 * tone(90, s)
    engine = lowpass_fast(engine, 500)
    chug = 1 + 0.25 * np.sin(2 * np.pi * 7.5 * x)
    return seamless(normalize(engine * chug + lowpass_fast(white(s, 12), 300), 0.8))


def pos_phone_ring():
    # North American ring cadence: 2 s ring, 4 s silence; bell = 20 Hz modulated two-tone.
    ring = 2.0
    x = t(ring)
    bell = (tone(440, ring) + tone(480, ring)) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 20 * x)))
    bell = bandpass_fast(bell, 300, 3500) * env(len(x), 0.01, 0.05, 1)
    return normalize(pad(bell, 2.5), 0.85)


def pos_footstep():
    n_s = 0.35
    heel = thump(85, n_s, 13) * 0.8
    scuff = bandpass_fast(white(n_s, 14), 800, 4000) * decay(int(n_s * RATE), 0.04) * 0.3
    return normalize(mix(heel, at(scuff, 0.03, n_s)), 0.85)


def pos_door_open():
    s = 1.4
    latch = at(click(15, 0.02, 4000) * 2, 0.0, s)
    creak_t = t(1.1)
    f = 340 + 120 * np.sin(2 * np.pi * 0.8 * creak_t) + 40 * rng(16).standard_normal(len(creak_t)).cumsum() / 400
    phase = 2 * np.pi * np.cumsum(f) / RATE
    creak = np.sign(np.sin(phase)) * 0.25
    creak = bandpass_fast(creak, 300, 2500) * env(len(creak_t), 0.15, 0.4)
    return normalize(mix(latch, at(creak, 0.12, s)), 0.8)


def pos_door_close():
    s = 0.9
    slam = thump(70, 0.6, 17)
    latch = click(18, 0.02, 5000) * 1.5
    return normalize(mix(at(slam, 0.0, s), at(latch, 0.06, s)), 0.9)


def pos_breaker_flip():
    s = 0.4
    return normalize(mix(at(click(19, 0.015, 7000), 0, s), at(thump(180, 0.15, 20) * 0.4, 0.004, s)), 0.85)


def pos_breaker_spark():
    s = 0.9
    crackle = white(s, 21) * (rng(22).uniform(0, 1, int(s * RATE)) > 0.97)
    crackle = bandpass_fast(crackle, 1500, 9000) * decay(int(s * RATE), 0.25)
    pop = thump(110, 0.3, 23)
    return normalize(mix(crackle * 3, pop), 0.9)


def pos_vtr_insert():
    s = 1.6
    slide = bandpass_fast(white(0.25, 24), 500, 3000) * env(int(0.25 * RATE), 0.02, 0.1)
    clunk = thump(120, 0.3, 25)
    motor_t = t(0.9)
    motor = lowpass_fast(np.sign(np.sin(2 * np.pi * (180 + 80 * motor_t) * motor_t)), 900) * env(len(motor_t), 0.05, 0.2) * 0.3
    return normalize(mix(at(slide, 0, s), at(clunk, 0.25, s), at(motor, 0.5, s)), 0.85)


def pos_vtr_eject():
    s = 1.3
    motor_t = t(0.6)
    motor = lowpass_fast(np.sign(np.sin(2 * np.pi * (260 - 90 * motor_t) * motor_t)), 900) * env(len(motor_t), 0.03, 0.15) * 0.3
    clack = mix(thump(150, 0.25, 26), click(27, 0.02) * 0.8)
    return normalize(mix(at(motor, 0, s), at(clack, 0.62, s)), 0.85)


def pos_light_fail():
    s = 1.5
    buzz = pos_fluorescent_buzz()[: int(1.0 * RATE)]
    flick = (rng(28).uniform(0, 1, len(buzz)) > 0.5).astype(float)
    flick = lowpass_fast(np.repeat(flick[:: int(0.05 * RATE)], int(0.05 * RATE))[: len(buzz)], 60)
    pop = thump(400, 0.2, 29) * 0.6
    return normalize(mix(buzz * flick * env(len(buzz), 0.0, 0.3), at(pop, 1.0, s)), 0.85)


def sig_static():
    s = 6.0
    hiss = white(s, 30)
    crackle = (rng(31).uniform(0, 1, len(hiss)) > 0.998) * rng(32).uniform(-1, 1, len(hiss))
    return seamless(normalize(lowpass_fast(hiss, 9000) * 0.8 + crackle, 0.75), 0.3)


def sig_tone_1k():
    return seamless(normalize(tone(1000, 4.0), 0.5), 0.05)


def sig_eas_attention():
    # The broadcast attention signal: 853 Hz + 960 Hz together.
    s = 4.0
    x = (tone(853, s) + tone(960, s)) * env(int(s * RATE), 0.01, 0.05, 1)
    return normalize(x, 0.7)


def sig_dropout():
    s = 0.8
    n = int(s * RATE)
    burst = white(s, 33) * decay(n, 0.12)
    f = 2200 * decay(n, 0.15) + 80
    sweep = np.sin(2 * np.pi * np.cumsum(f) / RATE) * decay(n, 0.2) * 0.4
    return normalize(lowpass_fast(burst, 6000) + sweep, 0.85)


def sig_tune_sweep():
    s = 6.0
    x = t(s)
    carrier = np.sin(2 * np.pi * np.cumsum(600 + 500 * np.sin(2 * np.pi * 0.33 * x)) / RATE) * 0.25
    hiss = bandpass_fast(white(s, 34), 400, 5000)
    het = tone(1800, s) * 0.08 * (1 + np.sin(2 * np.pi * 0.17 * x))
    return seamless(normalize(hiss + carrier + het, 0.65), 0.3)


def sig_carrier_lock():
    s = 1.2
    n = int(s * RATE)
    f = 1200 - 700 * (1 - decay(n, 0.08))
    chirp = np.sin(2 * np.pi * np.cumsum(f) / RATE) * env(n, 0.005, 0.6)
    clean = tone(500, s) * env(n, 0.15, 0.6) * 0.5
    return normalize(chirp * 0.5 + clean, 0.75)


def sig_interference():
    s = 6.0
    x = t(s)
    buzz = np.sign(np.sin(2 * np.pi * 59.94 * x)) * 0.3
    sync = np.sign(np.sin(2 * np.pi * 15734 / 262 * x))  # field-rate grind
    grind = bandpass_fast(white(s, 35) * (0.5 + 0.5 * sync), 300, 4000)
    return seamless(normalize(lowpass_fast(buzz, 1500) + grind, 0.7), 0.3)


def anchor_keylight_hum():
    # THE ANCHOR's studio key light: a heavy transformer hum with a slow, almost vocal formant.
    s = 10.0
    hum = mains_hum(s, 60, (1, 0.8, 0.5, 0.45, 0.3, 0.2))
    formant = bandpass_fast(hum, 300, 700) * (0.5 + 0.5 * tone(0.21, s))
    return seamless(normalize(hum * 0.6 + formant * 1.2, 0.75))


def anchor_presence():
    s = 12.0
    x = t(s)
    sub = 0.7 * tone(32, s) + 0.5 * tone(32.7, s)
    breath = bandpass_fast(white(s, 36), 200, 900) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.16 * x)) ** 3
    detune = tone(220, s) * tone(0.11, s) * 0.08
    return seamless(normalize(sub + breath * 1.5 + detune, 0.75))


def anchor_step():
    s = 0.7
    step = thump(55, 0.6, 37)
    smear = lowpass_fast(np.concatenate([np.zeros(int(0.08 * RATE)), step[: -int(0.08 * RATE)]]), 400) * 0.5
    return normalize(mix(step, smear), 0.95)


def anchor_skip():
    # A tracking glitch: a short reversed chunk of hum chopped at field rate.
    s = 0.45
    hum = anchor_keylight_hum()[: int(s * RATE)][::-1]
    gate = (np.floor(t(s) * 59.94) % 2 == 0).astype(float)
    return normalize(hum * gate * env(len(hum), 0.0, 0.1), 0.8)


def anchor_hunt_sting():
    s = 3.0
    n = int(s * RATE)
    cluster = sum(tone(f, s) for f in (98, 103.8, 146.8, 155.6)) * env(n, 0.005, 2.4)
    noise = bandpass_fast(white(s, 38), 200, 3000) * decay(n, 0.3)
    return normalize(lowpass_fast(cluster, 1200) + noise, 0.9)


def ui_click():
    return normalize(pad(click(39, 0.01, 5000), 0.05), 0.6)


def ui_switch():
    s = 0.25
    return normalize(mix(at(click(40, 0.012, 6000), 0, s), at(click(41, 0.01, 3000) * 0.6, 0.035, s)), 0.75)


def ui_confirm():
    s = 0.35
    beep = tone(880, 0.12) * env(int(0.12 * RATE), 0.005, 0.05)
    beep2 = tone(1320, 0.12) * env(int(0.12 * RATE), 0.005, 0.08)
    return normalize(mix(at(beep, 0, s), at(beep2, 0.1, s)), 0.6)


def ui_tape_pickup():
    s = 0.5
    rattle = bandpass_fast(white(0.2, 42), 1500, 6000) * decay(int(0.2 * RATE), 0.05)
    tap = thump(260, 0.2, 43) * 0.6
    return normalize(mix(at(rattle, 0, s), at(tap, 0.05, s)), 0.75)


def ui_objective():
    s = 1.0
    n = int(s * RATE)
    blip = (tone(660, s) * 0.6 + tone(990, s) * 0.3) * env(n, 0.01, 0.8)
    return normalize(lowpass_fast(blip, 3000), 0.55)


def sting_low():
    s = 4.0
    n = int(s * RATE)
    boom = thump(38, s, 44)
    swell = lowpass_fast(white(s, 45), 250) * env(n, 0.8, 2.5) * 2
    return normalize(boom + swell, 0.9)


def sting_reveal():
    s = 3.0
    n = int(s * RATE)
    screech = bandpass_fast(white(s, 46), 2500, 6000) * env(n, 0.002, 2.0)
    stab = sum(tone(f, s) for f in (466.2, 493.9, 523.3)) * env(n, 0.002, 1.5) * 0.4
    return normalize(screech + stab, 0.85)


# ---------------------------------------------------------------- driver

GENERATORS = {name: fn for name, fn in globals().items() if callable(fn) and re.match(r"^(amb|pos|sig|anchor|ui|sting)_", name)}


def files_from_config() -> list[str]:
    with open(CONFIG, encoding="utf-8") as f:
        return re.findall(r'def\("([a-z0-9_]+)\.ogg"', f.read())


def write_wav(path: str, samples: np.ndarray) -> None:
    data = (np.clip(samples, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data.tobytes())


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--wav", action="store_true", help="write .wav files instead of .ogg")
    parser.add_argument("only", nargs="*", help="generate only these file stems")
    args = parser.parse_args()

    stems = files_from_config()
    missing = [s for s in stems if s not in GENERATORS]
    if missing:
        print("No generator for: " + ", ".join(missing), file=sys.stderr)
        return 1
    ffmpeg = shutil.which("ffmpeg")
    if not args.wav and not ffmpeg:
        print("ffmpeg not found; use --wav or install ffmpeg (with libvorbis).", file=sys.stderr)
        return 1

    os.makedirs(OUT, exist_ok=True)
    for stem in stems:
        if args.only and stem not in args.only:
            continue
        samples = GENERATORS[stem]()
        wav_path = os.path.join(OUT, stem + ".wav")
        write_wav(wav_path, samples)
        if not args.wav:
            ogg_path = os.path.join(OUT, stem + ".ogg")
            subprocess.run(
                [ffmpeg, "-y", "-loglevel", "error", "-i", wav_path, "-c:a", "libvorbis", "-q:a", "5", ogg_path],
                check=True,
            )
            os.remove(wav_path)
        print(f"{stem}: {len(samples) / RATE:.2f}s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
