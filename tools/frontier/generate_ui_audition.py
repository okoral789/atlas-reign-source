"""Original cartoon UI listening study. No external recordings or BOOM audio used.

Generated audio is CC0. This does not change the game's sound bindings.
"""
from pathlib import Path
import hashlib
import json
import wave

import numpy as np

from generate_battle_audio import SR, env, layer, noise

OUT = Path(__file__).resolve().parents[2] / 'assets/audio-ui-study-1'


def bubble(seconds, start, end, fall=.018):
    t = np.arange(round(seconds * SR)) / SR
    phase = 2 * np.pi * (end*t + (start-end)*fall*(1-np.exp(-t/fall)))
    return env(np.sin(phase) + .12*np.sin(phase*2), attack=.0015, decay=.030)


def mallet(freq, seconds=.34):
    t = np.arange(round(seconds * SR)) / SR
    out = np.zeros(len(t))
    # Inharmonic modes and independent decay imitate a struck bar rather than a fixed beep.
    for ratio, gain, decay in [(1, 1, .11), (2.76, .29, .045), (5.4, .07, .018)]:
        out += gain*np.sin(2*np.pi*freq*ratio*t)*np.exp(-t/decay)
    return env(out, attack=.002, decay=.5)


def swoosh():
    seconds = .24
    t = np.arange(round(seconds * SR)) / SR
    air = noise(seconds, 11)
    air -= np.convolve(air, np.ones(81)/81, mode='same')
    air *= np.sin(np.pi*t/seconds)**2
    # A very quiet descending elastic body gives the swipe a soft end.
    return layer(.32, [(0, air, .26), (.115, bubble(.15, 560, 170, .025), .2)])


def stereo(a):
    left, right = a.copy(), a.copy()
    for delay, gain in [(.027, .065), (.049, .035), (.081, .018)]:
        shift = round(delay*SR)
        if shift < len(a):
            left[shift:] += a[:-shift]*gain
            shift += 137
            if shift < len(a):
                right[shift:] += a[:-shift]*gain
    return np.column_stack([left, right])


def master(a, peak):
    a = np.asarray(a, dtype=float)
    a -= a.mean()
    a = stereo(a)
    a *= peak / max(float(np.max(np.abs(a))), 1e-9)
    fade = min(round(.006*SR), len(a)//2)
    a[:fade] *= np.linspace(0, 1, fade)[:, None]
    a[-fade:] *= np.linspace(1, 0, fade)[:, None]
    assert np.isfinite(a).all() and np.max(np.abs(a)) <= .61
    assert np.sqrt(np.mean(a*a)) > .003
    assert not a[0].any() and not a[-1].any()
    return a


def write(path, a):
    with wave.open(str(path), 'wb') as f:
        f.setparams((2, 2, SR, 0, 'NONE', 'not compressed'))
        f.writeframes(np.round(a*32767).astype('<i2').tobytes())
    with wave.open(str(path)) as f:
        assert f.getnchannels() == 2 and f.getframerate() == SR
        assert f.getnframes() == len(a)


def generate():
    OUT.mkdir(parents=True, exist_ok=True)
    click = layer(.16, [(0, bubble(.16, 1100, 230, .009), .65),
                         (.003, env(noise(.12, 5), attack=.001, decay=.004), .10),
                         (.006, mallet(410, .14), .14)])
    pop = layer(.23, [(0, bubble(.17, 660, 145, .025), .66),
                      (.055, bubble(.13, 920, 350, .012), .23),
                      (0, env(noise(.14, 18), attack=.001, decay=.008), .10)])
    confirm = layer(.53, [(0, mallet(659), .60), (.075, mallet(988), .46),
                          (.01, bubble(.12, 520, 310), .12)])
    error = layer(.34, [(0, bubble(.19, 450, 205, .055), .5),
                        (.09, mallet(220, .23), .25),
                        (.016, env(noise(.09, 12), attack=.001, decay=.012), .1)])
    reward = layer(.92, [(0, mallet(523, .6), .48), (.09, mallet(659, .6), .46),
                         (.18, mallet(784, .6), .42), (.29, mallet(1046, .6), .39),
                         (.05, bubble(.14, 990, 280), .14)])
    cues = [('click', 'Jelly click', click, .40), ('pop', 'Bubble pop', pop, .43),
            ('swipe', 'Soft swipe', swoosh(), .27), ('confirm', 'Confirm', confirm, .43),
            ('error', 'Soft error', error, .33), ('reward', 'Reward', reward, .57)]
    report, demo, cursor = {}, [np.zeros((round(.25*SR), 2))], .25
    for name, title, raw, peak in cues:
        a = master(raw, peak)
        path = OUT / (name+'.wav')
        write(path, a)
        report[name] = {'title': title, 'start_seconds': round(cursor, 3),
                        'seconds': len(a)/SR, 'peak': float(np.max(np.abs(a))),
                        'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
        # Repeat short cues once so the phone audition has time to register the timbre.
        demo.extend([a, np.zeros((round(.25*SR), 2)), a, np.zeros((round(.6*SR), 2))])
        cursor += len(a)*2/SR + .85
    assert len({row['sha256'] for row in report.values()}) == len(cues)
    write(OUT/'listen.wav', np.concatenate(demo))
    (OUT/'generated.json').write_text(json.dumps({'licence': 'CC0-1.0',
        'source': 'Original mathematical synthesis; no external audio samples.',
        'purpose': 'Private listening study; not imported into Roblox.', 'cues': report},
        indent=2)+'\n', encoding='utf-8', newline='\n')
    (OUT/'LICENSE.txt').write_text('Original generated audio dedicated to CC0 1.0.\n'
        'https://creativecommons.org/publicdomain/zero/1.0/\n'
        'Generator code follows the repository licence. No BOOM or other third-party audio used.\n',
        encoding='utf-8', newline='\n')
    print(f'Generated {len(cues)} original cues and {cursor:.2f}s audition; '
          'checked PCM headers, distinct files, finite samples, peaks and zero endpoints.')


if __name__ == '__main__':
    generate()
