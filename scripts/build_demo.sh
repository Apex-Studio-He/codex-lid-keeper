#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
project_dir="$(cd "$script_dir/.." && pwd -P)"
output_dir="$project_dir/docs/demo"
output="$output_dir/codex-lid-keeper-ui-walkthrough.mp4"

ffmpeg_binary="$(command -v ffmpeg || true)"
if [[ -z "$ffmpeg_binary" && -x /opt/homebrew/bin/ffmpeg ]]; then
  ffmpeg_binary="/opt/homebrew/bin/ffmpeg"
fi
if [[ -z "$ffmpeg_binary" ]]; then
  printf 'ffmpeg is required to build the optional UI walkthrough.\n' >&2
  exit 1
fi

/bin/mkdir -p "$output_dir"
"$ffmpeg_binary" -y \
  -loop 1 -t 8 -i "$project_dir/docs/images/social-preview.jpg" \
  -loop 1 -t 8 -i "$project_dir/docs/images/gallery-01-hero.jpg" \
  -loop 1 -t 8 -i "$project_dir/docs/images/gallery-02-safety.jpg" \
  -loop 1 -t 8 -i "$project_dir/docs/images/social-preview.jpg" \
  -filter_complex \
  "[0:v]scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2:color=0x080a0d[v0];[1:v]scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2:color=0x080a0d[v1];[2:v]scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2:color=0x080a0d[v2];[3:v]scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2:color=0x080a0d[v3];[v0][v1]xfade=transition=fade:duration=1:offset=7[x1];[x1][v2]xfade=transition=fade:duration=1:offset=14[x2];[x2][v3]xfade=transition=fade:duration=1:offset=21,format=yuv420p[out]" \
  -map "[out]" \
  -r 30 \
  -c:v libx264 \
  -pix_fmt yuv420p \
  -preset slow \
  -crf 22 \
  -movflags +faststart \
  -metadata title="Codex Lid Keeper v0.3.0 UI walkthrough" \
  -metadata comment="UI walkthrough only; not a physical closed-lid hardware test." \
  "$output"

printf 'Built %s\n' "$output"
