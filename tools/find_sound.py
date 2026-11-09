# find_sound.py <rec.raw (f32 stereo 48k)> <sound.wav> [t0 t1]: where the sound is in a process-loopback recording, and
# how its loudness there compares with the file's own, 50 ms at a time (a quiet or missing stretch shows as "!!")
import sys, wave
import numpy as np
from numpy.fft import rfft, irfft
rec = np.fromfile(sys.argv[1], dtype='<f4').reshape(-1, 2).mean(axis=1)
w = wave.open(sys.argv[2])
h = np.frombuffer(w.readframes(w.getnframes()), dtype='<i2').astype(np.float32).reshape(-1, w.getnchannels()).mean(axis=1) / 32768.0
t0 = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0
t1 = float(sys.argv[4]) if len(sys.argv) > 4 else len(rec) / 48000
part = rec[int(t0 * 48000):int(t1 * 48000)]
N = 1
while N < len(part) + len(h): N *= 2
c = irfft(rfft(part, N) * np.conj(rfft(h, N)), N)[:max(1, len(part) - len(h))]
i = int(np.argmax(c))
seg = part[i:i + len(h)]
norm = np.sqrt((h ** 2).sum() * (seg ** 2).sum()) + 1e-9
print('recording %.2f s; best match at %.3f s, correlation %.3f' % (len(rec) / 48000, t0 + i / 48000, c[i] / norm))
k = 2400
oe = np.array([np.sqrt((h[j:j + k] ** 2).mean()) for j in range(0, len(h) - k + 1, k)])
re_ = np.array([np.sqrt((seg[j:j + k] ** 2).mean()) for j in range(0, len(seg) - k + 1, k)])
n = min(len(oe), len(re_))
oe, re_ = oe[:n], re_[:n]
loud = oe > oe.max() * 0.15
scale = np.median(re_[loud] / oe[loud])
print('gain (median) %.3f' % scale)
print(' '.join(('%.2f' % (re_[j] / (oe[j] * scale))) if loud[j] else '  - ' for j in range(n)))
