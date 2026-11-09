# Peach's new lines for the Final Bowser story (ending.lua LINES: "you saved me again and I baked another cake for you
# mario", 2026-11-04), made from the user's own takes. The first try pitched them up 1.6x as they were (ffmpeg rubberband,
# formants shifted with the pitch): a chipmunk - "the pitch up sounds terrible on peaches voice ... make it more closely
# match peaches audio". Here, as Praat's "Change gender" does it: the voice's formants raised a little (FORMANT, by
# resampling) and its pitch set apart from them by pitch-synchronous overlap-add (TD-PSOLA) - her pitch (each line's
# median from her own lines in the game, sfx/peach_*.wav: 230-470 Hz) and her sing-song range (RANGE: her lines move
# about twice as far as the takes do). Then her sound: the game's samples' tone (the long-term spectrum of her lines,
# matched band by band - dark, nothing over ~8.5 kHz), her loudness, and the 0.33 s of silence at the front that
# ending.lua plays them early for. Numpy only.
# python -P tools/peach_voice.py <take.wav (mono 48 kHz)> <out.wav> <median Hz> <peach sfx dir> [tempo]
import sys, os, wave
import numpy as np

FORMANT = 1.17          # (her formants against a man's: F2 ~2350 against ~2050 in the takes)
RANGE = 1.45            # (the pitch's moves about its median, as a power: hers are wider)
SR = 48000


def load(p):
    w = wave.open(p)
    sr, ch, n = w.getframerate(), w.getnchannels(), w.getnframes()
    x = np.frombuffer(w.readframes(n), dtype=np.int16).astype(np.float64) / 32768.0
    if ch > 1:
        x = x.reshape(-1, ch).mean(axis=1)
    if sr != SR:
        t = np.arange(int(len(x) * SR / sr)) / SR
        x = np.interp(t, np.arange(len(x)) / sr, x)
    return x


def lowpass(x, sr, fc):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / sr)
    X[f > fc] = 0.0
    return np.fft.irfft(X, len(x))


def f0_track(x, hop=240):
    # YIN on a 16 kHz copy, 5 ms apart: (Hz or 0, frame rms)
    x16 = lowpass(x, SR, 7000.0)[::3]
    sr, win, tmin, tmax = 16000, 640, 16000 // 600, 16000 // 65
    h = hop // 3
    n = (len(x16) - win - tmax) // h
    peak = max(1e-9, np.max([np.sqrt(np.mean(x16[i * h:i * h + win] ** 2)) for i in range(max(1, n))]))
    f0, rms = np.zeros(max(0, n)), np.zeros(max(0, n))
    for i in range(n):
        s = x16[i * h:i * h + win + tmax]
        a = s[:win]
        rms[i] = np.sqrt(np.mean(a ** 2))
        if rms[i] < 0.04 * peak:
            continue
        r = np.correlate(s, a, 'valid')                       # (tau = 0..tmax)
        e = np.cumsum(np.concatenate([[0.0], s ** 2]))
        et = e[win:win + tmax + 1] - e[0:tmax + 1]
        d = r[0] + et - 2.0 * r
        d[0] = 0.0
        c = np.cumsum(d[1:])
        dn = np.ones_like(d)
        dn[1:] = d[1:] * np.arange(1, len(d)) / np.maximum(c, 1e-12)
        t = None
        for k in range(tmin, tmax - 1):
            if dn[k] < 0.15 and dn[k] <= dn[k + 1]:
                t = k
                break
        if t is None:
            k = tmin + int(np.argmin(dn[tmin:tmax]))
            if dn[k] < 0.35:
                t = k
        if t is None:
            continue
        if 1 <= t < len(dn) - 1:                               # (parabolic, between samples)
            a0, a1, a2 = dn[t - 1], dn[t], dn[t + 1]
            den = a0 - 2 * a1 + a2
            t = t + (0.5 * (a0 - a2) / den if abs(den) > 1e-12 else 0.0)
        f0[i] = sr / t
    v = f0 > 0
    if v.sum() > 5:
        med = np.median(f0[v])
        f0[v & (f0 > 1.75 * med)] /= 2.0                       # (octave slips)
        f0[v & (f0 < med / 1.75)] *= 2.0
        g = f0.copy()                                          # (a 5-frame median through the voiced runs)
        for i in range(len(f0)):
            if f0[i] > 0:
                w = f0[max(0, i - 2):i + 3]
                g[i] = np.median(w[w > 0])
        f0 = g
        # (lone voiced or unvoiced frames: taken as their neighbours)
        for i in range(1, len(f0) - 1):
            if (f0[i] > 0) != (f0[i - 1] > 0) and (f0[i - 1] > 0) == (f0[i + 1] > 0):
                f0[i] = 0.5 * (f0[i - 1] + f0[i + 1]) if f0[i - 1] > 0 else 0.0
    return f0, hop


def psola(x, f0, hop, target_med, tempo):
    # the formants up by FORMANT: y is x played that much faster (every frequency up, its length down)
    a = FORMANT
    ty = np.arange(int(len(x) / a)) * a
    y = np.interp(ty, np.arange(len(x)), x)
    v = f0 > 0
    src_med = np.median(f0[v])

    def f0_x(tx):                                             # (the take's pitch at x's sample tx, or 0)
        i = int(tx / hop)
        return f0[i] if 0 <= i < len(f0) else 0.0

    def f0_new(tx):
        f = f0_x(tx)
        if f <= 0:
            return 0.0
        return float(np.clip(target_med * (f / src_med) ** RANGE, 170.0, 720.0))

    # pitch marks in y: a peak of its low band each period, in the voiced parts; every 5 ms in the rest
    ylp = lowpass(y, SR, 1500.0)
    UNV = 240
    marks, voiced = [], []
    t = 0
    while t < len(y) - 2:
        f = f0_x(t * a) * a
        if f > 0:
            P = SR / f
            if marks and voiced[-1]:
                c = marks[-1] + P
                lo, hi = int(c - 0.2 * P), int(c + 0.2 * P) + 1
            else:
                lo, hi = int(t), int(t + P) + 1
            lo, hi = max(lo, 0), min(hi, len(y))
            if hi <= lo + 1:
                break
            m = lo + int(np.argmax(ylp[lo:hi]))
            if marks and m <= marks[-1]:
                m = marks[-1] + max(1, int(P))
            marks.append(m)
            voiced.append(True)
            t = m
        else:
            m = int(t + UNV)
            marks.append(m)
            voiced.append(False)
            t = m
    marks = np.array(marks)
    periods = np.full(len(marks), float(UNV))
    for i in range(len(marks)):
        if voiced[i]:
            l = marks[i] - marks[i - 1] if i > 0 and voiced[i - 1] else None
            r = marks[i + 1] - marks[i] if i + 1 < len(marks) and voiced[i + 1] else None
            ps = [p for p in (l, r) if p]
            periods[i] = np.mean(ps) if ps else SR / max(1.0, f0_x(marks[i] * a) * a)
    # overlap-add: output time ts is x's ts/tempo, y's ts/(tempo*a)
    n_out = int(len(x) * tempo) + SR
    out, ws = np.zeros(n_out), np.zeros(n_out)
    ts = float(marks[0] * a * tempo) if len(marks) else 0.0
    while ts < len(x) * tempo and len(marks):
        ta = ts / (tempo * a)
        i = int(np.clip(np.searchsorted(marks, ta), 0, len(marks) - 1))
        if i > 0 and abs(marks[i - 1] - ta) < abs(marks[i] - ta):
            i -= 1
        P = int(max(16, round(periods[i])))
        m = marks[i]
        if voiced[i]:
            fn = f0_new(ts / tempo)
            Ps = SR / fn if fn > 0 else UNV
        else:
            Ps = UNV
        lo, hi = m - P, m + P + 1
        if lo >= 0 and hi <= len(y):
            w = np.hanning(2 * P + 1)
            g = y[lo:hi] * w
            c = int(round(ts))
            o0, o1 = c - P, c + P + 1
            if o0 >= 0 and o1 <= n_out:
                out[o0:o1] += g
                ws[o0:o1] += w
        ts += Ps
    out = out / np.maximum(ws, 0.6)
    return out[:int(len(x) * tempo)]


def ltas(x, n=4096):
    # long-term average power spectrum, 1/3-octave smoothed, of the loud frames
    frames = [x[i:i + n] for i in range(0, len(x) - n, n // 4)]
    if not frames:
        frames = [np.pad(x, (0, n - len(x)))]
    r = np.array([np.sqrt(np.mean(f ** 2)) for f in frames])
    keep = [f for f, v in zip(frames, r) if v > 0.1 * r.max()]
    P = np.mean([np.abs(np.fft.rfft(f * np.hanning(n))) ** 2 for f in keep], axis=0)
    fq = np.fft.rfftfreq(n, 1.0 / SR)
    S = np.zeros_like(P)
    for k, f in enumerate(fq):
        lo, hi = f / 1.122, f * 1.122
        m = (fq >= lo) & (fq <= hi)
        S[k] = P[m].mean() if m.any() else P[k]
    return fq, S


def main():
    src, dst, target = sys.argv[1], sys.argv[2], float(sys.argv[3])
    peach_dir = sys.argv[4]
    tempo = float(sys.argv[5]) if len(sys.argv) > 5 else 1.0
    x = load(src)
    # (its silence off both ends, 60 ms kept)
    fr = 480
    r = np.array([np.sqrt(np.mean(x[i:i + fr] ** 2)) for i in range(0, len(x) - fr, fr)])
    on = np.where(r > 0.03 * r.max())[0]
    a0, a1 = max(0, (on[0] - 6) * fr), min(len(x), (on[-1] + 7) * fr)
    x = x[a0:a1]
    x = x - np.mean(x)
    f0, hop = f0_track(x)
    v = f0 > 0
    print('%s: %.2f s, pitch median %.0f Hz (%.0f-%.0f), %d%% voiced' % (os.path.basename(src), len(x) / SR, np.median(f0[v]),
          np.percentile(f0[v], 10), np.percentile(f0[v], 90), 100 * v.mean()))
    y = psola(x, f0, hop, target, tempo)
    # her tone: the game's samples' long-term spectrum, band by band (within +-18 dB), and nothing over 8.5 kHz
    ref = None
    for nme in ('peach_power', 'peach_special', 'peach_thanks_to_you', 'peach_mario', 'peach_thank_you', 'peach_for_mario'):
        p = os.path.join(peach_dir, nme + '.wav')
        if os.path.exists(p):
            z = load(p)
            fq, S = ltas(z)
            ref = S / S.sum() if ref is None else ref + S / S.sum()
    fq, S = ltas(y)
    gain = np.sqrt(np.maximum(ref / ref.sum(), 1e-30) / np.maximum(S / S.sum(), 1e-30))
    gain = np.clip(gain, 10 ** (-18 / 20), 10 ** (18 / 20))
    gain[fq < 120] *= 0.3
    gain *= np.clip((9000.0 - fq) / 1000.0, 0.0, 1.0)
    Y = np.fft.rfft(y)
    fy = np.fft.rfftfreq(len(y), 1.0 / SR)
    Y *= np.interp(fy, fq, gain)
    y = np.fft.irfft(Y, len(y))
    # her loudness: her lines' rms over their loud parts, about 0.10 (and never over 0.95)
    def loud_rms(z):
        fr = 2400
        rr = np.array([np.sqrt(np.mean(z[i:i + fr] ** 2)) for i in range(0, len(z) - fr, fr)])
        return np.sqrt(np.mean(rr[rr > 0.3 * rr.max()] ** 2))
    y *= 0.10 / max(1e-9, loud_rms(y))
    pk = np.max(np.abs(y))
    if pk > 0.95:
        # (a soft limit on the peaks, not the whole line down)
        y = np.tanh(y / 0.95 * 1.2) * 0.95 / np.tanh(1.2)
    # fades, the front silence, a tail
    nf = int(0.02 * SR)
    y[:nf] *= np.linspace(0, 1, nf)
    y[-nf:] *= np.linspace(1, 0, nf)
    y = np.concatenate([np.zeros(int(0.33 * SR)), y, np.zeros(int(0.25 * SR))])
    s = (np.clip(y, -1, 1) * 32767).astype(np.int16)
    st = np.repeat(s[:, None], 2, axis=1)
    w = wave.open(dst, 'wb')
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(st.tobytes())
    w.close()
    print('  -> %s (%.2f s)' % (dst, len(y) / SR))


if __name__ == '__main__':
    main()
