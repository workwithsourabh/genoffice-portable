# GenOffice Portable (Windows)

A **folder-portable** build of [GenOffice](https://github.com/genspark-ai/genoffice) for Windows x64.
Unzip anywhere — USB stick, another drive, another PC — and run it.
No installer, no admin rights, no registry changes, nothing written outside the folder.

> **Just want to use it?** Grab the ZIP from the
> [latest release](../../releases/latest), extract it, and double-click
> `GenOffice-Portable.bat`. You do **not** need to clone or build anything.

## Download

| | |
|---|---|
| Release | **[v0.11.0](../../releases/tag/v0.11.0)** |
| File | `GenOffice-Portable-0.11.0-win-x64.zip` (~600 MB) |
| Upstream | [genspark-ai/genoffice](https://github.com/genspark-ai/genoffice) @ `1f306a2a` |
| License | Apache-2.0 (upstream), binaries unsigned |

Verify the download against the `SHA256SUMS.txt` published with the release.

## Usage

```
GenOffice-Portable.bat          start the app (GUI)
GenOffice-Portable.bat file.docx    ...and open a document
GenOffice-CLI.bat --version     the "genoffice" CLI, bundled runtime (no Node.js needed)
GenOffice-CLI.bat create report.docx --title "Quarterly Report"
GenOffice-CLI.bat mcp           MCP server for AI agents
```

Everything the app writes — settings, SQLite file index, projects, autosaves,
caches, API keys (`data\auth\auth.json`), temp files — stays under `data\`
inside the folder. Delete `data\` to reset to first-run state.

The folder is fully relocatable: the launchers resolve everything relative to
their own location, so you can move/rename/copy it freely. Always start via
the `.bat` files — launching `app\GenOffice.exe` directly bypasses the
redirects and falls back to `%APPDATA%`.

Full details: [`README-PORTABLE.txt`](release-assets) inside the ZIP, and
[BUILD-REPORT.md](BUILD-REPORT.md) in this repo.

## What's inside the ZIP

```
GenOffice-Portable\
  GenOffice-Portable.bat    GUI launcher
  GenOffice-CLI.bat         CLI launcher
  README-PORTABLE.txt       user documentation
  BUILD-REPORT.md           how it was built and what was tested
  app\                      GenOffice 0.11.0 (unpacked electron-builder output + Rust xlsx sidecar + win-ocr)
  data\                     created on first run — all writable state
```

## Building from source

The binaries are unsigned — if you prefer to verify what you run, build it
yourself:

```powershell
# Prerequisites: Node.js 24, Rust stable (MSVC), Windows 10/11 SDK, git
git clone https://github.com/genspark-ai/genoffice
cd genoffice
git checkout 1f306a2a496227cae9194097897212c93d00a4e6
git apply ..\genoffice-portable\patches\portable-patches.patch
powershell -ExecutionPolicy Bypass -File ..\genoffice-portable\tools\build-portable.ps1 -SmokeTest
```

The output lands in `..\GenOffice-Portable`. See [BUILD-REPORT.md](BUILD-REPORT.md)
for the full breakdown of the three patches, the portable redirection
mechanism, and the complete test matrix.

### Repository contents

| Path | Purpose |
|---|---|
| `patches/portable-patches.patch` | the 3 upstream patches (all portable-redirection; no feature or security changes) |
| `tools/build-portable.ps1` | one-command reproducible build → portable folder |
| `tools/portable-smoke.mjs` | Playwright GUI smoke test (13 checks: open/edit/save/reopen DOCX, XLSX/PPTX/PDF/Markdown tabs, data isolation) |
| `BUILD-REPORT.md` | build log, test results, known limitations |

Binaries are **not** stored in git — they ship only as release assets.

## Security notes

* Binaries are **not code-signed**; SmartScreen may warn on first run.
* `auth.json` (AI keys) is stored in **plain text** inside `data\auth\` —
  same model as upstream's `~/.genoffice`. Don't put keys there on a shared machine.
* No auto-update feed is configured (by design for a portable build).
* Electron security settings are unchanged from upstream.

## License

This packaging (patches, scripts, docs) is provided under the same
**Apache-2.0** license as upstream GenOffice. The bundled binaries include
GenOffice and ~570 npm + ~144 Rust dependencies — full inventory in
`app\THIRD-PARTY-NOTICES.txt` inside the ZIP.
