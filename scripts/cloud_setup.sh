#!/bin/bash
# OpenMontage — cloud environment setup script.
#
# Paste the contents of this file into the "Setup script" field of your cloud
# environment at claude.ai/code. It runs once per environment; the filesystem is
# then snapshotted and reused, so later sessions start with everything already
# on disk. It re-runs when you edit the script, change the network allowlist, or
# the snapshot expires (roughly weekly).
#
# Two constraints the environment imposes:
#   * the script must exit 0, or the session fails to start — hence `|| true`
#   * it must finish inside roughly five minutes, or the snapshot won't build
#
# Per-session work belongs in .claude/hooks/session-start.sh instead.
# See docs/cloud-environment.md for the network allowlist and API keys.
set -u

REPO="${CLAUDE_PROJECT_DIR:-/home/user/OpenMontage}"

# FFmpeg gates composition, stitching and most analysis tools.
apt-get update -qq && apt-get install -y -qq ffmpeg || true

# Python and Node installs are independent, so run them side by side to stay
# inside the five-minute budget.
(
  python3 -m pip install -q -r "$REPO/requirements-dev.txt" || true
  python3 -m pip install -q piper-tts faster-whisper yt-dlp || true
) &
PY_PID=$!

(
  cd "$REPO/remotion-composer" && npm install --no-audit --no-fund >/dev/null 2>&1 || true
) &
NODE_PID=$!

# Warm the npx cache so the first HyperFrames render doesn't pay the cold fetch.
(
  npx --yes hyperframes --version >/dev/null 2>&1 || true
) &
HF_PID=$!

wait $PY_PID $NODE_PID $HF_PID || true

exit 0
