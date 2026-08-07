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
