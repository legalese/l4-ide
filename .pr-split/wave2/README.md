# Wave 2 of the aug2026 re-partition

Wave 1 (the 19 `aug2026` PRs) re-cut `main..unstable` as of `b388f9a6` (10 Aug). By 24 Aug
`unstable` had gained 24 more merged PRs (#256, #258–#265, #267–#282 less #266; see below).
Wave 2 re-cuts that delta into 7 theme PRs, base branch `claude/aug2026-w2-base`.

## The base, and why it is `8af7d332`

`8af7d332` is #256's merge of `main` into `unstable`. Verified equivalences:

- `main`'s tip `8917dc3f` is an ancestor, so the tree contains all of main's plugin track;
- its diff against `b388f9a6` is exactly that track plus **pure `R100` renames** relocating
  `.claude/skills/writing-l4-rules/*` to `skills/*` — the same translation wave 1's
  agent-tooling slice performs, with blob identity guaranteed by the rename detection;
- no wave-1 manifest claims any file that merge touched.

Therefore tree(`8af7d332`) == tree(`main` + all 19 wave-1 slices), and a PR based on it
shows exactly wave-2 content. When wave 1 lands on `main`, retarget these PRs to `main`.

## The partition (350 files, exact closure verified)

| theme | files | note |
| --- | --- | --- |
| blawx | 150 + spine | upstream #261 #270 #272 #273 #276 #277 #278 #279 #280 |
| docassemble | 74 + spine | #264 #265 #267 #268 #269 |
| sg-succession | 57 | #274's corpus only |
| pipeline | 48 | #274's infra + #281; all of wave-2 `etc/go` reviews as one unit |
| repairs | 11 | #274's stdlib+service fixes, #259, #282 |
| applies | 2 | #263 #275, + #262's SUBJECT-TO datapoint (disclosed both sides) |
| backends-docs | 4 | #258 #260 #262 #271 |

**#274 split five ways** (corpus / pipeline / stdlib fix / service fix / CI wiring) because
its `etc/go` edits and #281's store are two authorship layers in the same files — splitting
those files by PR would leave both slices red in opposite directions, so all wave-2
`etc/go` content lives in `pipeline`, and the excel-date fix travels with its re-blessed
goldens in `repairs`.

**Two files net to zero** (docassemble `not-ok/` fixtures added mid-arc, deleted by M4) and
appear in no manifest.

**#266 (Catala implementation) is stranded**: it merged into #260's branch *after* #260 had
merged into `unstable`, so its 33 files are on `mengwong/catala-bridge` with the PR closed,
and are not wave-2 content. Needs a fresh PR into `unstable`.

## The spine (4 files, blawx × docassemble)

`jl4/jl4.cabal`, `jl4-core/jl4-core.cabal`, `jl4/app/Main.hs`, `jl4/tests-cli/Main.hs`.
`make-spine.py` attributes every added line by `git blame` (commit → PR → theme; the two
deletions are docassemble's one-line modifications), reconstructs each theme's version, and
proves (a) base + all attributed lines == `unstable`'s blob byte-for-byte, (b) each theme's
version differs from base by exactly its own lines. The two versions textually conflict at
shared insertion points if merged pairwise — expected; the merge vehicle is `unstable → main`.

## Ship

    wave2/ship.sh <theme> <worktree>   # builds branch, commits, pushes, opens/updates draft PR

Both Haskell-bearing slices (blawx, docassemble) were built and tested locally before
first ship — the discipline wave 1 lacked.
