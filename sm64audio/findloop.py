"""Find where a rendered Mario 64 tune starts repeating: the loop's start (after any intro) and its length, to the
sample. The renderer is deterministic, so once the sequence has looped the audio repeats almost exactly.
python findloop.py <wav>...  -> one line per file: name start_s length_s match"""
import sys
import wave

import numpy as np


def load(path):
    w = wave.open(path)
    n, ch, rate = w.getnframes(), w.getnchannels(), w.getframerate()
    a = np.frombuffer(w.readframes(n), dtype=np.int16).astype(np.float32).reshape(-1, ch)
    return a.mean(axis=1), rate


def find(x, rate):
    hop = 256
    env = np.sqrt(np.add.reduceat(x * x, np.arange(0, len(x) - hop, hop)) / hop)
    env = env - env.mean()
    # the period: the lag (5 s .. 200 s) at which the envelope matches itself best
    lo, hi = int(5 * rate / hop), min(int(200 * rate / hop), len(env) // 2)
    f = np.fft.rfft(env, 2 * len(env))
    ac = np.fft.irfft(f * np.conj(f))[:len(env)]
    norm = np.array([len(env) - k for k in range(len(env))], dtype=np.float64)
    ac = ac / norm
    best = None
    # (prefer the shortest strong period: multiples of the true one score as well)
    peak = ac[lo:hi].max()
    for k in range(lo, hi):
        if ac[k] >= 0.92 * peak and ac[k] >= ac[k - 1] and ac[k] >= ac[k + 1]:
            best = k
            break
    if best is None:
        best = lo + int(np.argmax(ac[lo:hi]))
    P = best * hop
    # to the sample: compare a second of audio well into the tune with the same a period later
    t1 = len(x) - P - 3 * rate
    seg = x[t1:t1 + rate]
    bestd, bestP = None, P
    for dP in range(-2 * hop, 2 * hop + 1):
        q = t1 + P + dP
        if q < 0 or q + rate > len(x):
            continue
        d = np.mean(np.abs(seg - x[q:q + rate]))
        if bestd is None or d < bestd:
            bestd, bestP = d, P + dP
    P = bestP
    scale = np.mean(np.abs(seg)) + 1e-6
    # the loop's start: walk back while a quarter-second window still matches its copy a period later
    win = rate // 4
    t = t1
    while t - win >= 0:
        a, b = x[t - win:t], x[t - win + P:t + P]
        if np.mean(np.abs(a - b)) > 0.02 * scale + 1.0:
            break
        t -= win
    # (to the sample within that last window)
    for s in range(win, 0, -1):
        if abs(x[t - s] - x[t - s + P]) <= 0.02 * scale + 1.0 and np.all(np.abs(x[t - s:t] - x[t - s + P:t + P]) <= 0.05 * scale + 2.0):
            t = t - s
            break
    return t, P, bestd / scale


if __name__ == '__main__':
    for path in sys.argv[1:]:
        x, rate = load(path)
        t, P, m = find(x, rate)
        name = path.replace('\\', '/').split('/')[-1][:-4]
        print('%s %.4f %.4f %.5f %d %d' % (name, t / rate, P / rate, m, t, P))
