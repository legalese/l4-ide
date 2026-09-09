# Plugin distribution: split the plugin out of the monorepo

> **Status — PROPOSED, NOT LANDED (2026-09-09).** Nothing here has been agreed.
> The branch that carries this document also moves the skill directory, which
> reverses a deliberate decision in `4c4c5ed4` (Thomas Gorissen, 2026-08-07);
> **that reversal needs Thomas's approval before this goes near `unstable`.**
> No `legalese/l4-plugin` repository has been created. The generated bundle
> exists only as a local, unpushed git repo for experimentation.
>
> What _is_ measured, and stands on its own regardless of the decision, is §1.

## 1. The measurement

`.claude-plugin/marketplace.json` names the plugin's source as:

```json
"source": { "source": "github", "repo": "legalese/l4-ide", "path": "." }
```

`path: "."` makes the plugin root the repo root. So the install method the
release notes label **"(Recommended)"** —

```
/plugin marketplace add legalese/l4-ide
/plugin install l4-computational-law@legalese
```

— resolves the plugin to this entire monorepo.

|                                            |                       |
| ------------------------------------------ | --------------------- |
| packed `.git` a plugin install resolves to | **289 MB**            |
| tracked files                              | 4,547                 |
| the skill that is actually published       | **0.53 MB**, 22 files |
| the skill plus every file it cites         | **4.82 MB**, 71 files |

Two further facts about the present state, both verified on `fca84449`:

- **Only one of the two skills is published at all.** `plugin.json` declares no
  `skills` field, so it defaults to root `skills/`, which held
  `writing-l4-rules` alone. `running-the-l4-pipeline` was never shipped, and
  should not be: it dispatches `etc/go/go.sh` and reads
  `etc/go/subjects/<subject>/NOTES.md`, so outside this repo it is inert.
  That — not accident — is why the two skills sat in different directories.
- **Lightweight packages already exist and nothing points at them.**
  `release-l4-skill.yml` builds `writing-l4-rules.skill` and `l4-plugin.zip`
  on every release. Both are listed _below_ the marketplace instructions, as
  fallbacks.

### 1.1 The skill teaches by example, and does not carry the examples

The skill names **49 files it does not contain** — `jl4/examples/legal/regcf/regcf.l4`
alone appears 20 times, `promissory-note.l4` 13 times — and **only four of those
citations are markdown links.** The rest are prose: `jl4/examples/legal/regcf/regcf.l4:142`.

This matters for what a "skill-only" package means. Shipping the skill alone
does not produce visible broken links. It produces something quieter: an agent
told _"see how `regcf.l4` handles this"_ with no `regcf.l4` on disk. The
failure is silent at package time and shows up as a worse answer later.

## 2. What the branch does

1. **Moves `skills/writing-l4-rules/` to `.claude/skills/writing-l4-rules/`**
   and deletes the symlink at that path. Both skills become plain directories
   in the ordinary project-skill location; nothing in the tree is a symlink.
2. **Updates every reference** — 9 files across workflows, specs, `paper/`,
   `PLUGIN.md`, and the VS Code build script.
3. **Adds `etc/build-plugin-bundle.mjs`**, which generates the distributable
   bundle: the skill, plus every file the skill cites, at the citation's own
   repo-relative path.
4. **Rewires `release-l4-skill.yml`** to package what that generator produces,
   so a released zip and a published repo cannot disagree.

### 2.1 Why the bundle set is computed, not listed

A maintained include list goes stale the first time someone cites a new
example, and goes stale **silently** — the symptom is a worse answer from an
agent, months later, with nothing red anywhere. Extracting citations from the
skill's own text is a rule; a list is a promise. Cite a new example, and the
next build carries it.

### 2.2 Two defects this surfaced, both fixed here

- **Four relative links broke on the move and nothing would have caught it.**
  The skill went from two directories deep to three, so
  `](../../../../doc/...)` in `references/source-patterns/` lands one level
  short. `doc/test-docs.sh` walks `doc/` only; no check anywhere validates a
  link inside a skill. The generator's self-check now verifies the artifact
  from outside, and refuses to build a bundle with a dangling citation.
- **The VS Code build script warned instead of failing.**
  `ts-apps/vscode/scripts/build.mjs` bundled the skill into the `.vsix` and, if
  the directory was missing, printed a warning and continued — shipping an
  extension whose "install the skill" command has no skill to install. It now
  throws. A directory move should break a build, not a user's editor.

## 3. What the branch deliberately does NOT do

- **No repository is created, and nothing is pushed.** The bundle is a local
  git repo with no remote.
- **The marketplace source is unchanged in this tree.** Repointing it is the
  architectural decision, and it is Thomas's to make.
- **No vocabulary or content change to the skill.** Meng is undecided on
  whether the retired-terms sweep should cover `skills/`; that question stays
  where it is, on PR #380.

## 4. Open questions for Thomas

- **Q1.** Does the plugin move to its own repository, or does `l4-ide` keep
  shipping as the plugin and accept the 289 MB?
- **Q2.** If it moves: does the marketplace catalog stay in `l4-ide` — so
  `/plugin marketplace add legalese/l4-ide` keeps working for anyone who has
  already added it, while the plugin `source` points elsewhere — or does the
  catalog move too, and existing subscribers re-add?
- **Q3.** Is the move to `.claude/skills/` right at all? It is only clearly
  right _if_ Q1 is "yes". If `l4-ide` remains the plugin, the Agent Plugins
  fixed location is `skills/`, `4c4c5ed4` was correct, and the symlink is the
  right answer to a question this proposal would otherwise be changing.
- **Q4.** Publishing direction: push from `l4-ide` on merge (needs a token or
  deploy key) or pull from the plugin repo on a schedule (needs no secret,
  lags). The branch implements neither.
