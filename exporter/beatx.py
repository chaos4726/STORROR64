"""The beat of a piece of music, for nodding along to it.

Takes raw sound (mono, 16-bit, 22050 a second, as ffmpeg writes it), finds how the energy of its attacks
rises and falls, works out the tempo from how that pattern repeats, and then places the beats: each
one where the attacks are strongest near where the tempo says it should fall. Writes the beat times and
how hard each one hits (0..1) as data/title_beats.lua.

Usage: python beatx.py <audio.raw> <out dir>"""
import sys, os, math
import numpy as np

SR, HOP, WIN = 22050, 256, 1024


def onset_envelope(x):
    n = 1 + (len(x) - WIN) // HOP
    w = np.hanning(WIN)
    prev, env = None, np.zeros(n)
    for i in range(n):
        s = np.abs(np.fft.rfft(x[i * HOP:i * HOP + WIN] * w))
        s = np.log1p(40.0 * s)
        if prev is not None:
            d = s - prev
            env[i] = d[d > 0].sum()                 # only what got louder
        prev = s
    env -= np.convolve(env, np.ones(87) / 87.0, mode='same')     # take the slow swell out (about a second)
    env[env < 0] = 0
    return env / (env.max() or 1.0)


def tempo(env, lo=70.0, hi=180.0):
    fps = SR / HOP
    ac = np.correlate(env, env, mode='full')[len(env) - 1:]
    best, score = None, -1
    for bpm in np.arange(lo, hi, 0.1):
        lag = 60.0 / bpm * fps
        v = 0.0
        for k in (1, 2, 3, 4):                      # a beat repeats at its own spacing and its multiples
            j = lag * k
            i = int(j)
            if i + 1 < len(ac):
                v += (ac[i] * (1 - (j - i)) + ac[i + 1] * (j - i)) / k
        if v > score:
            best, score = bpm, v
    return best


def track(env, bpm, tight=100.0):
    """Ellis's beat tracker: beats where the attacks are strong and the spacing stays near the tempo."""
    fps = SR / HOP
    period = 60.0 / bpm * fps
    n = len(env)
    score, back = env.copy(), np.full(n, -1)
    lo, hi = int(round(period * 0.5)), int(round(period * 2.0))
    for i in range(n):
        a, b = max(0, i - hi), i - lo
        if b <= a:
            continue
        prev = np.arange(a, b)
        penalty = -tight * np.log((i - prev) / period) ** 2
        cand = score[prev] + penalty
        j = int(np.argmax(cand))
        if cand[j] > 0:
            score[i] = env[i] + cand[j]
            back[i] = prev[j]
    i = int(np.argmax(score[-int(period * 2):])) + n - int(period * 2)
    beats = []
    while i >= 0:
        beats.append(i)
        i = back[i]
    return np.array(beats[::-1])


def main(raw, out_dir):
    x = np.frombuffer(open(raw, 'rb').read(), dtype='<i2').astype(np.float32) / 32768.0
    env = onset_envelope(x)
    bpm = tempo(env)
    beats = track(env, bpm)
    fps = SR / HOP
    times = beats / fps
    # how hard each beat hits: the attack around it, against the loudest in the piece
    hit = np.array([env[max(0, b - 3):b + 4].max() for b in beats])
    hit = np.clip(hit / (np.percentile(hit, 90) or 1.0), 0.0, 1.0)
    # a head does not stop for one soft beat in a loud passage, nor jump for one loud one in a quiet passage:
    # each beat's weight is mostly how loud the music is around it (four beats either side), partly its own
    pad = np.pad(hit, 4, mode='edge')
    around = np.convolve(pad, np.ones(9) / 9.0, mode='valid')
    hit = 0.6 * around + 0.4 * hit
    hit = np.clip(hit / (hit.max() or 1.0), 0.0, 1.0)
    gaps = np.diff(times)
    print('length %.2f s, tempo %.1f beats a minute, %d beats, spacing %.3f s (from %.3f to %.3f)' % (
        len(x) / SR, bpm, len(times), np.median(gaps), gaps.min(), gaps.max()))
    print('first beats:', ' '.join('%.2f' % t for t in times[:12]))
    print('how hard, by tenths of the piece:', ' '.join('%.2f' % hit[int(len(hit) * k / 10):int(len(hit) * (k + 1) / 10)].mean() for k in range(10)))
    if out_dir:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import sm64x as X
        X.write_lua(os.path.join(out_dir, 'Scripts', 'data', 'title_beats.lua'),
                    {'bpm': round(float(bpm), 2), 'length': round(len(x) / SR, 3),
                     'times': [round(float(t), 3) for t in times], 'hit': [round(float(h), 2) for h in hit]},
                    header="-- (this file: the beats of the music of STORROR's start film, found by beatx.py)\n")
        print('wrote title_beats.lua')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
