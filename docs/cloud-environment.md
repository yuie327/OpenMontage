# Running OpenMontage in a Claude Code cloud session

A cloud session runs on an Anthropic-managed VM that clones this repository
fresh and is reclaimed after a period of inactivity. Nothing from the previous
session's working directory survives, so the toolchain has to be restored before
any tool in `tools/` can import, let alone run.

Two mechanisms restore it, and they do different jobs.

| | Setup script | SessionStart hook |
|---|---|---|
| Configured in | The environment dialog at claude.ai/code | `.claude/settings.json` in this repo |
| Runs | Once per environment, then the filesystem is snapshotted and reused | Every session, cloud and local |
| Good for | apt packages, toolchains, large downloads | `npm install`, `pip install`, project setup |

The snapshot is why a cloud session is not as disposable as it first looks.
Packages the setup script installs, npm dependencies, and model weights all
carry over to later sessions. The setup script re-runs only when you edit it,
change the network allowlist, or the snapshot expires after roughly a week.

## 1. Setup script

Copy the contents of [`scripts/cloud_setup.sh`](../scripts/cloud_setup.sh) into
the **Setup script** field of your environment at claude.ai/code.

It installs FFmpeg, the Python dependencies, the zero-key providers (Piper TTS,
faster-whisper, yt-dlp), the Remotion composer's npm dependencies, and warms the
HyperFrames npx cache. Every command is suffixed with `|| true` because a
non-zero exit makes the session fail to start, and the independent installs run
in parallel to stay inside the roughly five-minute budget.

## 2. SessionStart hook

Already committed — [`.claude/hooks/session-start.sh`](../.claude/hooks/session-start.sh),
registered in `.claude/settings.json`. It exits immediately unless
`CLAUDE_CODE_REMOTE=true`, so a local checkout set up with `make setup` pays
nothing for it.

In a cloud session it fills in whatever the snapshot is missing: FFmpeg, the
Python dependencies, the Piper voice models, `remotion-composer/node_modules`,
and a `.env` placeholder.
It runs synchronously, so the session starts with the toolchain already in
place rather than racing against it.

Once this is merged to `main`, every future cloud session picks it up.

## 3. Network allowlist

The default **Trusted** access level reaches package registries and GitHub, and
nothing else. Every provider API this project calls is outside that list, so
image generation, video generation and cloud TTS all fail with connection errors
until you widen it.

Set **Network access** to **Custom**, check *Also include default list of common
package managers*, and add the hosts for the providers you actually use. A
leading `*.` matches subdomains.

```text
# Image and video gateway (FLUX, Veo, Kling, MiniMax, Recraft)
fal.ai
*.fal.ai
fal.run
queue.fal.run

# Stock footage and images
api.pexels.com
pixabay.com

# Speech and music
api.elevenlabs.io
texttospeech.googleapis.com
generativelanguage.googleapis.com

# Direct provider APIs
api.minimax.io
api.minimaxi.com
replicate.com
api.heygen.com
api.x.ai
api-singapore.klingai.com
platform.higgsfield.ai
api.dev.runwayml.com
dashscope.aliyuncs.com

# Model weights and public archives
huggingface.co
*.huggingface.co
archive.org
```

Trim this to the providers you have keys for. Every host you add is a host the
session can reach, so a shorter list is a smaller blast radius.

## 4. API keys

Two places, and they behave differently.

**Environment variables** — the **Environment variables** field in the
environment dialog. Readable inside the session, same as any shell variable.
Fine for non-secret settings such as `MINIMAX_REGION`.

**API credentials** — on Pro and Max plans, the environment dialog stores keys
outside the sandbox and attaches them to matching outbound requests after they
leave the session. The agent never sees the key itself. Prefer this for anything
that can spend money.

Locally, keys go in a `.env` file at the repo root; `lib/env_loader.py` and
`tools/base_tool.py` load it on import. `.env` is gitignored and must stay that
way. Use `.env.example` as the reference for every variable name the tools read.

## 5. What still won't work in the cloud

Worth knowing before you plan a production run there.

- **No GPU.** The local video-generation tools (`wan_video`, `hunyuan_video`,
  `ltx_video_local`, `cogvideo_video`) ask for 8–40 GB of VRAM and stay
  unavailable. Video generation means a paid API.
- **Renders don't persist.** Output lands in `projects/<name>/renders/` inside a
  VM that gets reclaimed. Video files don't belong in git, so anything you want
  to keep has to be uploaded somewhere first.
- **Modest hardware.** Roughly 4 cores, 16 GB RAM and a fixed disk allowance.
  Long compositions are slow.
- **No access to your machine.** Screen capture, Playwright recording of a local
  app, and local source footage are all local-only.

Cloud sessions suit work *on* this repository — editing skills and pipeline
definitions, running tests, opening pull requests. Actual production runs belong
on a local checkout.

## Local setup

```bash
git clone https://github.com/yuie327/OpenMontage.git
cd OpenMontage
make setup          # creates .venv, installs deps, npm install, copies .env.example to .env
```

Then add your keys to `.env` and check what lit up:

```bash
make preflight
```
