# Release model — how `unstable` reaches `main`, and what a release actually is

> **Status: the ROUTE is ruled, 2026-09-06. Wave 3 is NOT started and needs Meng's go on scope.**
> Rulings-bench card `D9-release-and-partition`, marked **decline** — that is, the card's
> _recommended_ option A was declined and its option D was taken. This file is the ruling's home
> because the tree had no release document: a grep for one matched only `release-l4-skill.yml` and
> four corpus image files.
>
> Nothing here changes a workflow, a branch or a tag. What it changes is `CLAUDE.md:19`, which said
> something that is not true (§D9.2).

## D9.1 — `unstable` reaches `main` through human-reviewable topic PRs, not one merge PR. RULED 2026-09-06.

**The ruling, in Meng's words, verbatim:**

> It's looking like d because we need organizationally approved review process by humans.

So: **re-cut a wave 3** of topic PRs with the `.pr-split/` toolchain on branch
`claude/unstable-branch-reorganization-6cle91` @ `50e790d6`, refreshing the 26 `aug2026` drafts. The
single conflict-free `unstable → main` merge PR — which the card recommended, and which is
technically available — is **declined**.

**What decided it, and it matters that this is not a technical finding.** The organisation requires
a human-approved review process. A single merge PR of the whole integration branch is not reviewable
by a person in any meaningful sense; a wave of topic PRs is. The decline is therefore **on process
grounds, not on the merits of the merge**, and a later reader must not "fix" it by observing that
the merge is conflict-free. It is conflict-free. That was never the question.

**The known cost, cited as cost and not as an objection.** Partition waves are expensive and this
project has measured how: **wave 1's twelve-PR type-level interlock was found only by building** —
no amount of reading the diffs surfaced it — and **wave 2 got no CI at all**, because its PRs were
cut against a base that fired no workflows. Whoever runs wave 3 should assume both: that the
interlock is discovered by compiling the wave end to end, and that CI on a re-cut base must be
verified to actually run rather than assumed from a green tick.

## D9.2 — The merge is not the release. RULED 2026-09-06.

Landing `unstable` on `main` releases nothing. The release is a **manual `workflow_dispatch`** of
`.github/workflows/main-tag.yml`, which says so in its own header comment: _"this release/tag
pipeline no longer runs automatically when a PR merges into main. Trigger it from the Actions tab
when you actually want to cut a build/tag."_ The workflow **mints its own tag** from
`github.run_number` — `1.5.<run_number>`, matching the VS Code extension version and the
`l4-ide-build-<run_number>` tag (`main-tag.yml:211-222`, `:475`, `:540`).

**Consequence, and it is the reason `CLAUDE.md` needed repairing: a hand-pushed tag runs nothing.**
Pushing `v1.5.7` by hand produces a git tag and no artifacts, because the workflow is not triggered
by tags and does not read one. The tag is an **output** of the release, not its input.

## D9.3 — Two artifact tracks, cut from different refs. RULED 2026-09-06.

| track                                                     | cut from                    | by                                            |
| --------------------------------------------------------- | --------------------------- | --------------------------------------------- |
| the **VS Code extension** (+ `jl4-service`, LSP binaries) | `main`                      | `main-tag.yml`, manual `workflow_dispatch`    |
| standalone **`l4` / `jl4-lsp`** prereleases               | `unstable`, ahead of `main` | the prerelease shelf (`legalese/prereleases`) |

The shelf exists precisely so a compiler prerelease does not have to wait for a `main` release, and
so that cutting one does not touch `l4-ide`'s release surface. **A reader planning a release must
say which track they mean**; "cut a release" is ambiguous between the two and they do not come from
the same ref.

## D9.4 — A superseded partition wave is kept, not deleted. RULED 2026-09-06.

The 26 `aug2026` drafts are **kept in `.pr-split/`** and their PRs stay open until their wave-3
successor opens. Closing a draft before its replacement exists loses the only record of how that
slice was partitioned, and the partition is the expensive part — it is what wave 1 paid for by
building.

---

## What this ruling does not decide

- **Wave 3's scope.** Not started. Needs Meng's go on how the tree is sliced, which is a judgement
  about reviewability, not a mechanical re-run of the toolchain.
- **Whether the shelf eventually replaces `main-tag.yml`'s LSP artifacts.** Out of scope here.
- **A `doc/` page.** `CLAUDE.md` §6 wants one if this changes how a contributor cuts a build. It
  does not: the route to `main` changes, the act of cutting a build does not. If wave 3 changes the
  contributor-facing procedure, that PR owes the page.
