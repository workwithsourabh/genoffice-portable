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
if not exist "%TEMPDIR%"  mkdir "%TEMPDIR%"

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
