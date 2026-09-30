# ai-turn-reattach-ownership — post-mortem

ai-proxy · branch `thomasgorissen/ai-turn-reattach-ownership` · base `main` · [PR #4](https://github.com/legalese/ai-proxy/pull/4) · 2026-09-28

## What was built

- `TurnOwner { orgId, creatorId }` and `turnOwnerOf(auth)` in `src/turn-registry.ts`; `Turn.owner` records who started the turn.
- `TurnRegistry` is keyed by owner + turn id: `create(turnId, owner)`, `lookup(turnId, owner)`. `src/chat.ts` passes `turnOwnerOf(auth)` on create; the reattach route (`GET /v1/chat/turns/{id}/stream`, `src/index.ts`) looks up with the caller's owner. A turn owned by someone else is a miss → the same `404 Turn not found or expired` as an unknown id.
- Two related holes closed by the keying: a different caller reusing a client-chosen turn id on POST no longer aborts the original turn, and a replaced turn's reaper no longer evicts its successor.

## Spec sections covered, and deviations (with reasons)

§15.2. Keyed the map by owner rather than only comparing on lookup, because comparing alone would have left the cross-owner abort on `create`. Same external behaviour (404 on mismatch).

## Checks run

`npm ci`, `npx tsc --noEmit`, `npm run lint` (0 errors, 2 pre-existing warnings), `npm test` (15 files, 161 tests), `npm run build`. No PR CI in this repo.

## Problems and how they were solved

Based on `main`, independent of #3, so `conversationCreatorId` isn't available; `turnOwnerOf` repeats the expression (`userId ?? api-key-{keyId}`).

## Open questions and follow-ups for later items

After #3 and #4 both merge, `turnOwnerOf` should delegate to `conversationCreatorId` (trivial conflict-free follow-up). With #3, an agent key and the same user's session share an owner, so the user can reattach to their agent's turn — intended.

## Where a reviewer should start

`src/turn-registry.ts` (`TurnRegistry`), then `src/turn-registry.test.ts`.
