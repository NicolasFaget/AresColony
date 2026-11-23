"""Générateur des sons d'Ares Colony (synthèse, bibliothèque standard uniquement).

- Effets : clic, construction, échec, alerte, recherche, objectif, ravitaillement, évacuation...
- Événements et dangers : séisme, éclipse, geyser, pluie, givre, dune, aurore, tempête, éruption,
  météorite, panne, décision.
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


# ---------------------------------------------------------------- Événements et dangers

def highpass(samples, cutoff):
    low = lowpass(samples, cutoff)
    return [x - y for x, y in zip(samples, low)]


def shape(samples, envelope):
    """Applique une enveloppe : envelope(t, durée) -> gain."""
    seconds = len(samples) / RATE
    return [v * envelope(i / RATE, seconds) for i, v in enumerate(samples)]


def swell(t, seconds):
    return math.sin(math.pi * t / seconds) ** 2


def glide(f_of_t, seconds, vibrato=0.0, rate=5.0):
    """Sinus dont la fréquence suit f_of_t(t)."""
    out = []
    phase = 0.0
    for i in range(int(seconds * RATE)):
        t = i / RATE
        phase += f_of_t(t) * (1.0 + vibrato * math.sin(TAU * rate * t)) / RATE
        out.append(math.sin(TAU * phase))
    return out


def events():
    """Un son par événement naturel et par danger (les petits haut-parleurs des téléphones
    ne rendent presque rien sous 250 Hz : chaque son garde de la matière dans le médium)."""
    sounds = {}

    # Séisme : grondement qui tremble, monte puis retombe, et quelques objets qui s'entrechoquent.
    rumble = highpass(noise(2.0, 1000.0), 180.0)
    rumble = shape(rumble, lambda t, s: min(1.0, t / 0.6) * min(1.0, (s - t) / 0.9) * (0.65 + 0.35 * math.sin(TAU * 13.0 * t)))
    quake = mix(silence(2.1), rumble, 0.0, 1.0)
    mix(quake, shape(glide(lambda t: 62.0 + 10.0 * math.sin(TAU * 1.5 * t), 2.0), swell), 0.0, 0.12)
    for k in range(9):
        mix(quake, sweep(rng.uniform(900, 1500), 700, 0.03, decay=90.0), 0.35 + k * 0.14 + rng.uniform(0.0, 0.05), 0.12)
    sounds["quake"] = fade(quake, 0.01, 0.2)

    # Éclipse : un accord doux qui s'assombrit (la hauteur fléchit), puis revient, et une clochette.
    dip = lambda t: 1.0 - 0.2 * math.sin(math.pi * min(1.0, t / 1.7)) ** 2
    eclipse = silence(2.3)
    for f, gain in [(freq(67), 0.5), (freq(74), 0.35), (freq(79), 0.25)]:
        mix(eclipse, shape(glide(lambda t, f=f: f * dip(t), 2.0), swell), 0.0, gain)
    mix(eclipse, bell(freq(91), 0.7, decay=4.0, index=1.0), 1.55, 0.25)
    sounds["eclipse"] = fade(eclipse, 0.02, 0.1)

    # Geyser : un choc sourd, puis un jet de vapeur sous pression qui retombe.
    jet = highpass(noise(1.5, 5000.0), 700.0)
    jet = shape(jet, lambda t, s: min(1.0, t / 0.05) * math.exp(-t * 2.3) * (0.8 + 0.2 * math.sin(TAU * 21.0 * t)))
    geyser = mix(silence(1.6), jet, 0.0, 1.0)
    mix(geyser, sweep(220, 90, 0.25, decay=10.0, shape="triangle"), 0.0, 0.6)
    sounds["geyser"] = fade(geyser, 0.004, 0.2)

    # Averse de méthane : de grosses gouttes lentes et graves sur un fond de pluie.
    bed = shape(noise(2.0, 1300.0), swell)
    rain = mix(silence(2.1), bed, 0.0, 0.35)
    for k in range(34):
        f = rng.uniform(420, 1100)
        mix(rain, sweep(f, f * 0.55, 0.05, decay=45.0), rng.uniform(0.05, 1.8), rng.uniform(0.25, 0.6))
    sounds["rain"] = fade(rain, 0.01, 0.15)

    # Givre, sel : de petits craquements de glace de plus en plus serrés, et un tintement.
    frost = silence(1.1)
    at = 0.0
    for k in range(13):
        f = rng.uniform(3800, 6500)
        mix(frost, sweep(f, f * 0.5, 0.014, decay=220.0), at, rng.uniform(0.4, 0.8))
        at += 0.11 * (0.86 ** k) + rng.uniform(0.0, 0.03)
    mix(frost, bell(freq(96), 0.5, decay=7.0, index=0.8), 0.45, 0.3)
    mix(frost, bell(freq(103), 0.4, decay=9.0, index=0.8), 0.55, 0.18)
    sounds["frost"] = frost

    # Dune : du sable qui glisse, un souffle grave qui enfle et retombe.
    sand = highpass(noise(1.5, 1600.0), 280.0)
    sand = shape(sand, lambda t, s: swell(t, s) * (0.75 + 0.25 * math.sin(TAU * 3.0 * t)))
    dune = mix(silence(1.6), sand, 0.0, 1.0)
    mix(dune, shape(glide(lambda t: 150.0 - 30.0 * t, 1.5), swell), 0.0, 0.25)
    sounds["dune"] = fade(dune, 0.02, 0.15)

    # Aurore : un scintillement aérien, des clochettes aiguës sur une note tenue qui tremble.
    aurora = silence(2.4)
    hold = shape(glide(lambda t: freq(79), 2.2, vibrato=0.004, rate=5.5), lambda t, s: swell(t, s) * (0.7 + 0.3 * math.sin(TAU * 6.0 * t)))
    mix(aurora, hold, 0.0, 0.3)
    for k, note in enumerate([86, 91, 88, 95, 93, 98, 91]):
        mix(aurora, bell(freq(note), 0.9, decay=3.5, index=1.2), 0.1 + k * 0.2, 0.3)
    sounds["aurora"] = fade(aurora, 0.02, 0.2)

    # Tempête : une rafale qui enfle, avec un sifflement, puis retombe vite.
    rise = lambda t, s: (min(1.0, t / 1.5) ** 2) * min(1.0, (s - t) / 0.45)
    gust = shape(highpass(noise(2.0, 1100.0), 200.0), rise)
    storm = mix(silence(2.1), gust, 0.0, 1.0)
    whistle = glide(lambda t: 520.0 + 260.0 * (t / 2.0) ** 2, 2.0, vibrato=0.03, rate=3.0)
    mix(storm, shape(whistle, rise), 0.0, 0.12)
    sounds["storm"] = fade(storm, 0.02, 0.1)

    # Éruption solaire : deux coups de sirène, puis la radio qui grésille.
    flare = silence(1.6)
    for k in range(2):
        tone = glide(lambda t: 620.0 + 380.0 * math.sin(math.pi * t / 0.36), 0.36)
        mix(flare, fade(tone, 0.01, 0.04), k * 0.4, 0.55)
    crackle = highpass(noise(0.75, 6000.0), 1500.0)
    gate = 1.0
    for i in range(len(crackle)):
        if i % 220 == 0:
            gate = 1.0 if rng.random() < 0.45 else 0.08
        crackle[i] *= gate * min(1.0, (len(crackle) - i) / (0.3 * RATE))
    mix(flare, crackle, 0.82, 0.5)
    sounds["flare"] = fade(flare, 0.004, 0.05)

    # Météorite : un sifflement qui tombe, puis le choc et les gravats.
    fall = glide(lambda t: 2300.0 * (0.25 ** (t / 0.45)), 0.45)
    meteor = mix(silence(1.1), shape(fall, lambda t, s: (t / s) ** 1.5), 0.0, 0.5)
    mix(meteor, noise(0.6, 900.0, decay=8.0), 0.45, 1.0)
    mix(meteor, sweep(190, 60, 0.4, decay=9.0, shape="triangle"), 0.45, 0.8)
    for k in range(5):
        mix(meteor, sweep(rng.uniform(700, 1300), 500, 0.03, decay=90.0), 0.58 + k * 0.07 + rng.uniform(0.0, 0.03), 0.18)
    sounds["meteor"] = meteor

    # Panne : une machine qui ralentit et s'arrête, puis trois étincelles.
    motor = sweep(340, 70, 0.6, decay=2.5, shape="triangle")
    motor = shape(motor, lambda t, s: 0.7 + 0.3 * math.sin(TAU * (28.0 - 30.0 * t) * t))
    breakdown = mix(silence(0.85), lowpass(motor, 1800.0), 0.0, 0.8)
    for at in [0.5, 0.59, 0.64]:
        mix(breakdown, highpass(noise(0.04, 7000.0, decay=60.0), 2000.0), at, 0.6)
    sounds["breakdown"] = fade(breakdown, 0.004, 0.05)

    # Décision à prendre : deux notes qui montent, comme une question.
    dilemma = silence(0.75)
    mix(dilemma, kalimba(freq(69), 0.5), 0.0, 0.7)
    mix(dilemma, kalimba(freq(74), 0.6), 0.16, 0.7)
    sounds["dilemma"] = dilemma
    return sounds


# Volume de crête des sons d'événements (0,9 par défaut) : les plus doux restent discrets.
PEAKS = {"flare": 0.5, "eclipse": 0.6, "aurora": 0.6, "frost": 0.6, "dune": 0.7, "rain": 0.7, "dilemma": 0.7, "quake": 0.85}


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
    # Après le vent, avec sa propre graine : les sons déjà écrits ne changent pas.
    rng.seed(11)
    for name, samples in events().items():
        write(name, samples, PEAKS.get(name, 0.9))
    print("Sons écrits dans %s" % OUT)


if __name__ == "__main__":
    main()
