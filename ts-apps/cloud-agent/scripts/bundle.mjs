// Bundle the harness into one CommonJS file for the cloud-agent image
// (cloud-sessions spec §5.3, §11). Node built-ins stay external; every
// npm dependency (the agent core, vscode-jsonrpc) is inlined, so the
// image needs only `node` and this file.
import esbuild from 'esbuild'

await esbuild.build({
  entryPoints: ['./src/main.ts'],
  bundle: true,
  platform: 'node',
  target: 'node24',
  format: 'cjs',
  outfile: 'dist/cloud-agent.cjs',
  sourcemap: true,
  minify: false,
  banner: { js: '#!/usr/bin/env node' },
  logLevel: 'info',
})
