#!/usr/bin/env python3
# Cuts single key presses out of a typing recording, for typing sounds.
# Usage: python3 Tools/slice_keystrokes.py typing.wav Resources/Sounds/<name> 10
# (convert first: ffmpeg -i in.mp3 -ac 1 -ar 44100 -c:a pcm_s16le typing.wav)
import sys, wave, numpy as np, os
src, out, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
w = wave.open(src); sr = w.getframerate()
x = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float32) / 32768
hop = 64
env = np.sqrt(np.convolve(x**2, np.ones(hop)/hop, 'same'))[::hop]
floor = np.percentile(env, 30)
onsets = []
for i in range(4, len(env)):
    rise = env[i] - env[i-4:i].mean()
    if env[i] > max(floor*6, 0.02) and rise > env[i]*0.6:
        t = i*hop
        if not onsets or t - onsets[-1] > 0.08*sr: onsets.append(t)
L = int(0.28*sr); pre = int(0.004*sr)
cands = []
for k, t in enumerate(onsets):
    prev = onsets[k-1] if k else -10**9; nxt = onsets[k+1] if k+1 < len(onsets) else 10**12
    if t - prev < 0.12*sr or nxt - t < 0.3*sr: continue   # isolated presses only
    seg = x[max(0, t-pre): t-pre+L]
    if len(seg) < L: continue
    before = x[max(0, t-int(0.05*sr)): t-pre]
    clean = np.abs(seg).max() / (np.sqrt((before**2).mean()) + 1e-6)
    cands.append((clean, t, seg))
print(len(onsets), "onsets,", len(cands), "isolated")
cands.sort(key=lambda c: -c[0])
peaks = sorted(np.abs(c[2]).max() for c in cands[:n*3])
mid = np.median(peaks) if peaks else 0
# cleanest takes, close to the median loudness so they sound even
pick = [c for c in cands[:n*3] if 0.5*mid < np.abs(c[2]).max() < 2*mid][:n]
os.makedirs(out, exist_ok=True)
for j, (_, t, seg) in enumerate(pick, 1):
    seg = seg.copy()
    f = int(0.06*sr); seg[-f:] *= np.linspace(1, 0, f)
    seg[:pre] *= np.linspace(0, 1, pre)
    seg *= 10**(-3/20) / np.abs(seg).max()
    o = wave.open(f"{out}/{j}.wav", "w"); o.setnchannels(1); o.setsampwidth(2); o.setframerate(sr)
    o.writeframes((seg*32767).astype(np.int16).tobytes()); o.close()
    print(j, round(t/sr, 2))
