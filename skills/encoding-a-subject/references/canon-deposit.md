# Depositing an encoding in canon

[`legalese/canon`](https://github.com/legalese/canon) is the corpus repository: it holds law, and `legalese/l4-ide` holds tools.
Its layout is ruled in `docs/directory-conventions.md` (rulings Q1–Q6, 2026-08-05; the ISO spelling ruled again 2026-09-26), on canon's `main`.
Read it before creating a subject, and check whether the law already has one: a second encoding of a law is a new row beside the others, not a new subject.

## Where

- **Branch.** Members of the `legalese` GitHub organisation commit straight to `main` (ruled 2026-09-26).
  **Contributions from outside Legalese are welcome**, by the standard GitHub route: fork `legalese/canon`, commit to a branch of your fork, and open a pull request against `main`.
- **The law**: `subjects/<jurisdiction>/<slug>/`
  - `<jurisdiction>` is the ISO 3166-1 alpha-2 code of the enacting authority, lowercase: `sg`, `il`, `us`, `uk`, and `eu` for the European Union.
    A subdivision nests as its own path component using its ISO 3166-2 suffix: `us/ca`, `uk/sct`.
  - `<slug>` is a short lowercase name; a statute takes `<short-title>-<enactment-year>` (`bna-1981`, `housing-act-1988`), a regulation may use an established nickname (`regcf`).
  - Contracts go under `subjects/contracts/<genre>/<slug>/` instead (`contracts/payments/sg-miles-card`); see §3 of the conventions document.
- **Your encoding**: `subjects/<jurisdiction>/<slug>/encodings/<row>/`.
  Rows are equal: canon holds every encoding of a law side by side and ranks none of them.
  Name the row for who made it, adding the occasion if you make more than one (`legalese`, `cleanroom-2026-08`).

## What goes in each

```
subjects/<jurisdiction>/<slug>/
  subject.json              facts about the LAW — true whoever encodes it
  README.md                 optional: the law in a paragraph, for a human
  source/                   optional: the fetched source files, with their provenance
  encodings/<row>/
    encoding.json           facts about THIS ENCODING
    NOTES.md                scope, coverage table, fork register, answer table, open questions
    SOURCE-LICENSE.md       the terms the quoted source text carries
    *.l4                    the modules
    check.sh                the self-check from this skill
```

**`subject.json`** — `id` (the slug), `display_name`, `citation`, `extent`, `authority` where the path is coarser than the enacting body, and `source` (URL, and a note on versions and provenance).

**`encoding.json`** — `id`, `encoder`, `display_name`, `status` (`draft` until a domain expert has reviewed it), `version` (semver, starting `0.1.0`), `license`, `maintainer`, `modules` (the list, in reading order), `scope` (the provisions encoded, and those not), and a `not_reviewed` note saying who has and has not read it against the source.
If some tests are meant to fail, say which file and how many under `expected_red`.

The fullest worked example is `subjects/il/hvac-work-licensing-2025/encodings/legalese/`; read its `encoding.json` and `NOTES.md` before writing your own.

## Licence terms

`SOURCE-LICENSE.md` records the terms the quoted legal text carries — not the licence of your encoding, which is Apache-2.0 like the rest of canon.
If you cannot establish the source's terms, say **undetermined** and say why; never write a grant you have not found.
An encoding that quotes the statute verbatim (as inert style does) reproduces the text, so the question is real.

## Two shared files to update in the same commit

- **`subjects/README.md`** — add a row to the table: the subject path, what it encodes, its status.
- **`NOTICE`** — add the subject's attribution entry, following the existing ones.

They drift silently if you leave them for later.

## Committing

```bash
# members of the legalese organisation
git -C <canon> switch main && git -C <canon> pull --ff-only
git -C <canon> add subjects/<jurisdiction>/<slug> subjects/README.md NOTICE
git -C <canon> commit -m "<jurisdiction>/<slug>: <what this encodes, in a line>"
git -C <canon> push origin main

# everyone else: the same commit on a branch of your fork, then
gh pr create --repo legalese/canon --base main
```

Canon has no CI of its own.
Nothing re-runs your tests after you push, so the numbers in `NOTES.md` are a point-in-time record: say which `l4` build produced them.
