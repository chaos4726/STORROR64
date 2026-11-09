"""Loop points for rendered Mario 64 tunes, for a player that jumps back by one period: the period P (to the sample,
from the waveform), where the repeating part starts (t0: from there on, a stretch matches its copy a period later),
and the best place to jump back from (tj, t0 + P <= tj: the half second there matches its copy a period earlier
best). Mario 64's engine updates notes in ~16 ms steps, so a second time through can differ by a step: the jump goes
where the two copies agree. python looppoints.py <period_guess_file> <wav>...
period_guess_file: lines "name period_s" (from findloop.py)."""
import sys
import wave

import numpy as np


def load(path):
    w = wave.open(path)
    n, ch, rate = w.getnframes(), w.getnchannels(), w.getframerate()
    return np.frombuffer(w.readframes(n), dtype=np.int16).astype(np.float64).reshape(-1, ch).mean(axis=1), rate


def corr_at(x, a, b, n):
    u, v = x[a:a + n], x[b:b + n]
    den = np.sqrt(np.sum(u * u) * np.sum(v * v)) + 1e-9
    return float(np.sum(u * v) / den)


def best_lag(x, t, P0, n, reach):
    seg = x[t:t + n]
    region = x[t + P0 - reach:t + P0 + reach + n]
    c = np.correlate(region, seg, mode='valid')
    e = np.sqrt(np.convolve(region * region, np.ones(n), mode='valid')) * np.sqrt(np.sum(seg * seg)) + 1e-9
    r = c / e
    k = int(np.argmax(r))
    return P0 - reach + k, float(r[k])


guess = {}
for line in open(sys.argv[1]):
    p = line.split()
    if len(p) >= 3:
        guess[p[0]] = float(p[2])
for path in sys.argv[2:]:
    name = path.replace('\\', '/').split('/')[-1][:-4]
    x, rate = load(path)
    P0 = int(guess[name] * rate)
    n = rate // 2
    # the period, to the sample: the best lag at the best-matching of a few places in the second half
    cands = []
    for frac in np.linspace(0.45, 0.70, 11):
        t = int(len(x) * frac) - P0
        if t < 0 or t + P0 + rate + n > len(x):
            continue
        lag, r = best_lag(x, t, P0, n, rate // 20)
        cands.append((r, lag, t))
    cands.sort(reverse=True)
    r_best, P, _ = cands[0]
    # the correlation of every half second with its copy a period later (allowing a 16 ms step either way)
    step = rate // 4
    prof = []
    for t in range(0, len(x) - P - n, step):
        prof.append((t, corr_at(x, t, t + P, n), P))
    # t0: the first place from which a run of 3 s all matches well
    t0 = None
    for i in range(len(prof) - 12):
        if all(prof[i + k][1] > 0.6 for k in range(12)):
            t0 = prof[i][0]
            break
    if t0 is None:
        t0 = 0
    # tj: within [t0 + P, t0 + 2P), the half second whose copy a period earlier matches best (exactly P apart)
    tj, rj = None, -1
    for t, r, lag in prof:
        if t0 <= t < t0 + P and t + P + n < len(x):
            rr = corr_at(x, t, t + P, n)
            loud = np.mean(np.abs(x[t:t + n]))
            if rr > rj and loud > 50:
                tj, rj = t, rr
    print('%s P %.4f t0 %.3f jump_from %.3f jump_to %.3f corr %.4f (period corr %.4f)' % (
        name, P / rate, t0 / rate, (tj + P) / rate, tj / rate, rj, r_best))
