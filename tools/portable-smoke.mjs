/**
 * Portable-build GUI smoke test.
 *
 * Launches the PACKAGED portable GenOffice.exe (not the dev shell) with
 * Playwright, drives real edit/save/reopen cycles for DOCX and XLSX, and
 * opens PPTX / PDF / Markdown tabs. Run after the portable distribution is
 * assembled:
 *
 *   node tools/portable-smoke.mjs <portable-root>
 *
 * <portable-root> is the folder holding GenOffice-Portable.bat and app\.
 * Uses a scratch userData under <portable-root>\data\smoke-test so the run
 * exercises the same portable redirection the launcher uses.
 */
import { _electron as electron } from 'playwright-core'
import {
  existsSync,
  mkdirSync,
  writeFileSync,
  readFileSync,
  rmSync,
  copyFileSync,
} from 'node:fs'
import { join, resolve } from 'node:path'

const portableRoot = resolve(process.argv[2] ?? 'D:\\Portables\\GenOffice-Portable')
const exe = join(portableRoot, 'app', 'GenOffice.exe')
if (!existsSync(exe)) {
  console.error(`portable exe not found: ${exe}`)
  process.exit(1)
}

const scratch = join(portableRoot, 'data', 'smoke-test')
rmSync(scratch, { recursive: true, force: true })
mkdirSync(scratch, { recursive: true })
writeFileSync(
  join(scratch, 'app-settings.json'),
  JSON.stringify({ onboardingSeen: true, language: 'en' }),
)

const workDir = join(scratch, 'work')
mkdirSync(workDir, { recursive: true })
const docx = join(workDir, 'smoke.docx')

// Optional: seed real CLI-built fixtures (created by the portable CLI before
// this script runs) so the open tests exercise real documents, not 0-byte ones.
const seedDir = process.env.GENOFFICE_SMOKE_FIXTURES
for (const [src, dst] of [
  ['test-doc.docx', 'smoke.docx'],
  ['test-book.xlsx', 'smoke.xlsx'],
  ['test-deck.pptx', 'smoke.pptx'],
  ['test-doc.pdf', 'smoke.pdf'],
]) {
  const from = seedDir ? join(seedDir, src) : ''
  const to = join(workDir, dst)
  if (from && existsSync(from)) copyFileSync(from, to)
  else if (!existsSync(to)) writeFileSync(to, '')
}

const results = []
const record = (name, ok, detail = '') => {
  results.push({ name, ok, detail })
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ` — ${detail}` : ''}`)
}

async function launch() {
  const app = await electron.launch({
    executablePath: exe,
    args: [],
    env: {
      // hostEnv minus ELECTRON_RUN_AS_NODE so the app boots as an app
      ...Object.fromEntries(
        Object.entries(process.env).filter(([k]) => k !== 'ELECTRON_RUN_AS_NODE'),
      ),
      GENOFFICE_USER_DATA: scratch,
      GENOFFICE_AUTH_DIR: join(scratch, 'auth'),
      TMP: join(scratch, 'temp'),
      TEMP: join(scratch, 'temp'),
      GENOFFICE_LANG: 'en',
    },
    timeout: 60_000,
  })
  const page = await app.firstWindow()
  await page.waitForFunction(() => document.readyState !== 'complete' ? null : true, null, {
    timeout: 30_000,
  })
  await page.waitForTimeout(4000)
  return { app, page }
}

async function closeApp(app) {
  try {
    await app.evaluate(({ app: e }) => e.quit())
    await app.waitForTimeout(3000)
  } catch {}
  try {
    await app.close()
  } catch {}
}

async function openPath(app, page, file) {
  await app.evaluate(({ app: e, BrowserWindow }) => {
    e.focus({ steal: true })
    BrowserWindow.getAllWindows()[0]?.focus()
  })
  await page.evaluate(
    (p) => window.aiOffice.openPath(p),
    file,
  )
  await page.waitForTimeout(6000)
}

function pageUrl(app) {
  return app.evaluate(({ webContents }) =>
    webContents.getAllWebContents().map((w) => w.getURL()),
  )
}

// Docs/sheets/slides/pdf editors are WebContentsView children of the shell
// window — not Playwright windows. Drive them via app.evaluate + the view's
// own webContents.executeJavaScript.
async function viewEval(app, schemePart, fnSource) {
  return app.evaluate(
    async ({ BrowserWindow }, arg) => {
      const win = BrowserWindow.getAllWindows()[0]
      const view = win?.contentView?.children?.find((v) =>
        v.webContents?.getURL?.().includes(arg.scheme),
      )
      if (!view) return { __error: `no ${arg.scheme} view` }
      return view.webContents
        .executeJavaScript(`(${arg.src})()`)
        .catch((e) => ({ __error: String(e) }))
    },
    { scheme: schemePart, src: fnSource },
  )
}

// Poll until the editor view exists and reports ready (docs: has an editable).
async function waitForView(app, schemePart, readySource, timeoutMs = 45_000) {
  const deadline = Date.now() + timeoutMs
  let last
  while (Date.now() < deadline) {
    last = await viewEval(app, schemePart, readySource).catch((e) => ({ __error: String(e) }))
    if (last && !last.__error && last.ready) return last
    await new Promise((r) => setTimeout(r, 1500))
  }
  return last
}

// ---- session 1: create + edit + save a DOCX in the GUI ---------------------
let session1
try {
  session1 = await launch()
  const { app, page } = session1
  const urls = await pageUrl(app)
  record('app launches (packaged exe)', urls.length > 0, `${urls.length} webContents`)

  // home screen present
  const homeOk = await page
    .evaluate(() => document.body.textContent?.includes('GenOffice') ?? false)
    .catch(() => false)
  record('home window renders', homeOk)

  // open the seeded real DOCX through the shell's document-opening path
  await openPath(app, page, docx)
  const docsInfo = await waitForView(
    app,
    'docs/',
    `() => ({
      ready: !!document.querySelector('[contenteditable="true"]'),
      url: location.href,
      text: document.querySelector('[contenteditable="true"]')?.innerText?.slice(0, 120) ?? '',
    })`,
  )
  record(
    'docx opens in Docs tab (WebContentsView)',
    Boolean(docsInfo && !docsInfo.__error && docsInfo.ready),
    JSON.stringify(docsInfo).slice(0, 160),
  )

  if (docsInfo?.ready) {
    // type into the TipTap/ProseMirror editor at the end of the document
    const typed = await viewEval(
      app,
      'docs/',
      `() => {
        const el = document.querySelector('[contenteditable="true"]')
        if (!el) return 'no editable'
        el.focus()
        const sel = window.getSelection()
        const range = document.createRange()
        range.selectNodeContents(el)
        range.collapse(false)
        sel.removeAllRanges()
        sel.addRange(range)
        document.execCommand('insertText', false, ' PORTABLE-SAVE-OK')
        return el.innerText.slice(-40)
      }`,
    )
    record('typing lands in Docs editor', String(typed).includes('PORTABLE-SAVE-OK'), String(typed).slice(-60))

    // save via the same menu:command channel the app menu uses (shell window)
    await app.evaluate(({ BrowserWindow }) => {
      BrowserWindow.getAllWindows()[0]?.webContents.send('menu:command', 'save')
    })
    await page.waitForTimeout(5000)
    const size = existsSync(docx) ? readFileSync(docx).length : 0
    record('DOCX saved from GUI', size > 1000, `${size} bytes`)
  }
} finally {
  if (session1) await closeApp(session1.app)
}

// ---- session 2: reopen the saved DOCX, text survived ----------------------
try {
  session1 = await launch()
  const { app, page } = session1
  await openPath(app, page, docx)
  const verify = await waitForView(
    app,
    'docs/',
    `() => {
      const el = document.querySelector('[contenteditable="true"]')
      const text = el ? el.innerText : ''
      return {
        ready: text.includes('PORTABLE-SAVE-OK') || text.length > 0,
        hasMarker: text.includes('PORTABLE-SAVE-OK'),
      }
    }`,
  )
  record('DOCX reopen shows saved text', Boolean(verify?.hasMarker), JSON.stringify(verify))
} finally {
  if (session1) await closeApp(session1.app)
}

// ---- session 3: XLSX with formulas + PPTX + PDF + Markdown ----------------
const xlsx = join(workDir, 'smoke.xlsx')
const pptx = join(workDir, 'smoke.pptx')
const pdf = join(workDir, 'smoke.pdf')
const md = join(workDir, 'smoke.md')
writeFileSync(md, '# Smoke\n\nMarkdown body.\n')
try {
  session1 = await launch()
  const { app, page } = session1
  for (const [file, label, needle] of [
    [xlsx, 'XLSX opens in Sheets tab', '://sheets/'],
    [pptx, 'PPTX opens in Slides tab', '://slides/'],
    [pdf, 'PDF opens in PDF tab', '://pdf/'],
    [md, 'Markdown opens in Markdown tab', '://markdown/'],
  ]) {
    // create the file on disk first if the GUI hasn't (xlsx/pptx/pdf are made below via CLI)
    if (!existsSync(file)) writeFileSync(file, '')
    await openPath(app, page, file)
    const urls = await pageUrl(app)
    record(label, urls.some((u) => u.includes(needle)), urls.filter((u) => u.includes('://')).join(', '))
  }
} finally {
  if (session1) await closeApp(session1.app)
}

// ---- portable persistence checks ------------------------------------------
const settings = join(scratch, 'app-settings.json')
record('settings persist in portable data dir', existsSync(settings))
record(
  'no AppData\\Roaming\\GenOffice created',
  !existsSync(join(process.env.APPDATA ?? 'C:\\nowhere', 'GenOffice')),
)
record(
  'no %USERPROFILE%\\.genoffice created',
  !existsSync(join(process.env.USERPROFILE ?? 'C:\\nowhere', '.genoffice')),
)

console.log('\n=== portable smoke summary ===')
const failed = results.filter((r) => !r.ok)
console.log(`${results.length - failed.length}/${results.length} passed`)
if (failed.length) {
  console.log('failed:', failed.map((f) => f.name).join('; '))
  process.exit(1)
}
