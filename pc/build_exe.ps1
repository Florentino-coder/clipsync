$ErrorActionPreference = "Stop"

if (!(Test-Path ".\.venv\Scripts\python.exe")) {
    if (Get-Command py -ErrorAction SilentlyContinue) {
        py -3 -m venv .venv
    } else {
        python -m venv .venv
    }
}

.\.venv\Scripts\python.exe -m pip install --no-cache-dir -r requirements.txt
.\.venv\Scripts\python.exe -m pip install --no-cache-dir pyinstaller==6.20.0

Remove-Item -Recurse -Force .\dist\ClipSyncPC -ErrorAction SilentlyContinue
Remove-Item -Force .\dist\ClipSyncPC.exe -ErrorAction SilentlyContinue

# Onedir (installer) — uses checked-in ClipSyncPC.spec with chrome-extension datas.
.\.venv\Scripts\python.exe -m PyInstaller `
    --noconfirm `
    --clean `
    ClipSyncPC.spec

# Expose chrome-extension at onedir root for Inno Setup Source (stable path install).
$onedir = Join-Path $PSScriptRoot "dist\ClipSyncPC"
$extRoot = Join-Path $onedir "chrome-extension"
$extInternal = Join-Path $onedir "_internal\chrome-extension"
if (-not (Test-Path (Join-Path $extRoot "manifest.json"))) {
    if (Test-Path (Join-Path $extInternal "manifest.json")) {
        if (Test-Path $extRoot) {
            Remove-Item -Recurse -Force $extRoot
        }
        Copy-Item -Recurse -Force $extInternal $extRoot
    } elseif (Test-Path "$PSScriptRoot\chrome-extension\manifest.json") {
        Copy-Item -Recurse -Force "$PSScriptRoot\chrome-extension" $extRoot
    }
}

$root = $PSScriptRoot
$extraData = @('--add-data', "$root\assets\clipsync_icon.png;assets")
if (Test-Path "$root\chrome-extension\manifest.json") {
    $extraData += @('--add-data', "$root\chrome-extension;chrome-extension")
}

$hiddenImports = @(
    '--hidden-import', 'psutil',
    '--hidden-import', 'websockets',
    '--hidden-import', 'cryptography'
)

# Onefile portable — write spec under build/ so we never overwrite ClipSyncPC.spec.
.\.venv\Scripts\python.exe -m PyInstaller `
    --noconfirm `
    --clean `
    --onefile `
    --windowed `
    --name ClipSyncPC `
    --icon "$root\assets\clipsync.ico" `
    @extraData `
    @hiddenImports `
    --distpath dist `
    --workpath build `
    --specpath build `
    clipsync_pc.py
