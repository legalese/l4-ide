import type { DirectiveResultRow } from './ports.js'
import type { EditSequence } from './tools/fs.js'
import {
  describeFileState,
  FILE_LEVEL,
  isWorse,
  madeProgress,
  type L4FileState,
} from './tools/lsp.js'

/**
 * Edits in a row that may leave a file broken with no progress before the
 * turn is stopped from editing it. Long fix loops mostly pay off (two
 * thirds of those that reached 5 or 10 broken edits still ended clean, and
 * 5 of 9 that reached 15), so this is a brake on the hopeless ones, not on
 * persistence.
 */
export const MAX_BROKEN_EDITS = 15

/** A file as the language server sees it at one moment. */
export interface FileSnapshot {
  state: L4FileState | null
  /** Directive rows with a pass/fail result. */
  checks: Pick<DirectiveResultRow, 'body' | 'success'>[]
}

interface TrackedFile {
  uri: string
  relative: string
  baseline: FileSnapshot
  /** Best state since the file last made progress. */
  best: L4FileState | null
  brokenEdits: number
}

interface TurnRecord {
  files: Map<string, TrackedFile>
  sequences: Map<string, EditSequence>
  nudged: boolean
  /** Compile errors per file before the turn's first edit. */
  errorsBefore?: Map<string, number>
}

/** A file the turn didn't edit but left with more errors. */
export interface KnockOnFile {
  relative: string
  errors: number
}

/** First line of the status appended to a reply. */
export const TURN_STATUS_HEADING =
  'File status from the language server (not a review of the rules):'

/** The status lines in a reply, if it ended with some. */
export function turnStatusLines(reply: string | undefined): string[] {
  if (!reply) return []
  const at = reply.lastIndexOf(TURN_STATUS_HEADING)
  if (at < 0) return []
  return reply
    .slice(at + TURN_STATUS_HEADING.length)
    .split('\n')
    .map((line) => line.replace(/^- /, '').trim())
    .filter(Boolean)
}

/** Snapshot of a file that doesn't exist yet. */
export const NEW_FILE: FileSnapshot = {
  state: {
    level: FILE_LEVEL.clean,
    errors: 0,
    warnings: 0,
    pending: false,
  },
  checks: [],
}

/**
 * What a turn has done to its L4 files: how they compared to where they
 * started, whether the edits of one model response are still safe to run,
 * and whether a fix loop has stopped getting anywhere. Works only from the
 * language server's states, so it needs no knowledge of L4.
 */
export class EditGuard {
  private readonly turns = new Map<string, TurnRecord>()

  private turn(turnId: string): TurnRecord {
    let t = this.turns.get(turnId)
    if (!t) {
      t = { files: new Map(), sequences: new Map(), nudged: false }
      this.turns.set(turnId, t)
    }
    return t
  }

  /**
   * Start a model response. Edits sent as separate calls to one file run
   * as one sequence, so splitting them can't get past the per-file cap or
   * carry on after a mistake. `uris` has one entry per edit call.
   */
  beginRound(turnId: string, uris: string[]): void {
    const t = this.turn(turnId)
    t.sequences.clear()
    const seen = new Set<string>()
    for (const uri of uris) {
      if (seen.has(uri)) t.sequences.set(uri, { applied: 0 })
      seen.add(uri)
    }
  }

  sequenceFor(turnId: string, uri: string): EditSequence | undefined {
    return this.turns.get(turnId)?.sequences.get(uri)
  }

  isTracked(turnId: string, uri: string): boolean {
    return this.turns.get(turnId)?.files.has(uri) ?? false
  }

  track(
    turnId: string,
    uri: string,
    relative: string,
    baseline: FileSnapshot
  ): void {
    const t = this.turn(turnId)
    if (t.files.has(uri)) return
    t.files.set(uri, {
      uri,
      relative,
      baseline,
      best: baseline.state,
      brokenEdits: 0,
    })
  }

  /** Note where every file stood, once, before the turn's first edit. */
  noteErrorsBefore(
    turnId: string,
    counts: Map<string, number> | undefined
  ): void {
    const t = this.turn(turnId)
    if (counts && !t.errorsBefore) t.errorsBefore = counts
  }

  /** Files the turn didn't edit that now have more errors than before it:
   *  usually importers of something it changed. */
  knockOnFiles(
    turnId: string,
    now: Map<string, number> | undefined,
    relativeOf: (uri: string) => string
  ): KnockOnFile[] {
    const t = this.turns.get(turnId)
    if (!t?.errorsBefore || !now) return []
    const out: KnockOnFile[] = []
    for (const [uri, errors] of now) {
      if (t.files.has(uri)) continue
      // Not checked before the turn: its errors can't be pinned on it.
      const before = t.errorsBefore.get(uri)
      if (before !== undefined && errors > before) {
        out.push({ relative: relativeOf(uri), errors })
      }
    }
    return out
  }

  /** Why this turn may not edit the file any more, if it may not. */
  blocked(turnId: string, uri: string): string | null {
    const f = this.turns.get(turnId)?.files.get(uri)
    if (!f || f.brokenEdits < MAX_BROKEN_EDITS) return null
    return `${f.relative} has had ${f.brokenEdits} edits in a row without getting closer to compiling, so no more edits to it were applied. Stop and tell the user what is still wrong and what you tried.`
  }

  /** Note the state after `applied` edits to a tracked file. A streak counts
   *  from its best state so far, so it only runs out when nothing helps. */
  recordState(
    turnId: string,
    uri: string,
    state: L4FileState,
    applied = 1
  ): void {
    const f = this.turns.get(turnId)?.files.get(uri)
    if (!f) return
    if (state.level >= FILE_LEVEL.failedChecks) {
      // It compiles. A failed check is for the user to judge, and must not
      // put pressure on the model, so ordinary work goes on.
      f.brokenEdits = 0
      f.best = state
    } else if (!f.best || f.best.level >= FILE_LEVEL.failedChecks) {
      // A new streak: measure progress from where it starts, not from a
      // compiling file nothing can be better than.
      f.brokenEdits = applied
      f.best = state
    } else if (madeProgress(f.best, state)) {
      f.brokenEdits = 0
      f.best = state
    } else {
      f.brokenEdits += applied
    }
  }

  trackedFiles(turnId: string): { uri: string; relative: string }[] {
    return [...(this.turns.get(turnId)?.files.values() ?? [])]
  }

  /**
   * The nudge to send when a turn would end with compile errors it
   * introduced, or null. At most once per turn. Failed checks don't count:
   * pushing a model to turn those green invites it to weaken them, so they
   * go in the status line for the user to judge. Nor do errors that were
   * already there, or a file the breaker already gave up on.
   */
  stopNudge(
    turnId: string,
    current: Map<string, FileSnapshot | null>,
    knockOn: KnockOnFile[] = []
  ): string | null {
    const t = this.turns.get(turnId)
    if (!t || t.nudged) return null
    const broken: string[] = []
    for (const f of t.files.values()) {
      const now = current.get(f.uri)?.state
      if (!now || now.pending || now.level >= FILE_LEVEL.failedChecks) continue
      if (f.brokenEdits >= MAX_BROKEN_EDITS) continue
      if (!f.baseline.state || !isWorse(f.baseline.state, now)) continue
      broken.push(`${f.relative} ${describeFileState(now)}`)
    }
    for (const f of knockOn) {
      broken.push(
        `${f.relative}, which this turn didn't edit, now has ${errorCount(f.errors)}`
      )
    }
    if (broken.length === 0) return null
    t.nudged = true
    return `Automatic check, not a message from the user: ${broken.join('; ')}, and this turn introduced that. Fix it if you can. If you can't, stop and say plainly what is still wrong. Do not delete code or tests just to clear an error.`
  }

  /**
   * A status line per tracked file, and forget them. Written by the
   * harness from the language server's results, so it can't overstate
   * what was done. It says what compiled and what passed, and never that
   * the rules are right: the model wrote those checks too, which is why
   * checks changed during the turn are called out.
   */
  takeStatus(
    turnId: string,
    current: Map<string, FileSnapshot | null>,
    knockOn: KnockOnFile[] = []
  ): string | null {
    const t = this.turns.get(turnId)
    if (!t || t.files.size === 0) return null
    const lines: string[] = []
    for (const f of t.files.values()) {
      const now = current.get(f.uri)
      if (!now) continue
      lines.push(`- \`${f.relative}\`: ${statusOf(f, now)}`)
    }
    for (const f of knockOn) {
      lines.push(
        `- \`${f.relative}\`: not edited, but now has ${errorCount(f.errors)}`
      )
    }
    t.files.clear()
    if (lines.length === 0) return null
    return `\n\n---\n${TURN_STATUS_HEADING}\n${lines.join('\n')}`
  }

  endTurn(turnId: string): void {
    this.turns.delete(turnId)
  }
}

function errorCount(n: number): string {
  return `${n} error${n === 1 ? '' : 's'}`
}

function statusOf(f: TrackedFile, now: FileSnapshot): string {
  const state = now.state
  if (!state) return 'status unknown'
  if (state.pending) return 'the check did not finish, so this is unknown'
  const parts = [describeFileState(state)]
  // Directive results are frozen at the last good compile, so they only
  // mean anything once the file compiles again.
  if (state.level >= FILE_LEVEL.failedChecks) {
    const total = now.checks.length
    if (total > 0) {
      const passed = now.checks.filter((c) => c.success === true).length
      parts.push(`${passed} of ${total} checks pass`)
    }
    const after = new Set(now.checks.map((c) => c.body))
    const changed = f.baseline.checks.filter((c) => !after.has(c.body)).length
    if (changed > 0) {
      parts.push(
        `${changed} check${changed === 1 ? '' : 's'} changed or removed this turn`
      )
    }
  }
  if (state.warnings > 0) {
    parts.push(`${state.warnings} warning${state.warnings === 1 ? '' : 's'}`)
  }
  return parts.join('; ')
}
