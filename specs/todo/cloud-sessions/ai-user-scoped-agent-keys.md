# ai-user-scoped-agent-keys — post-mortem

ai-proxy · branch `thomasgorissen/ai-user-scoped-agent-keys` · base `main` · [PR #3](https://github.com/legalese/ai-proxy/pull/3) · 2026-09-28

## What was built

- Net effect of the prototype branch `thomasgorissen/ai-cloud-agent` (commits 0884a52, 496cfcd, bdf9061), without the dropped JWT verifier: `src/api-key-owner.ts` (+ test) reads the org from `owner.organization_id` for user-owned WorkOS keys; user-scoped keys are never cached in `src/auth.ts`. The prototype's stray `package-lock.json` / `src/env.ts` churn was not carried over.
- New `apiKeyUserId(owner)`; for user-scoped keys `AuthResult.userId = owner.id`. A user-scoped key without a user id fails as `invalid-credentials`.
- `conversationCreatorId(auth)` in `src/auth.ts` replaces the duplicated expression in `src/chat.ts` and `src/conversation-read.ts`. Agent conversations now live in `{org}/{user_…}/`, so they survive key rotation and the user's sealed session reads them via `GET /v1/conversations/{id}` (creator-scoped `ConversationStore.load`, scope passed as `null`, so no cross-creator fallback).
- ARCHITECTURE.md: user-scoped keys paragraph, EFS layout comment.

## Spec sections covered, and deviations (with reasons)

§6.2 (ai-proxy accepts agent keys), §15.2. No deviations.

## Checks run

`npm ci`, `npx tsc --noEmit`, `npm run lint` (0 errors, 2 pre-existing warnings in `src/chat.ts`), `npm test` (17 files, 172 tests), `npm run build`. ai-proxy has no PR CI (only a manual deploy workflow), so `gh.py checks` reports none.

## Problems and how they were solved

- `@workos-inc/node` 7.82 types `owner` as org-only; the helpers take `unknown` (as on the prototype). The serializer passes `owner` through raw, so `organization_id` (snake case) is what arrives.
- Running prettier over `src/chat.ts` reformats unrelated code (main isn't prettier-clean); reverted and applied only the targeted edit.

## Open questions and follow-ups for later items

- `DELETE /v1/conversations/{id}` is org-wide (`softDeleteByRename` walks every creator), not creator-scoped; any `ai:chat` caller in the org — now including agent keys — can delete another member's conversation by id. Pre-existing; worth its own fix.
- `ai-turn-reattach-ownership` (#4) repeats the creator expression in `turnOwnerOf`; after both merge it should call `conversationCreatorId`.

## Where a reviewer should start

`src/auth.ts` (API-key branch of `authenticate`, `conversationCreatorId`), then `src/auth.test.ts` and `src/conversation-owner.test.ts`.
