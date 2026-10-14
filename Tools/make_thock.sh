#!/bin/zsh
# Makes Thocky and Creamy soft from the CC0 recordings already in Resources/Sounds.
# Thocky: slowed and lowered a lot, the click filtered off and the low thud
# lifted, like a heavy board. Creamy soft: lowered a little, the top smoothed off
# and the attack softened, for a smooth muted press without the boom. The
# peak level is matched to the other sounds. Needs ffmpeg. Run from the repo root.
set -e
tmp=$(mktemp -t f99thock).wav
make() { # name, source folder, speed, cutoff Hz, extra filters
  mkdir -p "Resources/Sounds/$1"
  for f in Resources/Sounds/$2/*.wav; do
    ffmpeg -loglevel error -y -i "$f" -af "asetrate=44100*$3,aresample=44100,\
lowpass=f=$4:p=2,lowpass=f=$4,$5,\
afade=t=out:st=0.22:d=0.08,atrim=0:0.3" \
      -ac 1 -ar 44100 -c:a pcm_s16le "$tmp"
    # Same peak as the other sounds (-3 dB).
    peak=$(ffmpeg -i "$tmp" -af volumedetect -f null - 2>&1 | sed -n 's/.*max_volume: \(.*\) dB/\1/p')
    ffmpeg -loglevel error -y -i "$tmp" -af "volume=$(( -3 - peak ))dB" -c:a pcm_s16le "Resources/Sounds/$1/${f:t}"
  done
}
make thocky tactile 0.72 2200 "bass=g=7:f=130,equalizer=f=300:t=q:w=1.2:g=3"
make creamySoft soft 0.86 3200 "equalizer=f=600:t=q:w=1:g=3,treble=g=-4:f=2500,afade=t=in:d=0.004"
rm -f "$tmp"
