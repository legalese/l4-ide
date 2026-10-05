import type { PermissionPolicy } from './ports.js'

/**
 * Per-category permission gate for client-side tools.
 *
 * Phase 1 plan called for braver defaults than a typical "ask for
 * everything" posture: the user invoked the AI to do work, so gating
 * every file read with a confirmation is friction theater. Only
 * operations with serious blast radius default to Ask — today that's
 * `fs.delete` and any newly-added third-party MCP server.
 *
 * Where values are stored is the host's business (the
 * {@link PermissionPolicy} port): the VS Code adapter persists them in
 * settings under `legaleseAi.permissions.*`, the cloud runner uses a
 * fixed policy. This module holds the categories, their defaults and
 * the tool → category mapping.
 */
export type PermissionValue = 'never' | 'ask' | 'always'

export type PermissionCategory =
  | 'fs.read'
  | 'fs.create'
  | 'fs.edit'
  | 'fs.delete'
  | 'l4.evaluate'
  | 'l4.refactor'
  | 'mcp.l4Rules'
  | 'mcp.vscode'
  | 'meta.askUser'
  | 'meta.statusUpdate'

/** Every category, in settings-UI order. */
export const PERMISSION_CATEGORIES: readonly PermissionCategory[] = [
  'fs.read',
  'fs.create',
  'fs.edit',
  'fs.delete',
  'l4.evaluate',
  'l4.refactor',
  'mcp.l4Rules',
  'mcp.vscode',
  'meta.askUser',
  'meta.statusUpdate',
]

export const DEFAULT_PERMISSIONS: Readonly<
  Record<PermissionCategory, PermissionValue>
> = {
  'fs.read': 'always',
  'fs.create': 'always',
  'fs.edit': 'always',
  // Destructive. Always confirm unless the user explicitly opts out.
  'fs.delete': 'ask',
  'l4.evaluate': 'always',
  // Refactors write to multiple files (the target + every importer
  // for cross-file actions like rename). Cross-file blast radius
  // deserves the same default treatment as fs.edit — runs without
  // prompting, but the user can flip it to `ask` in settings if they
  // want a confirmation per refactor.
  'l4.refactor': 'always',
  'mcp.l4Rules': 'always',
  // Which MCP servers/tools the model can reach is governed by the
  // per-server and per-tool toggles in the sidebar's MCP section, so
  // calls to what survived those toggles run unattended. The category
  // still exists (settable to ask/never via VS Code settings) for
  // users who want call-time confirmation on top.
  'mcp.vscode': 'always',
  // `meta__ask_user` has no side effects — it IS the user prompt.
  'meta.askUser': 'always',
  // `meta__post_status_update` only writes a line of prose into the
  // assistant bubble. Always allowed; never prompt.
  'meta.statusUpdate': 'always',
}

/** Parse a stored permission value; `null` when it isn't one. */
export function parsePermissionValue(raw: unknown): PermissionValue | null {
  if (typeof raw !== 'string') return null
  const v = raw.toLowerCase()
  return v === 'never' || v === 'ask' || v === 'always' ? v : null
}

/**
 * Categorize a tool call into a permission bucket. Tools live under
 * `<category>__<name>` (with `__` as the separator) so prefix-routing
 * gives us the right category for free.
 */
export function categoryForTool(toolName: string): PermissionCategory | null {
  if (toolName === 'fs__read_file') return 'fs.read'
  if (toolName === 'fs__create_file') return 'fs.create'
  if (toolName === 'fs__edit_file') return 'fs.edit'
  if (toolName === 'fs__delete_file') return 'fs.delete'
  if (toolName === 'l4__evaluate') return 'l4.evaluate'
  if (toolName === 'l4__refactor') return 'l4.refactor'
  if (toolName === 'meta__ask_user') return 'meta.askUser'
  if (toolName === 'meta__post_status_update') return 'meta.statusUpdate'
  if (toolName.startsWith('l4-rules__')) return 'mcp.l4Rules'
  if (toolName.startsWith('vsmcp__')) return 'mcp.vscode'
  return null
}

/** A policy with fixed values, falling back to the defaults. The cloud
 *  runner uses one; tests use it with overrides. */
export function fixedPermissionPolicy(
  overrides: Partial<Record<PermissionCategory, PermissionValue>> = {}
): PermissionPolicy {
  return {
    getPermission: (category) =>
      overrides[category] ?? DEFAULT_PERMISSIONS[category],
  }
}
