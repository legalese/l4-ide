/**
 * Sidebar webview ⇄ cloud sessions (spec §12): the `AiCloud*` RPCs,
 * forwarding of cloud-only events, state and start progress, the
 * cached history list, Clone / Sync, and VS Code notifications when a
 * background cloud session asks a question (cloud sessions never ask
 * for tool approval).
 * Notification text is fixed, or plain (notification-text.ts).
 *
 * Chat events of cloud sessions don't pass through here: they take the
 * ordinary `AiChat*` path (see `createCloudSessions`).
 */
import * as vscode from 'vscode'
import type { Messenger } from 'vscode-messenger'
import type { WebviewTypeMessageParticipant } from 'vscode-messenger-common'
import {
  AiCloudCommand,
  AiCloudConfig,
  AiCloudDelete,
  AiCloudEvent,
  AiCloudGitAction,
  AiCloudGitStatusRequest,
  AiCloudMcpSignIn,
  AiCloudMcpSignInNeeded,
  AiCloudOpen,
  AiCloudProgress,
  AiCloudRename,
  AiCloudReveal,
  AiCloudRollback,
  AiCloudRun,
  AiCloudSessionList,
  AiCloudState,
  AiCloudStop,
  AiCloudViewing,
  WebviewFrontendIsReadyNotification,
  cloudConversationId,
  type AiCloudEventPayload,
  type AiCloudGitStatus,
  type AiCloudResult,
  type AiCloudSessionSummary,
} from 'jl4-client-rpc'
import type { Logger } from '@repo/legalese-agent'
import { NotSignedInError, AuthProxyError } from './auth-proxy.js'
import { GitSyncError } from './git-sync.js'
import { SeedLimitError } from './seed.js'
import { SessionsApiError } from './sessions-api.js'
import { mergeConflictMessage } from './notification-text.js'
import {
  CLOUD_SESSIONS_ENABLED_SETTING,
  type CloudSessions,
} from './vscode-cloud.js'

/** The cached history list, per account and organisation (cloud
 *  sessions belong to one organisation; titles mustn't show under
 *  another). The key without a suffix is from before. */
const LIST_CACHE_KEY = 'legaleseAi.cloudSessions.listCache'

/** A user-facing message for anything the cloud path throws. */
export function cloudErrorMessage(err: unknown): string {
  if (
    err instanceof SeedLimitError ||
    err instanceof NotSignedInError ||
    err instanceof AuthProxyError ||
    err instanceof SessionsApiError ||
    err instanceof GitSyncError
  ) {
    return err.message
  }
  return `Cloud session request failed: ${err instanceof Error ? err.message : String(err)}`
}

export function registerCloudHandlers(deps: {
  messenger: Messenger
  frontend: WebviewTypeMessageParticipant
  cloud: CloudSessions
  logger: Logger
  storage: vscode.Memento
  /** The signed-in account and organisation, for the history cache;
   *  undefined: none (nothing cached). */
  account(): string | undefined
  visibility: {
    isVisible(): boolean
    onDidChangeVisibility: vscode.Event<boolean>
  }
  /** Bring the sidebar's AI tab to the front. */
  reveal(): Promise<void>
}): vscode.Disposable {
  const { messenger, frontend, cloud, logger, storage, visibility } = deps
  const { manager } = cloud
  /** The session the webview shows, for notifications. */
  let viewedSession: string | undefined
  // From before the cache was per account: whose it was is unknown.
  void storage.update(LIST_CACHE_KEY, undefined)
  const cacheKey = (): string | undefined => {
    const account = deps.account()
    return account ? `${LIST_CACHE_KEY}:${account}` : undefined
  }
  const cachedList = (): AiCloudSessionSummary[] => {
    const key = cacheKey()
    return key ? (storage.get<AiCloudSessionSummary[]>(key) ?? []) : []
  }
  const cacheList = async (items: AiCloudSessionSummary[]): Promise<void> => {
    const key = cacheKey()
    if (key) await storage.update(key, items)
  }

  // Cloud-only notifications are queued while the view is hidden, like
  // chat events (register.ts ChatEventBuffer).
  const queue: Array<() => void> = []
  const post = (send: () => void): void => {
    if (visibility.isVisible()) send()
    else if (queue.length < 5000) queue.push(send)
  }
  const visibilitySub = visibility.onDidChangeVisibility((visible) => {
    if (!visible) return
    for (const send of queue.splice(0)) send()
  })

  const pushConfig = (): void => {
    messenger.sendNotification(AiCloudConfig, frontend, {
      enabled: cloud.isEnabled(),
    })
  }
  const configSub = vscode.workspace.onDidChangeConfiguration((e) => {
    if (e.affectsConfiguration(CLOUD_SESSIONS_ENABLED_SETTING)) pushConfig()
  })
  messenger.onNotification(WebviewFrontendIsReadyNotification, pushConfig)
  pushConfig()

  // ── Listener: events, state, progress ───────────────────────────────

  const notify = async (sessionId: string, message: string): Promise<void> => {
    const open = 'Open'
    const choice = await vscode.window.showInformationMessage(message, open)
    if (choice !== open) return
    await deps.reveal()
    messenger.sendNotification(AiCloudReveal, frontend, { sessionId })
  }

  cloud.listener.cloudEvent = ({ sessionId, event, replay }) => {
    // Strip the envelope; the webview keys everything by session.
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    const { seq, ts, ...payload } = event
    post(() =>
      messenger.sendNotification(AiCloudEvent, frontend, {
        conversationId: cloudConversationId(sessionId),
        sessionId,
        seq,
        replay,
        event: payload as AiCloudEventPayload,
      })
    )
    if (replay) return
    if (event.type === 'local-merge-conflict') {
      // The answer to the user's Sync, wherever they are now.
      void vscode.window.showWarningMessage(mergeConflictMessage(event.files))
      return
    }
    const background = !visibility.isVisible() || viewedSession !== sessionId
    if (background && event.type === 'ask-user') {
      // The question itself stays in the sidebar (see the file comment).
      void notify(sessionId, 'A cloud session has a question for you.')
    }
  }
  cloud.listener.mcpSignIn = (sessionId, servers) => {
    post(() =>
      messenger.sendNotification(AiCloudMcpSignInNeeded, frontend, {
        sessionId,
        servers,
      })
    )
  }
  cloud.listener.state = (sessionId, state) => {
    post(() =>
      messenger.sendNotification(AiCloudState, frontend, { sessionId, state })
    )
  }
  cloud.listener.gone = (sessionId) => {
    post(() =>
      messenger.sendNotification(AiCloudState, frontend, {
        sessionId,
        state: 'gone',
      })
    )
  }
  cloud.listener.progress = ({
    turnId,
    sessionId,
    phase,
    mcpServers,
    fileCount,
    title,
  }) => {
    messenger.sendNotification(AiCloudProgress, frontend, {
      turnId,
      ...(sessionId ? { sessionId } : {}),
      phase,
      ...(mcpServers ? { mcpServers } : {}),
      ...(fileCount !== undefined ? { fileCount } : {}),
      ...(title ? { title } : {}),
    })
  }

  // ── Requests ────────────────────────────────────────────────────────

  const guard = async <T extends AiCloudResult>(
    what: string,
    run: () => Promise<T>
  ): Promise<T | AiCloudResult> => {
    if (!cloud.isEnabled()) {
      return { ok: false, error: 'Cloud sessions are turned off.' }
    }
    try {
      return await run()
    } catch (err) {
      logger.warn(
        `cloud-sessions: ${what} failed: ${err instanceof Error ? err.message : String(err)}`
      )
      return { ok: false, error: cloudErrorMessage(err) }
    }
  }

  messenger.onNotification(AiCloudRun, (params) => {
    void (async () => {
      try {
        if (!cloud.isEnabled())
          throw new Error('Cloud sessions are turned off.')
        const seed = await cloud.gatherSeed(params)
        const { sessionId } = await manager.runInCloud({
          turnId: params.turnId,
          text: params.text,
          seed,
        })
        viewedSession = sessionId
      } catch (err) {
        logger.warn(
          `cloud-sessions: start failed: ${err instanceof Error ? err.message : String(err)}`
        )
        messenger.sendNotification(AiCloudProgress, frontend, {
          turnId: params.turnId,
          phase: 'error',
          error: cloudErrorMessage(err),
        })
      }
    })()
  })

  messenger.onRequest(AiCloudOpen, ({ sessionId }) =>
    guard('open', async () => {
      viewedSession = sessionId
      const info = await manager.open(sessionId)
      // The webview shows "Loading…" until this answers: wait for the
      // replay, so it never shows a state the log merely passed through.
      await manager.replayed(sessionId)
      return {
        ok: true,
        state: manager.stateOf(sessionId) ?? info.state,
        title: info.session.title,
        // By their names here ("Elefant Pro"), not the protocol-safe
        // ones the session stores ("Elefant_Pro").
        mcpServers: manager.mcpServerLabels(
          info.session.mcpServers.map((s) => s.name)
        ),
        mcpSignIn: manager.mcpSignInNeeded(sessionId),
      }
    })
  )

  messenger.onNotification(AiCloudViewing, ({ sessionId }) => {
    viewedSession = sessionId ?? undefined
    manager.setViewing(viewedSession)
  })

  messenger.onRequest(AiCloudMcpSignIn, ({ sessionId, server }) =>
    guard('MCP sign-in', async () => {
      await manager.signInMcp(sessionId, server)
      return { ok: true }
    })
  )

  messenger.onRequest(AiCloudCommand, ({ sessionId, command }) =>
    guard(command.type, async () => {
      let res
      if (command.type === 'message' || command.type === 'inject') {
        // Add the prompt's @-mentioned files and active file first (§10).
        const files = await cloud.gatherPromptFiles({
          mentions: command.mentions ?? [],
          attachments: [],
          includeActiveFile: command.includeActiveFile ?? false,
          ...(command.activeFile ? { activeFile: command.activeFile } : {}),
        })
        res =
          command.type === 'message'
            ? await manager.sendMessage(
                sessionId,
                command.turnId,
                command.text,
                files
              )
            : await manager.inject(
                sessionId,
                command.turnId,
                command.text,
                command.injectionId,
                files
              )
      } else {
        res = await manager.send(sessionId, command)
      }
      return { ok: true, state: manager.stateOf(sessionId) ?? res.state }
    })
  )

  messenger.onRequest(
    AiCloudRollback,
    ({ sessionId, turnId, undoesLaterTurns, undoesLocalSync }) =>
      guard('rollback', async () => {
        if (undoesLaterTurns || undoesLocalSync) {
          const restore = 'Restore'
          const detail = [
            undoesLaterTurns
              ? 'This also undoes the file changes of every later turn.'
              : '',
            undoesLocalSync
              ? 'Local changes you synced into the session after this turn are undone too.'
              : '',
          ]
            .filter(Boolean)
            .join(' ')
          const choice = await vscode.window.showWarningMessage(
            'Restore the files to before this turn?',
            { modal: true, detail },
            restore
          )
          if (choice !== restore) return { ok: false, cancelled: true }
        }
        const res = await manager.rollback(sessionId, turnId)
        return { ok: true, state: manager.stateOf(sessionId) ?? res.state }
      })
  )

  messenger.onRequest(AiCloudStop, ({ sessionId }) =>
    guard('stop', async () => ({
      ok: true,
      state: await manager.stop(sessionId),
    }))
  )

  messenger.onRequest(AiCloudDelete, ({ sessionId }) =>
    guard('delete', async () => {
      // The only copy of the session's files, unless it was cloned: the
      // trash is emptied within minutes.
      const del = 'Delete'
      const choice = await vscode.window.showWarningMessage(
        'Delete this cloud session and its files?',
        {
          modal: true,
          detail:
            'Its conversation and files are deleted for good. A clone you made keeps its copy.',
        },
        del
      )
      if (choice !== del) return { ok: false, cancelled: true }
      // 204 at once, also while the task still runs (cleaned up later).
      await manager.delete(sessionId)
      await cacheList(cachedList().filter((s) => s.sessionId !== sessionId))
      if (viewedSession === sessionId) viewedSession = undefined
      return { ok: true }
    })
  )

  messenger.onRequest(AiCloudRename, ({ sessionId, title }) =>
    guard('rename', async () => {
      await cloud.api.renameSession(sessionId, title)
      await cacheList(
        cachedList().map((s) =>
          s.sessionId === sessionId ? { ...s, title } : s
        )
      )
      return { ok: true }
    })
  )

  messenger.onRequest(AiCloudSessionList, async ({ refresh }) => {
    const cached = cachedList()
    if (!cloud.isEnabled()) return { items: [] }
    if (!refresh) return { items: cached }
    try {
      const { sessions } = await manager.list()
      await cacheList(sessions)
      return { items: sessions }
    } catch (err) {
      return { items: cached, error: cloudErrorMessage(err) }
    }
  })

  // ── Clone / Sync (§9.3) ─────────────────────────────────────────────

  messenger.onRequest(AiCloudGitStatusRequest, async ({ sessionId }) => {
    if (!cloud.isEnabled()) {
      return { kind: 'unavailable', message: 'Cloud sessions are turned off.' }
    }
    return (await cloud.git.status(sessionId)) as AiCloudGitStatus
  })

  messenger.onRequest(AiCloudGitAction, async ({ sessionId, action }) => {
    const status = async (): Promise<AiCloudGitStatus> =>
      cloud.isEnabled()
        ? await cloud.git.status(sessionId)
        : { kind: 'unavailable', message: 'Cloud sessions are turned off.' }
    try {
      if (!cloud.isEnabled()) throw new Error('Cloud sessions are turned off.')
      if (action === 'sync') {
        return { status: await cloud.git.sync(sessionId) }
      }
      const picked = await vscode.window.showOpenDialog({
        canSelectFolders: true,
        canSelectFiles: false,
        canSelectMany: false,
        openLabel: 'Clone here',
        title: 'Choose where to put the cloud session’s files',
      })
      if (!picked?.[0]) return { status: await status(), cancelled: true }
      const folder = await cloud.git.clone(sessionId, picked[0])
      void (async () => {
        const open = 'Open Folder'
        const add = 'Add to Workspace'
        const choice = await vscode.window.showInformationMessage(
          `Cloned the cloud session to ${folder.fsPath}.`,
          open,
          add
        )
        if (choice === open) {
          await vscode.commands.executeCommand('vscode.openFolder', folder, {
            forceNewWindow: true,
          })
        } else if (choice === add) {
          vscode.workspace.updateWorkspaceFolders(
            vscode.workspace.workspaceFolders?.length ?? 0,
            0,
            { uri: folder }
          )
        }
      })()
      return { status: await status() }
    } catch (err) {
      return { status: await status(), error: cloudErrorMessage(err) }
    }
  })

  return {
    dispose(): void {
      visibilitySub.dispose()
      configSub.dispose()
      queue.length = 0
    },
  }
}
