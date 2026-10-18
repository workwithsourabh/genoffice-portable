# GenOffice Portable — Build Report

**Deliverable:** `D:\Portables\GenOffice-Portable` (folder-portable GenOffice for Windows x64)
**Built:** 2026-10-18
**Upstream:** https://github.com/genspark-ai/genoffice @ `1f306a2a496227cae9194097897212c93d00a4e6` (2026-10-17)
**App version:** 0.11.0 (`GenOffice.exe` FileVersion 0.11.0)
**Distribution size:** ~607 MB total (`app\` ~589 MB, plus `data\` created at runtime)

---

## 1. What this build is

An unpacked electron-builder output (`--win dir`, no NSIS installer, no registry
writes, no admin rights) wrapped in two `.bat` launchers that redirect every
writable path into the portable folder via environment variables. The folder is
self-contained and relocatable; nothing outside it is touched when launched
through the launchers.

| Component | How it was produced |
|---|---|
| Electron app (win-unpacked) | `npx electron-builder --win dir` from `apps/shell` |
| Modules (docs/sheets/slides/pdf/markdown/html/search) | `npm run build:all` |
| CLI (`resources/cli/genoffice.cjs`) + jsdom | `npm run build:all` |
| Rust XLSX sidecar (`resources/native/xlsx-sidecar.exe`, 9 MB) | `cargo build --release` for host MSVC triple, `crt-static` |
| OCR helper (`resources/ocr/win-ocr.exe`) | `node packages/pdf2docx/ocr-helper/build-win.mjs` |
| Third-party notices (`THIRD-PARTY-NOTICES.txt`, 1.4 MB) | `npm run notices` (570 npm packages + 144 crates) |
| Launchers | Written by this build (`tools/build-portable.ps1`) |

Source tree used for the build: `D:\Portables\GenOffice-Source` (kept separate
from the distribution; `D:\Portables` unrelated files untouched).

---

## 2. Patches to upstream (3 files, all minimal)

`git diff HEAD` in the source tree is exactly these three changes — nothing else
was modified (`package-lock.json` changes from `npm install` were reverted; they
were only stripped `peer: true` markers, no dependency changes).

### 2.1 `apps/shell/src/main/index.ts` — honor `GENOFFICE_USER_DATA` when packaged

Upstream honored the env override only in dev (`!app.isPackaged`). The override
is now applied whether or not the app is packaged, and the legacy
"AI Office" → GenOffice profile migration is skipped when
`GENOFFICE_USER_DATA` is set (a portable profile must never import AppData
state). Dev fallback behavior when the variable is unset is unchanged.

### 2.2 `packages/ai-search/src/gsk.ts:80` — honor `GENOFFICE_AUTH_DIR` in the Electron-compat shim

The shim file was written to `~/.genoffice/bin` regardless of
`GENOFFICE_AUTH_DIR`. It now prefers `GENOFFICE_AUTH_DIR`, so the CLI/GSK
compat helper lands in `data\auth\bin` on portable runs.

### 2.3 `apps/shell/electron-builder.cjs` — `GENOFFICE_WIN_SIDECAR` override

Upstream packaging requires the `x86_64-pc-windows-gnu` (MinGW) cross target
for the sidecar path. On a host without that toolchain, the sidecar was built
for the host MSVC triple instead; the env override points packaging at that
binary. Without the variable, upstream behavior is unchanged.

**No Electron security settings were weakened.** Auto-update stays disabled:
no update feed is baked in and `resources/app-update.yml` is absent from the
packaged output (verified by the build script, which fails if it appears).

---

## 3. Portable redirection mechanism

Both launchers set, relative to their own location (`%~dp0`, no absolute paths):

| Variable | Points at | Redirects |
|---|---|---|
| `GENOFFICE_USER_DATA` | `data\user` | Electron `userData`: `app-settings.json`, `file-index.db`, projects, autosaves, Chromium caches/profiles, single-instance lock |
| `GENOFFICE_AUTH_DIR` | `data\auth` | `auth.json` (AI keys/sign-in), CLI launcher marker, CLI audit log, GSK electron-compat shim |
| `TMP` / `TEMP` | `data\temp` | `os.tmpdir()` use by app, CLI and sidecar |

`GENOFFICE_USER_DATA` is honored in the packaged app thanks to patch 2.1 — this
is the one behavior difference from a stock upstream install, which writes to
`%APPDATA%\GenOffice`.

> Note: launching `app\GenOffice.exe` **directly** (bypassing the launchers)
> leaves the env unset and the app falls back to the normal
> `%APPDATA%\GenOffice` + `%USERPROFILE%\.genoffice` locations. Always start
> through `GenOffice-Portable.bat` / `GenOffice-CLI.bat`.

---

## 4. Reproducing this build

From a clean checkout of upstream @ `1f306a2a`, with the three patches applied
(they are already present in `D:\Portables\GenOffice-Source`):

```powershell
# Prerequisites: Node.js 24 (npm 11 used), Rust stable (MSVC), Windows 10/11 SDK (for win-ocr)
cd D:\Portables\GenOffice-Source
.\tools\build-portable.ps1                 # full build -> ..\GenOffice-Portable
.\tools\build-portable.ps1 -SkipInstall -SmokeTest   # rebuild + GUI smoke test
```

The script runs, in order: `npm install` → `npm run notices` → `npm run build:all`
→ win-ocr build → `cargo` sidecar check → `electron-builder --win dir` (with
`GENOFFICE_WIN_SIDECAR` set) → assembles `app\` + launchers into the output
dir → optional `tools\portable-smoke.mjs`. It fails fast with a diagnostic on
any broken step and never touches files in the output dir other than `app\`,
the two `.bat` files, and (created on first run) `data\`.

Versions used for this build: Node.js v24.12.0, npm 11.12.1, Rust host MSVC
toolchain, electron-builder from the repo's devDependencies.

---

## 5. Tests performed

### 5.1 CLI (via `GenOffice-CLI.bat`, portable env)

| Test | Result |
|---|---|
| `--version` | PASS — `genoffice 0.11.0` |
| `create --type docx` from Markdown, read back | PASS — 8 content blocks round-tripped |
| `create --type xlsx` with formulas, read back | PASS — computed values (5/12/17) and formulas preserved → **Rust sidecar works** |
| `create --type pptx` via `--ops`, read back | PASS — 2 slides |
| `create` PDF (headless export) | PASS |
| `convert` PDF → DOCX (PDFium) | PASS |
| `--help` for subcommands (e.g. `search`) | PASS |

### 5.2 GUI smoke test (`tools\portable-smoke.mjs`, packaged exe) — 13/13 PASS

Launched the packaged `GenOffice.exe` with the same portable env as the
launchers, against a scratch `data\smoke-test` profile:

- app launches from packaged exe; home window renders
- **DOCX**: opens in Docs tab (WebContentsView), typing lands in the
  TipTap/ProseMirror editor, save via `menu:command` writes a valid 3920-byte
  DOCX, app restart + reopen shows the saved marker text (persistence PASS)
- **XLSX** opens in Sheets tab (real CLI-built workbook with formulas)
- **PPTX** opens in Slides tab
- **PDF** opens in PDF tab
- **Markdown** opens in Markdown tab
- `app-settings.json` persists inside the portable `data\user`
- **zero leakage**: no `%APPDATA%\GenOffice`, no `%USERPROFILE%\.genoffice`
  created during the run

### 5.3 Portability / relocation

| Test | Result |
|---|---|
| Copy whole folder to a new path (`D:\Portables\GenOffice-Relocated-Test`) | PASS — CLI `--version` and `create docx` work from the copy |
| GUI launch from relocated copy | PASS — 4 processes all running from the relocated `app\`, own `data\user\app-settings.json` created |
| GUI renders from relocated copy | PASS |
| Launcher diagnostics (missing exe / asar) | PASS — clear error text, non-zero exit |

### 5.4 Data isolation

| Check | Result |
|---|---|
| `file-index.db`, `app-settings.json`, caches, `projects\`, `mcp-log.txt` all under `data\user` | PASS |
| `data\auth`, `data\temp` created and used | PASS |
| No writes to `%APPDATA%\GenOffice` via launchers | PASS |
| No writes to `%USERPROFILE%\.genoffice` via launchers | PASS |

---

## 6. Tests NOT performed (explicitly out of scope of this build session)

- **Real AI provider calls** — no API keys are embedded anywhere; AI chat /
  AI document commands were not exercised end-to-end. The settings UI that
  accepts keys renders correctly.
- **Sign-in / OAuth flows** — not exercised (would require real accounts).
- **MCP server with a live agent client** — `GenOffice-CLI.bat mcp` exists in
  the CLI bundle; not connected to Claude/Cursor during testing.
- **PDF editing/conversion from the GUI** — the PDF tab opens a real PDF;
  interactive editing and GUI conversion dialogs were not driven.
- **OCR (`win-ocr.exe`)** — built successfully; not driven end-to-end.
- **Local file-index search from the GUI** — `file-index.db` is created and
  grows in the portable profile; the search UI itself was not exercised.
- **Collaboration/sync, plugins, font downloads, detached editor windows** —
  not exercised.
- **Auto-update** — intentionally disabled; not tested (no feed packaged).
- **ARM64 Windows** — build is x64 only.
- **Execution from USB/network share, Windows-on-ARM, Server Core, Windows
  10 LTSC** — only tested on local NTFS on Windows 11-class x64.
- **SmartScreen / antivirus acceptance** — binaries are unsigned; no clean-VM
  reputation testing was done.
- **Two copies running simultaneously** — not tested (each copy has its own
  lock inside its own `data\user`, so it should work, but unverified).
- **Upstream's own e2e suite** — not run against the portable tree.

---

## 7. Known limitations

1. **Unsigned binaries** (`GenOffice.exe`, `xlsx-sidecar.exe`, `win-ocr.exe`).
   SmartScreen may warn on first run on fresh systems.
2. **`auth.json` is plain text** in `data\auth\` — same storage model as
   upstream (`~/.genoffice/auth.json`); not DPAPI-encrypted.
3. **No auto-update** by design; update by rebuilding or swapping `app\`
   while keeping `data\`.
4. **Direct exe launch is not portable** — always use the `.bat` launchers so
   the redirect env vars are set (see §3).
5. **First run creates ~hundreds of MB of Chromium cache** under
   `data\user\` (normal Electron behavior, contained in the folder).
6. **`win-ocr.exe` needs the Windows SDK at build time only**; no extra
   runtime prerequisites on target machines.

---

## 8. Deliverables checklist

| Item | Status |
|---|---|
| `D:\Portables\GenOffice-Portable\app\` | DONE — full unpacked app, version 0.11.0 |
| `GenOffice-Portable.bat` (GUI, `%~dp0`, diagnostics) | DONE — tested |
| `GenOffice-CLI.bat` (CLI on bundled runtime) | DONE — tested |
| `README-PORTABLE.txt` | DONE |
| `BUILD-REPORT.md` (this file) | DONE |
| Reproducible build script | DONE — `D:\Portables\GenOffice-Source\tools\build-portable.ps1` |
| GUI smoke test | DONE — `D:\Portables\GenOffice-Source\tools\portable-smoke.mjs` (13/13) |
| No real API keys anywhere | VERIFIED |
| Electron security untouched | VERIFIED — no security-related diff |
| `D:\Portables` unrelated files untouched | VERIFIED |

*(Optional ZIP was not created; the distribution is the folder itself. Say the
word if you want `GenOffice-Portable-0.11.0.zip` packed.)*
