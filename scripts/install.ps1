<#
.SYNOPSIS
    One-command OpenMontage setup for Windows.

.DESCRIPTION
    Windows has no `make`, so `make setup` does not work there. This script does
    the same job: checks the prerequisites, installs FFmpeg, creates the virtual
    environment, installs the Python and Node dependencies, and creates .env.

    Run it from the repository root:

        .\scripts\install.ps1

    If PowerShell refuses to run it, allow local scripts for this session first:

        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

    Safe to run more than once — anything already installed is left alone.

.PARAMETER SkipFFmpeg
    Don't try to install FFmpeg. Use this if you installed it yourself, or if
    winget isn't available on your machine.
#>

[CmdletBinding()]
param(
    [switch]$SkipFFmpeg
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

$script:Warnings = @()

function Write-Step ($Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Ok ($Message) {
    Write-Host "    $Message" -ForegroundColor Green
}

function Add-Warning ($Message) {
    $script:Warnings += $Message
    Write-Host "    ! $Message" -ForegroundColor Yellow
}

function Test-Command ($Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

# --- Prerequisites ----------------------------------------------------------
# Python and Node are the two things this script cannot install for you: both
# need choices (version, install location) that belong to you, not a script.

Write-Step "Checking prerequisites"

# `py` is the Windows Python launcher and picks the newest interpreter; plain
# `python` on Windows may be the Microsoft Store stub, which cannot build venvs.
# Kept as exe + argument array so the array can splat empty — PowerShell reads
# a descending range like 1..0 backwards, so index slicing would misfire here.
$PythonExe = $null
$PythonArgs = @()
if (Test-Command 'py') {
    $PythonExe = 'py'
    $PythonArgs = @('-3')
} elseif (Test-Command 'python') {
    $PythonExe = 'python'
} else {
    Write-Host ""
    Write-Host "Python is not installed." -ForegroundColor Red
    Write-Host "Install Python 3.10 or newer from https://www.python.org/downloads/"
    Write-Host "Tick 'Add python.exe to PATH' in the installer, then run this script again."
    exit 1
}

$PyVersion = & $PythonExe @PythonArgs -c "import sys; print('%d.%d' % sys.version_info[:2])" 2>$null
if (-not $PyVersion) {
    Write-Host "Could not run Python. Reinstall it from https://www.python.org/downloads/" -ForegroundColor Red
    exit 1
}
$PyParts = $PyVersion.Trim().Split('.')
if ([int]$PyParts[0] -lt 3 -or ([int]$PyParts[0] -eq 3 -and [int]$PyParts[1] -lt 10)) {
    Write-Host "OpenMontage needs Python 3.10 or newer; found $PyVersion." -ForegroundColor Red
    Write-Host "Install a newer one from https://www.python.org/downloads/"
    exit 1
}
Write-Ok "Python $PyVersion"

if (Test-Command 'node') {
    $NodeVersion = (& node --version).Trim()
    Write-Ok "Node $NodeVersion"
} else {
    Write-Host ""
    Write-Host "Node.js is not installed." -ForegroundColor Red
    Write-Host "Install Node.js 22 or newer from https://nodejs.org/ then run this script again."
    Write-Host "Without it, Remotion and HyperFrames compositions cannot render."
    exit 1
}

# --- FFmpeg -----------------------------------------------------------------
# FFmpeg gates composition, stitching and most of the analysis tools. Without
# it the majority of the tool registry reports unavailable.

Write-Step "Checking FFmpeg"

if (Test-Command 'ffmpeg') {
    Write-Ok "FFmpeg already installed"
} elseif ($SkipFFmpeg) {
    Add-Warning "FFmpeg missing and -SkipFFmpeg was passed; composition tools stay unavailable"
} elseif (Test-Command 'winget') {
    Write-Host "    Installing FFmpeg via winget (this takes a minute)..."
    winget install --id Gyan.FFmpeg --accept-package-agreements --accept-source-agreements --silent 2>&1 | Out-Null

    # winget puts FFmpeg on PATH for new shells, not this one, so re-read PATH
    # from the registry rather than telling you to reopen the terminal.
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('Path', 'User')

    if (Test-Command 'ffmpeg') {
        Write-Ok "FFmpeg installed"
    } else {
        Add-Warning "FFmpeg installed but not on PATH yet — close this terminal and open a new one"
    }
} else {
    Add-Warning "winget not available; install FFmpeg yourself from https://ffmpeg.org/download.html"
}

# --- Virtual environment ----------------------------------------------------
# Everything below installs into .venv rather than your system Python, so
# nothing here can disturb other Python projects on this machine.

Write-Step "Setting up the virtual environment"

$VenvPython = Join-Path $RepoRoot '.venv\Scripts\python.exe'

if (Test-Path $VenvPython) {
    Write-Ok "Reusing existing .venv"
} else {
    & $PythonExe @PythonArgs -m venv .venv
    if (-not (Test-Path $VenvPython)) {
        Write-Host "Could not create the virtual environment in .venv" -ForegroundColor Red
        exit 1
    }
    Write-Ok "Created .venv"
}

Write-Step "Installing Python dependencies"
& $VenvPython -m pip install --upgrade pip --quiet --disable-pip-version-check
& $VenvPython -m pip install -r requirements.txt --disable-pip-version-check
if ($LASTEXITCODE -ne 0) {
    Write-Host "Python dependency install failed. The output above says why." -ForegroundColor Red
    exit 1
}
Write-Ok "Dependencies installed"

# Free offline TTS. Optional: cloud providers cover narration without it, so a
# failure here is a warning rather than a stop.
Write-Step "Installing offline TTS (Piper)"
& $VenvPython -m pip install piper-tts --quiet --disable-pip-version-check
if ($LASTEXITCODE -eq 0) {
    Write-Ok "Piper TTS installed"
} else {
    Add-Warning "Piper TTS install failed — narration will need a cloud TTS key instead"
}

# --- Node dependencies ------------------------------------------------------

Write-Step "Installing Remotion composer dependencies"

Push-Location (Join-Path $RepoRoot 'remotion-composer')
npm install --no-audit --no-fund
if ($LASTEXITCODE -ne 0) {
    # Known Windows failure: npm shipped with some Node builds throws
    # ERR_INVALID_ARG_TYPE here. Running it through npx uses a different copy.
    Write-Host "    npm install failed; retrying through npx..." -ForegroundColor Yellow
    npx --yes npm install --no-audit --no-fund
}
if ($LASTEXITCODE -eq 0) {
    Write-Ok "Remotion composer ready"
} else {
    Add-Warning "npm install failed — Remotion compositions stay unavailable"
}
Pop-Location

# Pull the HyperFrames CLI into the npx cache so the first render doesn't pay a
# cold fetch. Purely a speed optimisation.
Write-Step "Warming the HyperFrames cache"
npx --yes hyperframes --version 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Ok "HyperFrames CLI cached"
} else {
    Add-Warning "HyperFrames cache warm failed — the first render will fetch it on demand"
}

# --- API keys ---------------------------------------------------------------
# Tools read keys from a .env at the repository root. It is gitignored.

Write-Step "Setting up .env"

if (Test-Path (Join-Path $RepoRoot '.env')) {
    Write-Ok ".env already exists — leaving it alone"
} else {
    Copy-Item (Join-Path $RepoRoot '.env.example') (Join-Path $RepoRoot '.env')
    Write-Ok "Created .env from .env.example"
}

# --- Report -----------------------------------------------------------------

Write-Step "Checking which tools are available"

$Available = & $VenvPython -c "from tools.tool_registry import registry; registry.discover(); e=registry.support_envelope(); a=[k for k,v in e.items() if str(v.get('status','')).upper().startswith('AVAIL')]; print('%d of %d' % (len(a), len(e)))" 2>$null

Write-Host ""
Write-Host "-----------------------------------------------------------"
if ($Available) {
    Write-Host " Setup complete. $($Available.Trim()) tools are available." -ForegroundColor Green
} else {
    Write-Host " Setup complete." -ForegroundColor Green
}

if ($script:Warnings.Count -gt 0) {
    Write-Host ""
    Write-Host " Finished with $($script:Warnings.Count) warning(s):" -ForegroundColor Yellow
    foreach ($w in $script:Warnings) {
        Write-Host "   - $w" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host " Next:"
Write-Host "   1. Add API keys to .env to unlock more providers (optional)."
Write-Host "   2. Open this folder in your AI coding assistant and describe"
Write-Host "      the video you want."
Write-Host ""
Write-Host " To see the full provider list at any time:"
Write-Host "   .venv\Scripts\python.exe -c `"from tools.tool_registry import registry; import json; registry.discover(); print(json.dumps(registry.provider_menu(), indent=2))`""
Write-Host "-----------------------------------------------------------"
Write-Host ""
