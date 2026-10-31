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
  // Its main category (for "always allow"); what a call needs depends on
  // its arguments, see categoriesForCall.
  if (toolName === 'fs__copy_file') return 'fs.edit'
  if (toolName === 'l4__evaluate') return 'l4.evaluate'
  if (toolName === 'l4__refactor') return 'l4.refactor'
  if (toolName === 'meta__ask_user') return 'meta.askUser'
  if (toolName === 'meta__post_status_update') return 'meta.statusUpdate'
  if (toolName.startsWith('l4-rules__')) return 'mcp.l4Rules'
  if (toolName.startsWith('vsmcp__')) return 'mcp.vscode'
  return null
}

/**
 * Every category a call needs, from its arguments: a copy creates its
 * target, replaces it with `overwrite` (an edit), and deletes its
 * source with `deleteSource` (a move); a create with `content` also
 * writes text. Read as the tool reads them (truthy), so a call can't do
 * more than it was checked for.
 */
export function categoriesForCall(
  toolName: string,
  args: unknown
): PermissionCategory[] {
  if (toolName === 'fs__copy_file') {
    const a = (args && typeof args === 'object' ? args : {}) as {
      overwrite?: unknown
      deleteSource?: unknown
    }
    return [
      'fs.create',
      ...(a.overwrite ? (['fs.edit'] as const) : []),
      ...(a.deleteSource ? (['fs.delete'] as const) : []),
    ]
  }
  // Without content, create only makes a stub and the text arrives through
  // fs__edit_file. With it, the one call also does that edit, so it can't
  // get past a user who set fs.edit to `ask`.
  if (toolName === 'fs__create_file') {
    const content = (args as { content?: unknown } | null)?.content
    return typeof content === 'string' && content.length > 0
      ? ['fs.create', 'fs.edit']
      : ['fs.create']
  }
  const category = categoryForTool(toolName)
  return category ? [category] : []
}

/** Directories whose files configure the editor, git or another agent. */
const SENSITIVE_DIRS: ReadonlySet<string> = new Set([
  '.git',
  '.vscode',
  '.claude',
  '.cursor',
  '.husky',
  '.devcontainer',
])

/** Single files that do the same. */
const SENSITIVE_FILES: ReadonlySet<string> = new Set([
  '.devcontainer.json',
  '.mcp.json',
  '.envrc',
  '.gitmodules',
  '.gitconfig',
])

/**
 * Whether writing to `p` could change what the editor, git or an agent
 * does, instead of just changing the user's documents. A prompt-injected
 * model could use such a file to lift its own limits or run code later, so
 * hosts ask before writing one whatever the category settings say. Matched
 * case-insensitively, because macOS and Windows file systems are.
 */
export function isSensitivePath(p: string): boolean {
  const parts = p.replace(/\\/g, '/').toLowerCase().split('/').filter(Boolean)
  const name = parts[parts.length - 1] ?? ''
  if (SENSITIVE_FILES.has(name) || name.endsWith('.code-workspace')) return true
  return parts.some(
    (part, i) =>
      SENSITIVE_DIRS.has(part) ||
      (part === '.github' && parts[i + 1] === 'workflows')
  )
}

const STRICTNESS: Record<PermissionValue, number> = {
  always: 0,
  ask: 1,
  never: 2,
}

/**
 * The value that applies when settings live at several levels: the user's
 * own value or the default, tightened by any level above it. A workspace
 * may restrict what the agent does there, as a team might, but never relax
 * it: a repo, or a prompt-injected model writing `.vscode/settings.json`,
 * must not be able to switch approvals off.
 */
export function effectivePermission(
  user: unknown,
  fallback: PermissionValue,
  ...workspaceLevels: unknown[]
): PermissionValue {
  let value = parsePermissionValue(user) ?? fallback
  for (const level of workspaceLevels) {
    const tighter = parsePermissionValue(level)
    if (tighter && STRICTNESS[tighter] > STRICTNESS[value]) value = tighter
  }
  return value
}

/** The strictest permission among `categories`, with the category it
 *  comes from (the first, on a tie). */
export function strictestPermission(
  policy: PermissionPolicy,
  categories: readonly PermissionCategory[]
): { category: PermissionCategory; permission: PermissionValue } | null {
  let worst: {
    category: PermissionCategory
    permission: PermissionValue
  } | null = null
  for (const category of categories) {
    const permission = policy.getPermission(category)
    if (!worst || STRICTNESS[permission] > STRICTNESS[worst.permission]) {
      worst = { category, permission }
    }
  }
  return worst
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
