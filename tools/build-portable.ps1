#Requires -Version 5.1
<#
.SYNOPSIS
  Rebuilds the GenOffice portable distribution from this source tree.

.DESCRIPTION
  Produces a folder-portable GenOffice (no installer, no admin, no AppData):
    1. npm install                       (skip with -SkipInstall if node_modules is current)
    2. third-party notices generation
    3. build:all                         (modules, shell renderer, CLI, Rust xlsx sidecar)
    4. win-ocr.exe                       (pdf2docx OCR helper; needs MSVC + Windows SDK)
    5. electron-builder --win dir        (unpacked app at apps\shell\release\win-unpacked)
    6. assemble the portable folder      (app\ + GenOffice-Portable.bat + GenOffice-CLI.bat)
    7. optional GUI smoke test           (-SmokeTest; needs playwright-core in node_modules)

  The three portable patches (GENOFFICE_USER_DATA when packaged, GENOFFICE_AUTH_DIR
  in the gsk shim, GENOFFICE_WIN_SIDECAR override) are ALREADY APPLIED in this tree.
  This script does not modify the tree; it only builds and packages it.

.PARAMETER OutDir
  Where the portable distribution is assembled. Default: <repo>\..\GenOffice-Portable
  (i.e. a sibling of GenOffice-Source). Existing app\ content is replaced; other
  files in OutDir are left alone.

.PARAMETER SkipInstall
  Skip "npm install" (use when node_modules is already up to date).

.PARAMETER SmokeTest
  Run tools\portable-smoke.mjs against the assembled distribution after building.

.EXAMPLE
  .\tools\build-portable.ps1

.EXAMPLE
  .\tools\build-portable.ps1 -SkipInstall -SmokeTest
#>
param(
  [string]$OutDir = "",
  [switch]$SkipInstall,
  [switch]$SmokeTest
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot   # <repo root>
Set-Location $repo

if (-not $OutDir) {
  $OutDir = Join-Path (Split-Path -Parent $repo) 'GenOffice-Portable'
}

function Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Fail($msg) { Write-Host "BUILD FAILED: $msg" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
Step '1/7  npm install'
if ($SkipInstall) {
  Write-Host 'skipped (-SkipInstall)'
  if (-not (Test-Path 'node_modules')) { Fail 'node_modules missing; rerun without -SkipInstall' }
} else {
  npm install
  if ($LASTEXITCODE -ne 0) { Fail 'npm install' }
}

# ---------------------------------------------------------------------------
Step '2/7  third-party notices'
npm run notices
if ($LASTEXITCODE -ne 0) { Fail 'npm run notices' }

# ---------------------------------------------------------------------------
Step '3/7  build:all (modules, shell, CLI, Rust sidecar)'
npm run build:all
if ($LASTEXITCODE -ne 0) { Fail 'npm run build:all' }

# The packaged sidecar is the host-MSVC build produced by build:all.
$sidecar = Join-Path $repo 'target\release\xlsx-sidecar.exe'
if (-not (Test-Path $sidecar)) { Fail "Rust sidecar missing at $sidecar" }
Write-Host "sidecar: $sidecar"

# ---------------------------------------------------------------------------
Step '4/7  win-ocr.exe'
node packages\pdf2docx\ocr-helper\build-win.mjs
if ($LASTEXITCODE -ne 0) { Fail 'win-ocr build' }

# ---------------------------------------------------------------------------
Step '5/7  electron-builder --win dir (unpacked, no installer)'
$env:GENOFFICE_WIN_SIDECAR = $sidecar
npx electron-builder --win dir --config apps\shell\electron-builder.cjs
if ($LASTEXITCODE -ne 0) { Fail 'electron-builder' }
$unpacked = Join-Path $repo 'apps\shell\release\win-unpacked'
if (-not (Test-Path (Join-Path $unpacked 'GenOffice.exe'))) { Fail "GenOffice.exe missing in $unpacked" }
if (-not (Test-Path (Join-Path $unpacked 'resources\native\xlsx-sidecar.exe'))) { Fail 'sidecar not packaged' }
if (Test-Path (Join-Path $unpacked 'resources\app-update.yml')) {
  Fail 'app-update.yml present - auto-update must stay disabled for the portable build'
}

# ---------------------------------------------------------------------------
Step "6/7  assemble portable distribution -> $OutDir"
$appOut = Join-Path $OutDir 'app'
if (Test-Path $appOut) { Remove-Item $appOut -Recurse -Force }
New-Item -ItemType Directory -Force -Path $appOut | Out-Null
Copy-Item (Join-Path $unpacked '*') $appOut -Recurse -Force

# Launchers travel with the distribution; write them fresh so the assembled
# folder is self-contained even on a clean OutDir.
$guiBat = @'
@echo off
rem ===========================================================================
rem  GenOffice-Portable launcher
rem  Starts the bundled GenOffice app with ALL writable data kept inside this
rem  portable folder. No installation, no admin rights, no system PATH changes.
rem  The folder can be moved or copied anywhere; nothing is hard-coded.
rem ===========================================================================
setlocal

rem -- %~dp0 is this script's folder, always with a trailing backslash --------
set "ROOT=%~dp0"
set "APPDIR=%ROOT%app"
set "EXE=%APPDIR%\GenOffice.exe"

rem -- Diagnostics: fail loudly if the app payload is missing ----------------
if not exist "%EXE%" (
    echo.
    echo  [GenOffice-Portable] ERROR: GenOffice.exe was not found at:
    echo      "%EXE%"
    echo.
    echo  This launcher must stay inside the portable folder, next to the
    echo  "app" directory. If you moved only the .bat file, move the whole
    echo  "GenOffice-Portable" folder instead.
    echo.
    pause
    exit /b 1
)
if not exist "%APPDIR%\resources\app.asar" (
    echo.
    echo  [GenOffice-Portable] ERROR: The app payload is incomplete
    echo  ^(missing "%APPDIR%\resources\app.asar"^).
    echo  Re-copy the full portable distribution.
    echo.
    pause
    exit /b 1
)
if not exist "%APPDIR%\resources\native\xlsx-sidecar.exe" (
    echo  [GenOffice-Portable] WARNING: xlsx-sidecar.exe is missing.
    echo  Spreadsheets ^(.xlsx^) will not open correctly.
    echo.
)

rem -- Portable data layout (created on first run) ---------------------------
rem     data\user   app settings, SQLite file index, projects, autosaves,
rem                 downloaded fonts, Chromium/Electron caches and profiles
rem     data\auth   API keys / sign-in state (auth.json), CLI audit log
rem     data\temp   temporary files (pasted images, imports, conversions)
set "DATA=%ROOT%data"
set "USERDATA=%DATA%\user"
set "AUTHDIR=%DATA%\auth"
set "TEMPDIR=%DATA%\temp"

if not exist "%USERDATA%" mkdir "%USERDATA%"
if not exist "%AUTHDIR%"  mkdir "%AUTHDIR%"
if not exist "%TEMPDIR%" mkdir "%TEMPDIR%"

rem -- Environment the app reads before it writes anything -------------------
rem GENOFFICE_USER_DATA: redirects Electron userData (settings, file-index.db,
rem   projects, caches) and the single-instance lock into the portable folder.
rem GENOFFICE_AUTH_DIR: redirects auth.json, the CLI launcher marker and the
rem   CLI audit log out of %%USERPROFILE%%\.genoffice.
rem TMP/TEMP: traps os.tmpdir() use by the app, the CLI and the sidecar.
set "GENOFFICE_USER_DATA=%USERDATA%"
set "GENOFFICE_AUTH_DIR=%AUTHDIR%"
set "TMP=%TEMPDIR%"
set "TEMP=%TEMPDIR%"

rem -- Launch (extra arguments are passed through, e.g. document paths) ------
start "" "%EXE%" %*

endlocal
exit /b 0
'@
$cliBat = @'
@echo off
rem ===========================================================================
rem  GenOffice-CLI launcher
rem  Runs the bundled "genoffice" command line on the portable app's own
rem  Node runtime (ELECTRON_RUN_AS_NODE). No Node.js install required.
rem
rem  Examples:
rem    GenOffice-CLI.bat --version
rem    GenOffice-CLI.bat create report.docx --title "Quarterly Report"
rem    GenOffice-CLI.bat convert input.pdf --to docx
rem    GenOffice-CLI.bat mcp          (MCP server on stdio, for AI agents)
rem
rem  Agent skills: GenOffice-CLI.bat skill install <claude|codex|cursor|...>
rem ===========================================================================
setlocal

set "ROOT=%~dp0"
set "APPDIR=%ROOT%app"
set "EXE=%APPDIR%\GenOffice.exe"
set "CLI=%APPDIR%\resources\cli\genoffice.cjs"

if not exist "%EXE%" (
    echo [GenOffice-CLI] ERROR: GenOffice.exe not found at "%EXE%". 1>&2
    echo Keep this .bat inside the portable folder, next to "app". 1>&2
    exit /b 1
)
if not exist "%CLI%" (
    echo [GenOffice-CLI] ERROR: CLI bundle not found at "%CLI%". 1>&2
    echo The portable distribution is incomplete - re-copy it. 1>&2
    exit /b 1
)

rem -- Same portable data dirs as GenOffice-Portable.bat ---------------------
set "DATA=%ROOT%data"
if not exist "%DATA%\user" mkdir "%DATA%\user"
if not exist "%DATA%\auth" mkdir "%DATA%\auth"
if not exist "%DATA%\temp" mkdir "%DATA%\temp"
set "GENOFFICE_USER_DATA=%DATA%\user"
set "GENOFFICE_AUTH_DIR=%DATA%\auth"
set "TMP=%DATA%\temp"
set "TEMP=%DATA%\temp"

rem -- Run the CLI on the Electron/Node runtime bundled in GenOffice.exe -----
set "ELECTRON_RUN_AS_NODE=1"
"%EXE%" "%CLI%" %*
exit /b %ERRORLEVEL%
'@
# UTF-8 without BOM: the .bat files are pure ASCII; Set-Content -Encoding ascii
# also keeps cmd.exe happy on every code page.
Set-Content -Path (Join-Path $OutDir 'GenOffice-Portable.bat') -Value $guiBat -Encoding ascii
Set-Content -Path (Join-Path $OutDir 'GenOffice-CLI.bat') -Value $cliBat -Encoding ascii

# ---------------------------------------------------------------------------
Step '7/7  portable GUI smoke test'
if ($SmokeTest) {
  $fixtures = Join-Path $env:TEMP 'genoffice-tests'
  $env:GENOFFICE_SMOKE_FIXTURES = $fixtures
  node tools\portable-smoke.mjs $OutDir
  if ($LASTEXITCODE -ne 0) { Fail 'portable smoke test' }
} else {
  Write-Host 'skipped (pass -SmokeTest to run tools\portable-smoke.mjs)'
}

Step "DONE - portable distribution at $OutDir"
Write-Host "Start it with:  $OutDir\GenOffice-Portable.bat"
