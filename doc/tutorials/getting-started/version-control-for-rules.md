# Manage rules in git and CI

Keep L4 rules in git: repository layout, commits, review, automatic checks, and safe redeployment.

**Before you start:** [Test your rules](testing-your-rules.md), and basic git.

---

## Why legal rules belong in git

An `.l4` file is a legal text that happens to be executable. That makes version control more than an engineering habit:

- **The diff is the amendment.** When a threshold moves from 18 to 21, the git diff _is_ the amendment, line by line — reviewable by a lawyer, not just a programmer.
- **The history is the audit trail.** `git log` answers "what did the rule say on 3 March, and who changed it, and why" — the exact questions a regulator or court asks.
- **A tag is a version of record.** Tag the commit that was deployed; you can always re-run last year's cases against last year's rules.
- **A revert is a repeal.** Rolling back a bad change is one command, with the reversal itself on the record.

None of this works if rules live in a wiki, a shared drive, or someone's editor. Put them in a repository from day one.

---

## A repository layout

Keep it simple. A rules project needs little more than:

```
loan-rules/
├── README.md              # what these rules encode, which instrument, which version
├── rules/
│   ├── eligibility.l4     # one file per part/instrument, named after the source text
│   ├── repayment.l4       # rules + their §§ Tests sections
│   └── shared-types.l4    # DECLAREs shared across files (IMPORTed by the others)
└── .github/
    └── workflows/
        └── check.yml      # CI: l4 check and the tests on every pull request
```

Guidelines:

- **Mirror the source text.** One file per statute part or contract, with `§` sections matching the source's numbering, keeps every diff traceable to a clause.
- **Tests live with the rules.** Deployment publishes only the rules marked `@export`, so keep each rule's tests in the same file, in a `§§ Tests` section.
- **Shared vocabulary in one place.** If several files need the same `DECLARE`s, put them in one file and `IMPORT` it (a same-directory file can be imported by name).

---

## One legal change per commit

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

## Review rule changes

Treat a pull request on a rules repo as an amendment bill:

1. **Read the diff as law.** Does the change say what the amending instrument says — and nothing else?
2. **Check the assertions moved.** New boundary values need new `#ASSERT`s on both sides of the boundary; changed obligations need updated `#TRACE` timelines.
3. **Let CI do the mechanical part.** Reviewers should never spend attention on "does it compile".

## Check every change in CI

This GitHub Actions workflow type-checks every rule file and fails when an assertion fails. It takes the `l4` binary from the Linux build of the VS Code extension, which is attached to each `l4-ide-build-…` release of [legalese/l4-ide](https://github.com/legalese/l4-ide/releases):

```yaml
name: check-rules
on: [pull_request]

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install l4
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          tag=$(gh release list --repo legalese/l4-ide --limit 50 --json tagName \
                  --jq '[.[] | select(.tagName | startswith("l4-ide-build-"))][0].tagName')
          gh release download "$tag" --repo legalese/l4-ide \
            --pattern 'l4-vscode-linux-x64-*.vsix' --output l4.vsix
          mkdir -p "$HOME/.local/bin"
          unzip -j l4.vsix 'extension/bin/linux-x64/l4' -d "$HOME/.local/bin"
          chmod +x "$HOME/.local/bin/l4"
          echo "$HOME/.local/bin" >> "$GITHUB_PATH"

      - name: Typecheck all rule files
        run: |
          for f in $(git ls-files '*.l4'); do
            l4 check "$f"
          done

      - name: Run tests (fail on failed assertions and on assertions that cannot be evaluated)
        run: |
          status=0
          for f in $(git ls-files '*.l4'); do
            if ! out=$(l4 run "$f" 2>&1); then
              echo "::error file=$f::l4 run failed for $f (a type error, or a directive that could not be evaluated)"
              echo "$out"
              status=1
            elif echo "$out" | grep -q "assertion failed"; then
              echo "::error file=$f::assertion failed in $f"
              echo "$out"
              status=1
            fi
          done
          exit $status
```

To pin a version, replace the `tag=$(...)` line with a fixed tag, such as `tag=l4-ide-build-95`. To build `l4` from source instead, see [Using the l4 CLI](l4-cli.md).

Two details worth knowing:

- `l4 check` exits non-zero on any parse or type error, so the typecheck step needs no extra logic.
- `l4 run` exits non-zero on type errors and on directives that crash during evaluation (an `#ASSERT` whose expression raises is one), but **not** on failed assertions — a failing `#ASSERT` prints `assertion failed` while the file still typechecks. That is why the test step checks two things: the exit code, which catches the type errors and the assertions that could not be evaluated, and a grep for `assertion failed`, which catches the verdicts (alternatively, use `l4 run --json` and inspect results of `"kind": "assertion"`).

If rules use `NOW` or `TODAY`, add `--fixed-now <ISO8601>` to the `l4 run` calls so CI results do not depend on the day the job runs.

---

## Redeploy when a merge changes a live API

If your rules are deployed ([Deploy your rules](../deploying-rules/exporting-rules-for-deployment.md)), merging to main is not the end of the story — the deployment has consumers, and its exported interface is a contract with them.

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

Both surfaces enforce this. The VS Code Deploy tab runs the check client-side and warns you before you confirm ([Update a deployment](../deploying-rules/exporting-rules-for-deployment.md#update-a-deployment)); the service runs the same diff server-side on a guarded update and rejects it outright with a message listing every incompatibility:

```
Update rejected — it would break existing integrations:
  calculate premium parameter applicant.risk score removed;
  qualifies for discount return type changed from BOOLEAN to NUMBER
```

If the break is intentional, overwrite explicitly: confirm the warning in VS Code, or run `l4 redeploy --force`. The deployment's version number records it — the breaking component of the version is bumped, so consumers can see at a glance that the interface changed incompatibly.

Practical workflow:

- **Tag what you deploy** (`git tag deployed/insurance-premium/2025-07-01`) so the live interface always corresponds to a known commit.
- **Prefer additive evolution.** Add the new rule or optional parameter alongside the old one; retire the old one in a later, announced release.
- **Treat an intentional break like a major release**: coordinate with consumers first, then overwrite, then note the new deployment version in the PR.

---

## Next steps

- [Test your rules](testing-your-rules.md): the assertions your CI runs.
- [Deploy your rules](../deploying-rules/exporting-rules-for-deployment.md): the deployment this page protects.
- [Using the l4 CLI](l4-cli.md): every command used in the workflow.
