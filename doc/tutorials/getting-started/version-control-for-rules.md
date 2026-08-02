# Version Control for Rules

Manage L4 rules in git: repository layout, commit discipline, review, CI, and safe redeployment.

**Prerequisites:** [Your First L4 File](first-l4-file.md), [Testing Your Rules](testing-your-rules.md), basic git

---

## Why Legal Rules Belong in Git

An `.l4` file is a legal text that happens to be executable. That makes version control more than an engineering habit:

- **The diff is the amendment.** When a threshold moves from 18 to 21, the git diff _is_ the amendment, line by line — reviewable by a lawyer, not just a programmer.
- **The history is the audit trail.** `git log` answers "what did the rule say on 3 March, and who changed it, and why" — the exact questions a regulator or court asks.
- **A tag is a version of record.** Tag the commit that was deployed; you can always re-run last year's cases against last year's rules.
- **A revert is a repeal.** Rolling back a bad change is one command, with the reversal itself on the record.

None of this works if rules live in a wiki, a shared drive, or someone's editor. Put them in a repository from day one.

---

## A Sensible Repository Layout

Keep it simple. A rules project needs little more than:

```
loan-rules/
├── README.md              # what these rules encode, which instrument, which version
├── rules/
│   ├── eligibility.l4     # one file per part/instrument, named after the source text
│   ├── repayment.l4       # rules + their §§ Tests sections (see Testing Your Rules)
│   └── shared-types.l4    # DECLAREs shared across files (IMPORTed by the others)
└── .github/
    └── workflows/
        └── check.yml      # CI: l4 check + assertions on every PR
```

Guidelines:

- **Mirror the source text.** One file per statute part or contract, with `§` sections matching the source's numbering, keeps every diff traceable to a clause.
- **Tests live with the rules.** `#ASSERT` and `#TRACE` directives are ignored by deployment, so keep each rule's tests in the same file, in a `§§ Tests` section.
- **Shared vocabulary in one place.** If several files need the same `DECLARE`s, put them in one file and `IMPORT` it (a same-directory file can be imported by name).

---

## Commit Discipline: One Legal Change per Commit

Because the diff is the amendment, cut commits along legal lines, not editing sessions:

- **One substantive change per commit.** Raising an age threshold and adding a new exemption are two amendments — two commits.
- **Separate substance from form.** Run `l4 format` in its own commit so reformatting noise never obscures a change of meaning.
- **Update the assertions in the same commit.** A rule change without its test change is an unreviewable claim.
- **Say why, cite the source.** The message should name the instrument and reason, not describe the syntax.

A well-cut commit reads like this:

```diff
 GIVEN `the applicant's age` IS A NUMBER
 GIVETH A BOOLEAN
 DECIDE `meets the qualifying age` IF
-    `the applicant's age` AT LEAST 18
+    `the applicant's age` AT LEAST 21

-#ASSERT `meets the qualifying age` 18
-#ASSERT NOT `meets the qualifying age` 17
+#ASSERT `meets the qualifying age` 21
+#ASSERT NOT `meets the qualifying age` 20
```

```
Raise qualifying age to 21 per Amendment Act 2025 s 3(b)

Effective 2025-07-01. Boundary assertions moved to the new threshold.
```

Anyone — including a reviewer who has never seen L4 — can see exactly what changed in the law and that the boundary tests moved with it.

---

## Reviewing Rule Changes

Treat a pull request on a rules repo as an amendment bill:

1. **Read the diff as law.** Does the change say what the amending instrument says — and nothing else?
2. **Check the assertions moved.** New boundary values need new `#ASSERT`s on both sides of the boundary; changed obligations need updated `#TRACE` timelines.
3. **Let CI do the mechanical part.** Reviewers should never spend attention on "does it compile".

### CI with `l4 check` and `l4 run`

A minimal GitHub Actions workflow that typechecks every rule file and fails on failed assertions:

```yaml
name: check-rules
on: [pull_request]

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # Provide the l4 binary. Build it once from the l4-ide repo
      # (cabal build jl4:l4) and cache it, or fetch a binary your team
      # publishes — whatever gets `l4` onto the PATH.
      - name: Install l4
        run: ./scripts/install-l4.sh

      - name: Typecheck all rule files
        run: |
          for f in $(git ls-files '*.l4'); do
            l4 check "$f"
          done

      - name: Run tests (fail on failed assertions)
        run: |
          status=0
          for f in $(git ls-files '*.l4'); do
            out=$(l4 run "$f" 2>&1) || status=1
            if echo "$out" | grep -q "assertion failed"; then
              echo "::error file=$f::assertion failed in $f"
              echo "$out"
              status=1
            fi
          done
          exit $status
```

Two details worth knowing:

- `l4 check` exits non-zero on any parse or type error, so the typecheck step needs no extra logic.
- `l4 run` exits non-zero on type errors and on directives that crash during evaluation, but **not** on failed assertions — a failing `#ASSERT` prints `assertion failed` while the file still typechecks. That is why the test step greps for it (alternatively, use `l4 run --json` and inspect results of `"kind": "assertion"`).

If rules use `NOW` or `TODAY`, add `--fixed-now <ISO8601>` to the `l4 run` calls so CI results do not depend on the day the job runs.

---

## Redeployment: When a Merge Changes a Live API

If your rules are deployed ([Exporting Rules for Deployment](../deploying-rules/exporting-rules-for-deployment.md)), merging to main is not the end of the story — the deployment has consumers, and its exported interface is a contract with them.

When you redeploy to an existing deployment name, the interface of the new bundle is diffed against the currently deployed one. **Backwards-compatible** changes go through silently:

- adding a new exported rule
- adding a new _optional_ parameter
- adding a new field to a result

**Breaking** changes are detected and stopped:

- removing or renaming an exported rule
- removing or renaming a parameter, or changing its type
- making a previously optional parameter required
- narrowing the accepted values of an input enum
- changing a rule's return type, removing a result field, or widening an output enum with values consumers may not handle

Both surfaces enforce this. The VS Code Deploy tab runs the check client-side and warns you before you confirm ([see the deployment tutorial](../deploying-rules/exporting-rules-for-deployment.md#updating-an-existing-deployment)); the service runs the same diff server-side on a guarded update and rejects it outright with a message listing every incompatibility:

```
Update rejected — it would break existing integrations:
  calculate premium parameter applicant.risk score removed;
  qualifies for discount return type changed from BOOLEAN to NUMBER
```

If the break is intentional, the deliberate path is to overwrite explicitly (confirming the warning in VS Code); the deployment's version number records it — the breaking component of the version is bumped, so consumers can see at a glance that the interface changed incompatibly.

Practical workflow:

- **Tag what you deploy** (`git tag deployed/insurance-premium/2025-07-01`) so the live interface always corresponds to a known commit.
- **Prefer additive evolution.** Add the new rule or optional parameter alongside the old one; retire the old one in a later, announced release.
- **Treat an intentional break like a major release**: coordinate with consumers first, then overwrite, then note the new deployment version in the PR.

---

## What You Learned

- Rule repositories make amendments reviewable, history auditable, and rollbacks trivial
- Lay out files to mirror the legal source; keep tests in the same file as the rules
- Cut commits along legal lines; update assertions in the same commit; cite the instrument
- CI: `l4 check` for validity, `l4 run` plus a grep for `assertion failed` for outcomes
- Redeployments are interface-checked: compatible changes flow through, breaking changes are rejected unless you overwrite deliberately

---

## Next Steps

- [Exporting Rules for Deployment](../deploying-rules/exporting-rules-for-deployment.md) — the deployment pipeline this page protects
- [Testing Your Rules](testing-your-rules.md) — the assertions your CI runs
- [Using the l4 CLI](l4-cli.md) — the commands behind the workflow
