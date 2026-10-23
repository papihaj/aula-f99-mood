#!/usr/bin/env python3
# Cuts single key presses out of a typing recording, for typing sounds.
# Usage: python3 Tools/slice_keystrokes.py typing.wav Resources/Sounds/<name> 10 [warmth dB]
# (convert first: ffmpeg -i in.mp3 -ac 1 -ar 44100 -c:a pcm_s16le typing.wav)
# Creamy: freesound 868632 with warmth 3.5, Creamy light: freesound 815614 with
# warmth 2 (the -hq.mp3 previews).
import sys, wave, numpy as np, os
src, out, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
warmth = float(sys.argv[4]) if len(sys.argv) > 4 else 0

def biquad(x, b, a):
    y = np.zeros_like(x); x1 = x2 = y1 = y2 = 0.0
    for i, v in enumerate(x):
        y[i] = (b[0]*v + b[1]*x1 + b[2]*x2 - a[1]*y1 - a[2]*y2) / a[0]
        x2, x1, y2, y1 = x1, v, y1, y[i]
    return y

def warm(x, sr, gain_db, hz=150, q=0.8):
    # Picking the presses with the most click leaves them lighter than the
    # keyboard sounds, so lift the body around 150 Hz back up. Below 40 Hz
    # goes: that rumble is a thump, not warmth.
    A = 10**(gain_db/40); w = 2*np.pi*hz/sr; al = np.sin(w)/(2*q); c = np.cos(w)
    x = biquad(x, (1+al*A, -2*c, 1-al*A), (1+al/A, -2*c, 1-al/A))
    w = 2*np.pi*40/sr; al = np.sin(w)/np.sqrt(2); c = np.cos(w)
    return biquad(x, ((1+c)/2, -(1+c), (1+c)/2), (1+al, -2*c, 1-al))
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
    # Thud (40-250 Hz) against click (above 1.5 kHz). Some presses in a
    # recording are only a thud, which sounds like a door closing.
    X = np.abs(np.fft.rfft(seg, 16384))**2; f = np.fft.rfftfreq(16384, 1/sr)
    thud = X[(f > 40) & (f < 250)].sum() / X[f > 1500].sum()
    ring = np.sqrt((seg[int(0.08*sr):]**2).mean()) / np.sqrt((seg[:int(0.04*sr)]**2).mean())
    cands.append((thud, ring, t, seg))
print(len(onsets), "onsets,", len(cands), "isolated")
mid = np.median([np.abs(c[3]).max() for c in cands]) if cands else 0
# close to the median loudness so they sound even, not ringing on after the
# press, then the least thud
pick = sorted((c for c in cands if 0.5*mid < np.abs(c[3]).max() < 2*mid and c[1] < 0.35),
              key=lambda c: c[0])[:n]
os.makedirs(out, exist_ok=True)
for j, (thud, _, t, seg) in enumerate(pick, 1):
    seg = warm(seg.astype(np.float64), sr, warmth) if warmth else seg.copy()
    f = int(0.06*sr); seg[-f:] *= np.linspace(1, 0, f)
    seg[:pre] *= np.linspace(0, 1, pre)
    seg *= 10**(-3/20) / np.abs(seg).max()
    o = wave.open(f"{out}/{j}.wav", "w"); o.setnchannels(1); o.setsampwidth(2); o.setframerate(sr)
    o.writeframes((seg*32767).astype(np.int16).tobytes()); o.close()
    print(j, round(t/sr, 2), "thud", round(thud, 2))
