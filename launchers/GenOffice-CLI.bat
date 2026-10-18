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
