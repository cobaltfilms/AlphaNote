#!/usr/bin/env python3
"""Synthétise les sonneries du minuteur (aucune source tierce, aucun droit).
Des sonneries, pas des mélodies : cloches, bips, tintements.

Écrit des WAV 44,1 kHz mono dans design/sounds/, puis les encode en AAC
(.m4a, afconvert) pour macOS (Resources/Sounds) et Android (res/raw/alarm_*).
Chaque fichier dure ~2,5 s, silence compris : l'app le joue en boucle.

    python3 -I scripts/make-sounds.py
"""
import pathlib
import subprocess
import wave

import numpy as np

RATE = 44100
ROOT = pathlib.Path(__file__).resolve().parent.parent
WAV_DIR = ROOT / "design" / "sounds"
MAC_DIR = ROOT / "Sources" / "AlphaNote" / "Resources" / "Sounds"
ANDROID_DIR = ROOT / "Android" / "app" / "src" / "main" / "res" / "raw"


def t(seconds):
    return np.arange(int(seconds * RATE)) / RATE


def tone(freq, seconds, partials=((1, 1.0),), decay=3.0, attack=0.004):
    """Somme de partiels (rapport de fréquence, amplitude) à décroissance exponentielle."""
    x = t(seconds)
    out = np.zeros_like(x)
    for ratio, amp in partials:
        # Les partiels aigus s'éteignent plus vite, comme sur un vrai instrument.
        out += amp * np.sin(2 * np.pi * freq * ratio * x) * np.exp(-decay * ratio ** 0.5 * x)
    env = np.minimum(1, x / attack)
    return out * env


def place(total, events):
    """events : (début en s, signal)."""
    out = np.zeros(int(total * RATE))
    for start, sig in events:
        i = int(start * RATE)
        n = min(len(sig), len(out) - i)
        out[i:i + n] += sig[:n]
    return out


BELL = ((0.5, 0.35), (1, 1.0), (1.19, 0.45), (1.51, 0.35), (2.0, 0.3), (2.52, 0.18), (3.01, 0.12))



def cloche():
    return place(2.6, [(0, tone(392.0, 2.5, BELL, decay=1.3))])



def reveil():
    # Réveil numérique : 4 bips doublés, sinus + un peu de 3e harmonique.
    beep = tone(1760, 0.09, ((1, 1.0), (3, 0.12)), decay=0.0, attack=0.003)
    beep *= np.minimum(1, (0.09 - t(0.09)) / 0.01)  # relâche nette, sans clic
    events = []
    for k in range(4):
        events += [(k * 0.42, beep), (k * 0.42 + 0.13, beep)]
    return place(2.2, events)



def telephone():
    # Sonnerie de téléphone à cloches : un marteau frappe deux timbres ~22 fois/s.
    x = t(0.9)
    strike = (np.sin(2 * np.pi * 22 * x) > 0).astype(float)
    bells = np.sin(2 * np.pi * 1040 * x) + 0.8 * np.sin(2 * np.pi * 1210 * x) + 0.25 * np.sin(2 * np.pi * 2650 * x)
    ring = bells * (0.55 + 0.45 * strike) * np.minimum(1, x / 0.01) * np.minimum(1, (0.9 - x) / 0.05)
    return place(2.6, [(0, ring), (1.15, ring)])


def minuterie():
    # Minuteur de cuisine mécanique : un « ding » clair et long.
    return place(2.4, [(0, tone(2093, 2.3, ((1, 1.0), (2.76, 0.4), (5.4, 0.15)), decay=1.6))])


def sonar():
    ping = tone(1480, 1.2, ((1, 1.0),), decay=3.2, attack=0.002)
    return place(2.6, [(0, ping), (0.38, 0.25 * ping)])  # écho


def cristal():
    # Verre effleuré : partiels aigus inharmoniques, deux touches.
    glass = tone(2637, 1.3, ((1, 1.0), (2.32, 0.5), (4.25, 0.25), (6.3, 0.1)), decay=2.6, attack=0.001)
    return place(2.4, [(0, glass), (0.18, 0.6 * glass)])


def montre():
    # Montre numérique : quatre bips très aigus, une pause.
    beep = tone(4096, 0.06, ((1, 1.0),), decay=0.0, attack=0.002)
    beep *= np.minimum(1, (0.06 - t(0.06)) / 0.008)
    return place(1.6, [(k * 0.12, beep) for k in range(4)])


def bois():
    # Bloc de bois : trois coups secs.
    knock = tone(820, 0.25, ((1, 1.0), (2.9, 0.35)), decay=28.0, attack=0.001)
    return place(1.8, [(0, knock), (0.22, knock), (0.44, knock)])


def alerte():
    # Bip d'alerte insistant (même note), trois impulsions rapides.
    beep = tone(1320, 0.16, ((1, 1.0), (2, 0.15)), decay=0.0, attack=0.004)
    beep *= np.minimum(1, (0.16 - t(0.16)) / 0.02)
    return place(1.6, [(k * 0.24, beep) for k in range(3)])


def pulsation():
    # Impulsions douces et graves, comme un réveil discret.
    def pulse():
        x = t(0.35)
        return np.sin(np.pi * x / 0.35) ** 2 * np.sin(2 * np.pi * 523.25 * x)
    return place(2.0, [(0, pulse()), (0.5, pulse())])


SOUNDS = {
    "minuterie": minuterie, "cloche": cloche, "telephone": telephone, "reveil": reveil, "alerte": alerte,
    "montre": montre, "sonar": sonar, "cristal": cristal, "bois": bois, "pulsation": pulsation,
}


def write_wav(path, signal):
    peak = np.max(np.abs(signal)) or 1
    data = (signal / peak * 0.85 * 32767).astype(np.int16)  # -1,4 dBFS
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data.tobytes())


def main():
    for d in (WAV_DIR, MAC_DIR, ANDROID_DIR):
        d.mkdir(parents=True, exist_ok=True)
    for name, make in SOUNDS.items():
        wav = WAV_DIR / f"{name}.wav"
        write_wav(wav, make())
        for out in (MAC_DIR / f"{name}.m4a", ANDROID_DIR / f"alarm_{name}.m4a"):
            subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "96000", str(wav), str(out)], check=True)
        print("✓", name)


if __name__ == "__main__":
    main()
