# cloud-sessions-ui — post-mortem

l4-ide · branch `thomasgorissen/cloud-sessions-ui` · base `cloud-sessions-git-sync` · [PR #512](https://github.com/legalese/l4-ide/pull/512) · 2026-09-28

## What was built

- RPC: `ts-shared/jl4-client-rpc/cloud-sessions-messages.ts` (`AiCloud*`
  notifications/requests, `cloudConversationId` = `cloud:<sid>`).
- Extension: `cloud/register-cloud.ts` (all handlers, queued cloud events
  while hidden, VS Code notifications with _Open_, cached session list,
  rollback confirmation modal, clone folder picker). Chat events of cloud
  sessions are re-keyed to `cloud:<sid>` in `vscode-cloud.ts`.
- Webview: `lib/stores/cloud-chat.ts` (pure: history merge, `adoptTurn`,
  `applyCloudEvent`, `rollbackOffer`), store changes in `ai-chat.svelte.ts`
  (cloud routing of send/inject/abort/answer/retry, Run in cloud,
  progress, open/replay, resume/stop, git), `cloud-banner.svelte`, history
  rows with cloud icon + state badge, rollback buttons in `message-list`,
  Run in cloud + Clone/Sync in `chat-input`. Vitest added to the webview
  (14 tests).

## Spec sections covered, and deviations (with reasons)

§12.1, §12.2, §9.4 UI, §9.3 button, §8 `user-message`. Deviations:

- Run in cloud only on a fresh chat (local history can't move to a session).
- Retry of a cloud reply = re-send the last prompt as a new turn.
- Follow-up prompts can't carry attachments (API takes them at create only).
- `onStarted` adopts unknown turns for local chats too (fixes the dropped
  deltas generally, not only for cloud).
- Stop during upload only stops the spinner.

## Checks run

`npm ci`, `npm run build`, `lint`, `format:check`, `check`, `npm test` — pass
locally (21/21 turbo tasks). One pre-existing `svelte-check` warning
(`deployment-integrate-popover.svelte`). No PR CI (stacked). Not run in a
live VS Code; no deployed Sessions API to try it against.

## Problems and how they were solved

- Chat and cloud events are buffered separately while the sidebar is hidden,
  so `user-message` can arrive after its reply's `started`: the prompt is
  inserted before its reply instead of appended.
- Replaying a log re-raised answered questions: a question is cleared when
  its tool call finishes or the turn is done.
- Typing Send during a pending Run-in-cloud would start a second session;
  guarded.

## Open questions and follow-ups for later items

- Runner: the UI keys replies by the `message` turn id; `started.turnId`,
  `git-committed.turnId` and `rolled-back.turnId` must be that id (not a
  sub-turn id). Inject echoes as `user-message` should carry the running
  turn's id.
- Clone should wait for the first `git-committed` (empty repo before).
- Not verified: behaviour with two windows on one session, and notification
  noise for long-running background sessions.

- Follow-up 2026-09-30: no approval UI, commands or notifications for cloud sessions (local chats unchanged); notifications = questions and Resume; start banner lists passed MCP servers with the no-approval note; rollback unaffected by the `data/`/`tmp/` layout. Checks re-run locally, all pass.

## Where a reviewer should start

`lib/stores/cloud-chat.ts` and its tests, then the cloud block in
`ai-chat.svelte.ts` (search "Cloud sessions (spec"), then
`cloud/register-cloud.ts`.
