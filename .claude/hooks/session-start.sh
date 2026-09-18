#!/bin/bash
# OpenMontage — SessionStart hook.
#
# Cloud sessions start from a fresh clone, so the toolchain has to be put back
# before anything in tools/ can be imported. Local checkouts are set up once
# with `make setup`, so this exits early there and costs nothing.
#
# Heavy, slow-changing installs belong in the cloud environment's setup script
# (see docs/cloud-environment.md) — that one is snapshotted and reused. This
# hook runs on every session, so it only does the work that is still missing.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$PROJECT_DIR"

log() { echo "[openmontage-setup] $*"; }

# The session runs as root, and pip's warning about that is noise on every start.
export PIP_ROOT_USER_ACTION=ignore
export PIP_DISABLE_PIP_VERSION_CHECK=1

# FFmpeg gates video_compose, video_stitch, hyperframes_compose and most of the
# analysis tools. Usually already present from the environment's setup script.
if ! command -v ffmpeg >/dev/null 2>&1; then
  log "installing ffmpeg"
  (apt-get update -qq && apt-get install -y -qq ffmpeg) >/dev/null 2>&1 \
    || log "WARN ffmpeg install failed — composition tools stay unavailable"
fi

# requirements-dev.txt includes requirements.txt plus pytest. Installed into the
# session interpreter rather than a .venv so `python3` works without activation;
# pip is close to a no-op once the packages are already satisfied.
log "installing python dependencies"
python3 -m pip install -q -r requirements-dev.txt \
  || log "WARN python dependency install failed"

# Zero-key providers: offline TTS, local transcription, source-video downloads.
python3 -m pip install -q piper-tts faster-whisper yt-dlp \
  || log "WARN optional provider install failed — cloud providers still work"

# `npm install` rather than `ci` so a cached node_modules is reused instead of
# being deleted and refetched.
if [ ! -d remotion-composer/node_modules ]; then
  log "installing remotion-composer dependencies"
  (cd remotion-composer && npm install --no-audit --no-fund) >/dev/null 2>&1 \
    || log "WARN npm install failed — Remotion compositions stay unavailable"
fi

# Tools read API keys from the repo-root .env via load_dotenv. In cloud sessions
# the keys arrive as environment variables instead, so this only lays down the
# placeholder file that the loader expects to find.
if [ ! -f .env ]; then
  cp .env.example .env
fi

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PYTHONPATH=\"$PROJECT_DIR\"" >> "$CLAUDE_ENV_FILE"
fi

log "ready — run 'make preflight' to see which providers are available"
