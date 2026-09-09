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
// The skill is an ordinary directory under `.claude/skills/`, beside
// running-the-l4-pipeline. It used to sit at `skills/` — the Agent Plugins
// location — with a symlink here, back when this repo was itself the
// published plugin. The plugin now ships from legalese/l4-plugin, so that
// reason is gone and neither path in this tree is a symlink any more.
const skillSrc = path.join(repoRoot, '.claude', 'skills', 'writing-l4-rules')
const skillDest = path.join(
  extensionRoot,
  'static',
  'skills',
  'writing-l4-rules'
)
// Fail the build rather than warn. This used to warn and carry on, which
// produces a .vsix whose "install the skill" command has no skill to install
// — a defect invisible here and visible only in a user's editor. The path is
// exactly the kind of thing a directory move breaks, so let the move break
// the build instead.
if (!fs.existsSync(skillSrc)) {
  throw new Error(
    `writing-l4-rules skill not found at ${skillSrc}. The extension bundles it ` +
      `into static/, so a missing skill is a build error, not a warning. If the ` +
      `skill moved, update this path.`
  )
}
fs.rmSync(skillDest, { recursive: true, force: true })
fs.mkdirSync(path.dirname(skillDest), { recursive: true })
fs.cpSync(skillSrc, skillDest, { recursive: true })
console.log(`Bundled writing-l4-rules skill from ${skillSrc}`)

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
