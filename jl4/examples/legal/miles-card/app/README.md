# Projecting the consumer app's `D[]` out of the encoding

`which-card.html` — the "which card should I use" app — is driven by one array, `const D=[…]`, of
51 rows: 42 spend categories and 9 reference cards. Today that array is typed by hand. This
directory generates it from the L4 encoding of the issuers' own terms instead, so that every rate,
cap, condition, citation and confidence marker on the page is something a clause says rather than
something someone remembered.

Spec §7 of `docs/projects/miles-card/SPEC-miles-card-l4-encoding.md` sets the bar, and it is worth
repeating here because it is the whole point:

> The projection must carry justification and confidence, not just conclusions. A generator that
> emits only the answer reproduces [version 3's confident, wrong renderer] at scale, prettily.

So each generated card slot carries the rate, the cap and its reset basis, the pool the cap runs
against, the conditions, the `[document cl.N]` citations, and a status pill where the answer is not
simply verified.

## Files

| file             | what it is                                                                        |
| ---------------- | --------------------------------------------------------------------------------- |
| `scenarios.json` | hand-maintained. One entry per app row: the fact side of a representative charge. |
| `gen-d.mjs`      | the generator. Node, no dependencies.                                             |
| `D.generated.js` | its output. Overwritten on every run; do not edit.                                |
| `DIFF.md`        | the generated array against the app's current hand-edited one, classified.        |

**The app itself is not in this repository and must not be copied into it.** Two copies live in
the homelab checkout under `docs/projects/miles-card/app/`: `which-card.alexis-original.html`,
Alexis's, which nothing touches, and `which-card.html`, Meng's fork, which is where generated
output goes. The generator reads a copy only when you ask for a comparison, from the path you give,
and never writes to either.

## Regenerating

```sh
export L4=/path/to/your/worktree/dist-newstyle/.../l4
node gen-d.mjs
```

Ten seconds, 378 evaluations, 51 rows.

| flag               | effect                                                                     |
| ------------------ | -------------------------------------------------------------------------- |
| `--out FILE`       | write the array somewhere other than `D.generated.js`.                     |
| `--keep-workdir`   | leave the generated probe module on disk to read.                          |
| `--reference PATH` | also compare the result against the app's `D[]` at PATH. Unset by default. |
| `--diff-out FILE`  | with `--reference`, write the comparison to a file instead of stdout.      |

`--reference` is how `DIFF.md`'s counts were produced and how they are re-checked:

```sh
node gen-d.mjs --reference ~/src/mengwong/homelab/docs/projects/miles-card/app/which-card.html
```

It reads that file, extracts its `const D=[…]`, matches it row for row against the generated array,
and prints one line per comparison plus a tally by class and by tag. It abandons the comparison, with
a message and exit 1, if the two arrays have different lengths or if a row's name does not match: a
comparison that has quietly slipped by one row would report nonsense confidently. The array itself
is written before any of this, so a failed comparison never costs you the output.

A comparison it cannot place lands in an `UNCLASSIFIED` tag rather than being folded into a
neighbouring bucket, so a new kind of disagreement shows up as a number nobody wrote a rule for.
That is not decorative: changing the drop rule on 2026-09-21 put three PAssion slots into
`UNCLASSIFIED`, which is how they got a rule of their own instead of being absorbed into
`APP-CURATES`.

`$L4` is not optional in spirit even though the script will fall back to an `l4` on `PATH`. **A
binary older than the corpus it reads reports newly-landed syntax as broken source**, and the error
points at the line after the construct it could not parse, so it reads as a broken encoding rather
than a stale tool. Build from this worktree and point `$L4` at that.

`JL4_LIBRARY_PATH` defaults to `<repo>/jl4-core/libraries`, computed from this file's own location.
Override it only if you know why.

## How it works, and the two things that are not obvious

The generator writes a throwaway L4 module — one `Cardholder`, one `Month position`, one
`Transaction` per scenario, and a `#EVAL` of `` `the rate on` `` for every scenario against each of
the nine cards — runs `l4 run --json` over it, and parses the printed answers.

**It builds that module in a temp directory of symlinks, not here.** The probe has to sit beside
the corpus modules for importer-relative `IMPORT` to find them, but this directory is under
`jl4/examples/legal/`, which is inside the golden globs: a stray `.l4` there turns `jl4-test` red
for whoever branches next. So `gen-d.mjs` symlinks every corpus `.l4` into `mkdtemp`, writes the
probe alongside them, and removes the lot.

**It parses the printed value against a schema, not with a regex.** `l4 run --json` renders a
`Rate answer` positionally — `` `Rate answer` OF 36, 0.28, Verified, … `` — and the comma between
two fields of a record is the same character as the comma between two elements of a list, so the
text is only unambiguous if you already know the shape. The descriptors at the top of `gen-d.mjs`
are that shape, and **they must stay in the field order of the `DECLARE`s in
`miles-card-domain.l4`.** Reorder a field there and the parser will happily read the wrong column
into the wrong name. It would not necessarily fail: two adjacent `NUMBER` fields swap silently.
That is the one change to the domain that this script cannot detect for you.

`l4 batch` would have been the natural route and does not work here. Its wrapper decodes rows with
`JSONDECODE`, which fails to resolve an enum constructor when the enum is declared beneath a `§`
heading — every enum in this domain is — and the failure surfaces far away as "the value `"Red"`
reached a CONSIDER that has no branch for it".

## The rules the generator applies, so you can argue with them

- **A card answering 0 mpd is dropped — unless its status says why, or unless every card on the row
  is 0.** "Answering 0" means no branch earns anything: a conditional answer whose lower branch is 0
  is kept, because that conditional is the uncertainty the page exists to show.

  The status exception is what puts POSB PAssion back on all 42 rows at `0 mpd` with an `EXPIRED`
  pill. Its promotion period ended on 30 September 2025, so it answers 0 everywhere; under the
  earlier rule it was dropped everywhere, which deleted the reason along with the rate and left the
  table with no `EXPIRED` pill at all. A card the app still recommends having stopped paying is not
  a card worth hiding. Spec §7 asks the projection to carry confidence and not only conclusions, and
  an absent row carries neither. `Verified` and `Unconfirmed` zeroes stay dropped: those are the
  ordinary "not this card, not this purchase" answers and there are hundreds of them.

  `Disputed by source` is deliberately **not** in the kept set. The same argument would carry it,
  but no module returns that status yet, and a rule written for no case is a rule nobody can check.
  Whoever fills `miles-card-disputed.l4` from the acceptance run should decide then.

- **Cards are ordered by descending `miles per dollar`.** For an answer that depends on the merchant
  indicator, that field carries the **lower** branch by design, so a "4 mpd if online, else 0.4"
  answer sorts at 0.4 and lands below a flat 1.4 mpd card. The ordering is conservative and it is
  not the app's.
- **Statuses render as the app's vocabulary.** `Verified` gets no pill. `Unconfirmed` →
  `UNCONFIRMED`, `Source expired` → `EXPIRED`, `Disputed by source` → `DISPUTED`. An unrecognised
  status throws rather than being dropped.
- **Citations are `[document cl.N]`**, deduplicated, in the order the answer lists its sources.
- **The clock is fixed** at `2026-09-22T00:00:00Z`, passed as `--fixed-now`. Two runs over one
  `scenarios.json` are byte-identical. Rules that read "now" — the PAssion promotion period is the
  one that does — are answered against a stated day rather than against whenever you ran this.
- **Any failure is fatal.** A non-zero exit from `l4`, an error diagnostic, a result count that does
  not match the plan, a directive that produced something other than a value, or a value the parser
  cannot read: the script prints what went wrong and exits non-zero without writing an output file.
  A table that is 95% evaluated still looks like an answer, which is worse than no table.

## Editing `scenarios.json`

`n`, `k` and `mcc` were copied out of the app so the two arrays line up row for row; leave them
alone unless the app's row changes. Everything under `transaction` is hand-written from the row's
own words, and `mccChoice` records which code was picked where the row lists several and why.

Three constraints on the fact side are deliberate and shared by all 42 rows: `merchant indicator`
is always `Unknown`, which is what makes the conditional answers appear; `description patterns` is
always empty; and `charge kind` is always `Retail purchase`. The second and third are the ones most
worth relaxing — the exclusion machinery in every module keys on them and nothing here exercises it.

## Publishing

**This script never writes to the app.** `D.generated.js` is an artifact in this repository. Getting
it into `docs/projects/miles-card/app/which-card.html` in the homelab fork is a human step, taken by
someone who has read `DIFF.md` and decided, difference by difference, which side is right. Several
of the differences are the encoding abstaining rather than correcting, and pasting over them without
reading would replace a true figure with a cautious one.

Checked 2026-09-21: **that file has no paste markers yet.** Its array starts at `const D=[` near
line 259 and ends at the matching `];`. Whoever does the first paste should add a marker pair around
it, so that the next one is a replace rather than a hunt — but adding them is that person's edit to
the fork, not something this script or this directory does.
