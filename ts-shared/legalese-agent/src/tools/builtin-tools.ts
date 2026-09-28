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

/**
 * The built-in fs and L4 tools, bound to one session's workspace and
 * language server.
 *
 * Each instance owns its own directive snapshot stores (one for
 * `l4__evaluate`, one for `fs__edit_file`), so the "what changed since
 * I last reported" diff of one session — the sidebar chat, the
 * `@legalese` participant, the `l4_evaluate` LM tool, a cloud session —
 * is never blinded by another's calls. (They used to be module-level
 * singletons shared by everything in the extension host.)
 */
export class BuiltinTools {
  readonly evaluateStore: DirectiveSnapshotStore =
    createDirectiveSnapshotStore()
  readonly editStore: DirectiveSnapshotStore = createDirectiveSnapshotStore()

  constructor(
    readonly workspace: Workspace,
    readonly l4: L4Language
  ) {}

  readFile(args: FsReadArgs): Promise<string> {
    return fsReadFile(this, args)
  }

  createFile(args: FsCreateArgs): Promise<string> {
    return fsCreateFile(this, args)
  }

  editFile(args: FsEditArgs): Promise<string> {
    return fsEditFile(this, args)
  }

  deleteFile(args: FsDeleteArgs): Promise<string> {
    return fsDeleteFile(this, args)
  }

  evaluate(args: L4EvaluateArgs): Promise<string> {
    return l4Evaluate(this, args)
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
