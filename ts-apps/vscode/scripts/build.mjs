import esbuild from 'esbuild'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

/*
The previous esbuild package.json script that
this is meant to extend
(setting aside the ts vs mts difference):

    "esbuild-base": "esbuild ./src/extension.ts --bundle --minify --outfile=out/extension.js --external:vscode --format=cjs --platform=node",
*/

// Copy the writing-l4-rules skill into static/ so it ships inside the .vsix
// and the extension can install it into ~/.claude/skills/ on demand.
const __dirname = path.dirname(fileURLToPath(import.meta.url))
const extensionRoot = path.resolve(__dirname, '..')
const repoRoot = path.resolve(extensionRoot, '..', '..')
// The skill's real home is the plugin's Agent Plugins location, `skills/` at
// the repo root. `.claude/skills/` is only a symlink to it (so the skill still
// auto-loads for anyone working in this repo), and symlinks don't survive
// every checkout — read through the real path, not the link.
const skillSrc = path.join(repoRoot, 'skills', 'writing-l4-rules')
const skillDest = path.join(
  extensionRoot,
  'static',
  'skills',
  'writing-l4-rules'
)
if (fs.existsSync(skillSrc)) {
  fs.rmSync(skillDest, { recursive: true, force: true })
  fs.mkdirSync(path.dirname(skillDest), { recursive: true })
  fs.cpSync(skillSrc, skillDest, { recursive: true })
  console.log(`Bundled writing-l4-rules skill from ${skillSrc}`)
} else {
  console.warn(
    `writing-l4-rules skill not found at ${skillSrc} — extension will not bundle it`
  )
}

// Vendor the PvRecorder native audio module into static/ so chat
// dictation can record the microphone (see src/ai/dictation.ts). The
// package locates its prebuilt binary relative to its own folder, so it
// is copied whole and loaded by path at runtime — never bundled. All
// platforms' binaries ship in every .vsix (a few MB); the extension
// only offers dictation where one matches.
const pvrecorderSrc = path.dirname(
  fileURLToPath(import.meta.resolve('@picovoice/pvrecorder-node/package.json'))
)
const pvrecorderDest = path.join(extensionRoot, 'static', 'pvrecorder')
fs.rmSync(pvrecorderDest, { recursive: true, force: true })
fs.mkdirSync(pvrecorderDest, { recursive: true })
fs.cpSync(
  path.join(pvrecorderSrc, 'package.json'),
  path.join(pvrecorderDest, 'package.json')
)
fs.cpSync(path.join(pvrecorderSrc, 'lib'), path.join(pvrecorderDest, 'lib'), {
  recursive: true,
  // Raspberry Pi builds target specific CPUs VSCode doesn't ship for.
  filter: (src) => !src.includes('raspberry-pi'),
})
fs.cpSync(path.join(pvrecorderSrc, 'dist'), path.join(pvrecorderDest, 'dist'), {
  recursive: true,
  filter: (src) => !src.endsWith('.map') && !src.endsWith('.d.ts'),
})
fs.writeFileSync(
  path.join(pvrecorderDest, 'NOTICE'),
  'PvRecorder (@picovoice/pvrecorder-node) — Copyright Picovoice Inc.\n' +
    'Licensed under the Apache License, Version 2.0; see the LICENSE file\n' +
    'at the root of this extension for the license text.\n' +
    'https://github.com/Picovoice/pvrecorder\n'
)
console.log(`Bundled PvRecorder from ${pvrecorderSrc}`)

// The dictation capture loop runs in a worker thread, so it needs to be
// a script of its own next to extension.js.
esbuild
  .build({
    entryPoints: ['./src/ai/dictation-worker.ts'],
    bundle: true,
    minify: true,
    sourcemap: true,
    platform: 'node',
    target: 'es2020',
    format: 'cjs',
    outfile: 'out/dictation-worker.js',
  })
  .catch(() => process.exit(1))

esbuild
  .build({
    entryPoints: ['./src/extension.mts'],
    bundle: true,
    minify: true,
    sourcemap: true,
    platform: 'node',
    target: 'es2020', // to match the target in tsconfig.json
    external: ['vscode'],
    format: 'cjs',
    outfile: 'out/extension.js',
    loader: {
      '.html': 'text',
      // Load .html files as text.
      // Required for the html loading in the webview part of webview-panel.ts
    },
  })
  .then(() => {
    console.log('Esbuild-bundling of VSCode extension succeeded!')
  })
  .catch(() => process.exit(1))
