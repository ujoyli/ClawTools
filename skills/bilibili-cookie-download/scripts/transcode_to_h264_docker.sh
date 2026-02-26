#!/usr/bin/env bash
set -euo pipefail

IN="${1:-}"
OUT="${2:-}"

if [[ -z "$IN" || -z "$OUT" ]]; then
  echo "Usage: transcode_to_h264_docker.sh <input.mp4> <output.mp4>" >&2
  exit 2
fi

if [[ ! -f "$IN" ]]; then
  echo "Input not found: $IN" >&2
  exit 2
fi

mkdir -p "$(dirname "$OUT")"

# Use a dockerized ffmpeg with libx264 enabled.
IMG="jrottenberg/ffmpeg:7.0-ubuntu"

WORKDIR="/work"
IN_BASENAME="$(basename "$IN")"
OUT_BASENAME="$(basename "$OUT")"

docker run --rm \
  -v "$(cd "$(dirname "$IN")" && pwd):$WORKDIR" \
  -w "$WORKDIR" \
  "$IMG" \
  -y -i "$IN_BASENAME" \
  -c:v libx264 -pix_fmt yuv420p -preset veryfast -crf 23 \
  -c:a aac -b:a 128k \
  -movflags +faststart \
  "$OUT_BASENAME"

echo "wrote $OUT"
