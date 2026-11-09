#!/usr/bin/env bash
# Generates a synthetic HLS stream (test pattern + sine tone, 30 s, unencrypted) into media/.
# Layout mirrors the stream where the issue was found: MPEG-TS, H.264 High + AAC muxed,
# multi-variant master playlist, no EXT-X-MEDIA, no CEA-608.
set -euo pipefail
cd "$(dirname "$0")"

OUT=media
DURATION=30
rm -rf "$OUT"
mkdir -p "$OUT"

# name  size     level  codec-string  video-bitrate  bandwidth
VARIANTS=(
  "v360 640x360 3.0 avc1.64001e 800k 1000000"
  "v144 256x144 1.2 avc1.64000c 200k 350000"
)

for v in "${VARIANTS[@]}"; do
  read -r name size level _codec vbr _bw <<<"$v"
  ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i "testsrc2=size=${size}:rate=30" \
    -f lavfi -i "sine=frequency=440:sample_rate=48000" \
    -t "$DURATION" \
    -c:v libx264 -profile:v high -level "$level" -pix_fmt yuv420p -b:v "$vbr" \
    -g 60 -keyint_min 60 -sc_threshold 0 \
    -c:a aac -b:a 96k -ac 2 \
    -f hls -hls_time 10 -hls_playlist_type vod \
    -hls_segment_filename "$OUT/${name}_%03d.ts" "$OUT/${name}.m3u8"
done

{
  echo '#EXTM3U'
  echo '#EXT-X-VERSION:3'
  echo '#EXT-X-INDEPENDENT-SEGMENTS'
  for v in "${VARIANTS[@]}"; do
    read -r name size _level codec _vbr bw <<<"$v"
    echo "#EXT-X-STREAM-INF:BANDWIDTH=${bw},CODECS=\"${codec},mp4a.40.2\",RESOLUTION=${size},FRAME-RATE=30.000"
    echo "${name}.m3u8"
  done
} > "$OUT/master.m3u8"

# Progressive MP4 with the same content (to check whether non-HLS playback is affected)
ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "testsrc2=size=640x360:rate=30" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000" \
  -t "$DURATION" \
  -c:v libx264 -profile:v high -level 3.0 -pix_fmt yuv420p -b:v 800k -g 60 \
  -c:a aac -b:a 96k -ac 2 \
  -movflags +faststart "$OUT/video.mp4"

ls -l "$OUT"
