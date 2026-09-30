import type { L4Language, Workspace } from '../ports.js'
import {
  createDirectiveSnapshotStore,
  type DirectiveSnapshotStore,
} from './directive-snapshot.js'
import {
  fsCreateFile,
  fsDeleteFile,
  fsEditFile,
  fsReadFile,
  resolveCurrentContents,
  resolveFileUri,
  type FsCreateArgs,
  type FsDeleteArgs,
  type FsEditArgs,
  type FsReadArgs,
} from './fs.js'
import { l4Evaluate, type L4EvaluateArgs } from './l4-evaluate.js'
import { l4Refactor, type L4RefactorArgs } from './refactor.js'

/** The two directive snapshot stores behind one model's diffs. */
export interface DirectiveSnapshotStores {
  /** `l4__evaluate`'s "what changed since the last evaluate". */
  evaluateStore: DirectiveSnapshotStore
  /** `fs__edit_file`'s "what changed since the last edit". */
  editStore: DirectiveSnapshotStore
}

/** Which conversation a tool call belongs to (from the dispatcher's
 *  `ToolCallContext`). Absent for callers without one. */
export interface ToolSessionContext {
  conversationId?: string
}

/** Conversations whose snapshots are kept; the least recently used
 *  beyond this are dropped (their next call reports everything again). */
export const MAX_SNAPSHOT_CONVERSATIONS = 200

function createStores(): DirectiveSnapshotStores {
  return {
    evaluateStore: createDirectiveSnapshotStore(),
    editStore: createDirectiveSnapshotStore(),
  }
}

/**
 * The built-in fs and L4 tools, bound to one session's workspace and
 * language server.
 *
 * Directive snapshot stores (one for `l4__evaluate`, one for
 * `fs__edit_file`) are keyed by conversation as well as by file, so each
 * conversation's model gets diffs relative to what IT was last told.
 * Calls without a conversation (the rename command, the `l4_evaluate`
 * LM tool, the `@legalese` participant) use this instance's own
 * per-consumer stores. (They all used to share module-level singletons.)
 */
export class BuiltinTools {
  /** Stores for calls without a conversation. */
  readonly evaluateStore: DirectiveSnapshotStore
  readonly editStore: DirectiveSnapshotStore
  private readonly byConversation = new Map<string, DirectiveSnapshotStores>()

  constructor(
    readonly workspace: Workspace,
    readonly l4: L4Language
  ) {
    const own = createStores()
    this.evaluateStore = own.evaluateStore
    this.editStore = own.editStore
  }

  /** The snapshot stores for a conversation (or this instance's own). */
  storesFor(conversationId?: string): DirectiveSnapshotStores {
    if (!conversationId) {
      return { evaluateStore: this.evaluateStore, editStore: this.editStore }
    }
    let stores = this.byConversation.get(conversationId)
    if (stores) {
      // Refresh recency.
      this.byConversation.delete(conversationId)
    } else {
      stores = createStores()
    }
    this.byConversation.set(conversationId, stores)
    while (this.byConversation.size > MAX_SNAPSHOT_CONVERSATIONS) {
      const oldest = this.byConversation.keys().next().value as string
      this.byConversation.delete(oldest)
    }
    return stores
  }

  private withStores(
    ctx: ToolSessionContext | undefined
  ): { workspace: Workspace; l4: L4Language } & DirectiveSnapshotStores {
    return {
      workspace: this.workspace,
      l4: this.l4,
      ...this.storesFor(ctx?.conversationId),
    }
  }

  readFile(args: FsReadArgs): Promise<string> {
    return fsReadFile(this, args)
  }

  createFile(args: FsCreateArgs): Promise<string> {
    return fsCreateFile(this, args)
  }

  editFile(args: FsEditArgs, ctx?: ToolSessionContext): Promise<string> {
    return fsEditFile(this.withStores(ctx), args)
  }

  deleteFile(args: FsDeleteArgs): Promise<string> {
    return fsDeleteFile(this, args)
  }

  evaluate(args: L4EvaluateArgs, ctx?: ToolSessionContext): Promise<string> {
    return l4Evaluate(this.withStores(ctx), args)
  }

  refactor(args: L4RefactorArgs): Promise<string> {
    return l4Refactor(this, args)
  }

  /** Workspace URI for a tool-call path, or null. */
  resolveFileUri(p: string): string | null {
    return resolveFileUri(this.workspace, p)
  }

  /** On-disk contents before a write (`''` when absent). */
  currentContents(p: string): Promise<string> {
    return resolveCurrentContents(this.workspace, p)
  }
}
