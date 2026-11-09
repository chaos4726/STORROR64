"""For a tune and a rough period: the exact lag (+-1 s) with the best waveform correlation at a few points, to see
whether the loop repeats sample-exactly. python loopcheck.py <wav> <period_s>"""
import sys
import wave

import numpy as np

w = wave.open(sys.argv[1])
n, ch, rate = w.getnframes(), w.getnchannels(), w.getframerate()
x = np.frombuffer(w.readframes(n), dtype=np.int16).astype(np.float64).reshape(-1, ch).mean(axis=1)
P0 = int(float(sys.argv[2]) * rate)
for t1 in (int(n * 0.30), int(n * 0.45), int(n * 0.55)):
    seg = x[t1:t1 + rate // 2]
    if t1 + P0 + rate * 2 > n:
        continue
    lo, hi = P0 - rate, P0 + rate
    region = x[t1 + lo:t1 + hi + len(seg)]
    # normalised cross-correlation of seg against every lag in the region
    c = np.correlate(region, seg, mode='valid')
    e = np.sqrt(np.convolve(region * region, np.ones(len(seg)), mode='valid')) * np.sqrt(np.sum(seg * seg)) + 1e-9
    r = c / e
    k = int(np.argmax(r))
    lag = lo + k
    d = np.mean(np.abs(seg - x[t1 + lag:t1 + lag + len(seg)])) / (np.mean(np.abs(seg)) + 1e-9)
    print('t1 %.1f s: best lag %d (%.4f s) corr %.5f diff %.4f' % (t1 / rate, lag, lag / rate, r[k], d))
