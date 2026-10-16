"""Générateur des sons d'Ares Colony (synthèse, bibliothèque standard uniquement).

- Effets : clic, construction, échec, alerte, recherche, objectif, ravitaillement, évacuation...
- Instruments de la musique (une note chacun, transposée par le jeu) : kalimba, nappe, basse.
- Ambiance : boucle de vent martien sans couture.

Usage : python tools/make_sounds.py            (écrit dans art/audio/)
"""
import math
import os
import random
import struct
import wave

RATE = 22050
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "art", "audio")
TAU = 2.0 * math.pi
rng = random.Random(7)


# ---------------------------------------------------------------- Outils

def silence(seconds):
    return [0.0] * int(seconds * RATE)


def mix(target, source, offset=0.0, gain=1.0):
    start = int(offset * RATE)
    if len(target) < start + len(source):
        target.extend([0.0] * (start + len(source) - len(target)))
    for i, v in enumerate(source):
        target[start + i] += v * gain
    return target


def lowpass(samples, cutoff):
    a = 1.0 - math.exp(-TAU * cutoff / RATE)
    y = 0.0
    out = []
    for x in samples:
        y += a * (x - y)
        out.append(y)
    return out


def normalize(samples, peak=0.9):
    m = max(abs(v) for v in samples) or 1.0
    return [v * peak / m for v in samples]


def fade(samples, fade_in=0.004, fade_out=0.02):
    n = len(samples)
    fi, fo = int(fade_in * RATE), int(fade_out * RATE)
    for i in range(min(fi, n)):
        samples[i] *= i / fi
    for i in range(min(fo, n)):
        samples[n - 1 - i] *= i / fo
    return samples


def write(name, samples, peak=0.9):
    os.makedirs(OUT, exist_ok=True)
    data = normalize(samples, peak)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767)) for v in data))


def freq(note):
    """Note MIDI -> fréquence."""
    return 440.0 * 2.0 ** ((note - 69) / 12.0)


# ---------------------------------------------------------------- Timbres

def bell(f, seconds, decay=3.0, index=2.2, ratio=3.5):
    """Cloche FM : attaque brillante, extinction douce."""
    out = []
    for i in range(int(seconds * RATE)):
        t = i / RATE
        env = math.exp(-t * decay)
        out.append(math.sin(TAU * f * t + index * math.exp(-t * 4.0) * math.sin(TAU * f * ratio * t)) * env)
    return fade(out)


def kalimba(f, seconds=1.4):
    out = []
    for i in range(int(seconds * RATE)):
        t = i / RATE
        tone = math.sin(TAU * f * t) + 0.35 * math.sin(TAU * f * 3.01 * t) * math.exp(-t * 14.0)
        tone += 0.12 * math.sin(TAU * f * 5.4 * t) * math.exp(-t * 30.0)
        out.append(tone * math.exp(-t * 3.6))
    return fade(out, 0.002, 0.05)


def pad(f, seconds=8.0):
    """Nappe : trois dents de scie désaccordées, filtrées, attaque et relâche lentes."""
    out = []
    phases = [0.0, 0.33, 0.66]
    detune = [1.0, 1.004, 0.996]
    for i in range(int(seconds * RATE)):
        t = i / RATE
        v = 0.0
        for k in range(3):
            p = (phases[k] + f * detune[k] * t) % 1.0
            v += 2.0 * p - 1.0
        attack = min(1.0, t / 1.2)
        release = min(1.0, (seconds - t) / 3.0)
        out.append(v / 3.0 * attack * release)
    return lowpass(lowpass(out, 900.0), 1400.0)


def bass(f, seconds=1.8):
    out = []
    for i in range(int(seconds * RATE)):
        t = i / RATE
        v = math.sin(TAU * f * t) + 0.25 * math.sin(TAU * 2 * f * t)
        v = math.tanh(v * 1.4)
        out.append(v * min(1.0, t / 0.01) * math.exp(-t * 2.2))
    return fade(lowpass(out, 600.0), 0.002, 0.08)


def sweep(f0, f1, seconds, decay=8.0, shape="sine"):
    out = []
    phase = 0.0
    for i in range(int(seconds * RATE)):
        t = i / RATE
        f = f0 + (f1 - f0) * (t / seconds)
        phase += f / RATE
        if shape == "triangle":
            v = 4.0 * abs((phase % 1.0) - 0.5) - 1.0
        else:
            v = math.sin(TAU * phase)
        out.append(v * math.exp(-t * decay))
    return fade(out)


def noise(seconds, cutoff, decay=0.0):
    out = [rng.uniform(-1.0, 1.0) * (math.exp(-i / RATE * decay) if decay else 1.0) for i in range(int(seconds * RATE))]
    return lowpass(out, cutoff)


# ---------------------------------------------------------------- Effets

def effects():
    sounds = {}
    sounds["click"] = mix(silence(0.06), sweep(1400, 900, 0.05, decay=60.0), 0.0, 0.7)
    sounds["tab"] = mix(silence(0.08), sweep(760, 980, 0.06, decay=45.0), 0.0, 0.6)
    sounds["fail"] = mix(silence(0.2), sweep(180, 120, 0.18, decay=14.0, shape="triangle"), 0.0, 0.8)

    upgrade = silence(0.8)
    for k, note in enumerate([72, 76, 79, 84]):
        mix(upgrade, bell(freq(note), 0.5, decay=6.0, index=1.5), k * 0.07, 0.7)
    mix(upgrade, noise(0.6, 6000.0, decay=7.0), 0.2, 0.08)
    sounds["upgrade"] = upgrade

    fanfare = silence(1.4)
    for k, note in enumerate([67, 72, 76]):
        mix(fanfare, bell(freq(note), 0.4, decay=7.0), k * 0.1, 0.7)
    for note in [79, 84, 88]:
        mix(fanfare, bell(freq(note), 1.1, decay=2.8), 0.32, 0.45)
    sounds["milestone"] = fanfare



    sounds["whoosh"] = mix(silence(0.3), noise(0.28, 1800.0, decay=10.0), 0.0, 0.7)

    # Construction : choc sourd puis cliquetis de verrouillage.
    build = silence(0.6)
    mix(build, sweep(160, 70, 0.25, decay=12.0, shape="triangle"), 0.0, 0.9)
    mix(build, noise(0.15, 3000.0, decay=25.0), 0.0, 0.3)
    for k in range(3):
        mix(build, sweep(2400, 1800, 0.03, decay=80.0), 0.18 + k * 0.07, 0.35)
    sounds["build"] = build

    # Alerte : deux bips graves répétés.
    alert = silence(0.9)
    for k in range(2):
        mix(alert, bell(freq(64), 0.22, decay=10.0, index=0.6, ratio=2.0), k * 0.3, 0.7)
        mix(alert, bell(freq(61), 0.22, decay=10.0, index=0.6, ratio=2.0), k * 0.3 + 0.13, 0.7)
    sounds["alert"] = alert

    # Atterrissage du ravitaillement : grondement des rétrofusées.
    landing = noise(2.4, 400.0)
    for i in range(len(landing)):
        t = i / RATE
        landing[i] *= min(1.0, t / 0.4) * min(1.0, (2.4 - t) / 0.8)
    sounds["landing"] = mix(silence(2.6), landing, 0.0, 1.0)

    # Évacuation : décollage qui s'éloigne.
    evac = noise(2.0, 900.0)
    for i in range(len(evac)):
        t = i / RATE
        evac[i] *= math.exp(-t * 1.4) * min(1.0, t / 0.1)
    sounds["evacuation"] = mix(silence(2.2), evac, 0.0, 1.0)
    return sounds


# ---------------------------------------------------------------- Ambiance

def wind(seconds=12.0, overlap=1.5):
    """Vent martien : souffle grave et rafales lentes, raccordé en boucle par fondu enchaîné."""
    total = seconds + overlap
    out = []
    brown = 0.0
    for i in range(int(total * RATE)):
        t = i / RATE
        brown = 0.997 * brown + rng.uniform(-1.0, 1.0) * 0.04
        gust = 0.4 + 0.45 * math.sin(math.pi * t / 6.0) ** 2 + 0.25 * math.sin(math.pi * t / 2.0 + 0.7) ** 4
        out.append(brown * gust)
    out = lowpass(out, 500.0)
    n = int(seconds * RATE)
    o = int(overlap * RATE)
    loop = out[:n]
    for i in range(o):
        w = i / o
        loop[i] = loop[i] * w + out[n + i] * (1.0 - w)
    return loop


def main():
    for name, samples in effects().items():
        write(name, samples)
    # Musique : bande son « Cradle of the Red Horizon » (art/audio/music_red_horizon.mp3).
    write("ambience_wind", wind(), 0.8)
    print("Sons écrits dans %s" % OUT)


if __name__ == "__main__":
    main()
