# Gates Reference

SPEC.md §7.3 defines exactly two human gates in this pipeline. Everything else is autonomous. This file is about what each gate is asking a person to certify, how the machinery makes that certification hard to fake, and where its guarantees stop.

**Canonical references:**

- The gates as specified: <file:specs/todo/single-instruction-demo/SPEC.md>
- The enrolment file and its instructions: <file:specs/todo/single-instruction-demo/gate-allowed-signers>
- The default-deny check: <file:etc/go/gate-verify.sh>

---

## Contents

- [The two gates](#the-two-gates)
- [How a gate is granted](#how-a-gate-is-granted)
- [Why the signature binds to content](#why-the-signature-binds-to-content)
- [Waivers](#waivers)
- [What this machinery does not do](#what-this-machinery-does-not-do)
- [The MCP leg, which is the interesting case](#the-mcp-leg-which-is-the-interesting-case)

---

## The two gates

**HG1 — after P5, before the tests are treated as specifications.**

What it certifies: a domain expert has read the inert-style L4 against the source regulation and is satisfied it is isomorphic. This is the judgement no oracle reaches — SPEC.md §8 lists it among the conditions that are unmechanisable in principle — and it is why the gate exists rather than being replaced by a checker.

In the driver, HG1 blocks `p6-tests` and everything after it, which is every projection and the report.

**HG2 — anything outward-facing.**

What it certifies: Meng has agreed to a specific act that other people will see. SPEC.md is expansive about the scope on purpose: creating the corpus-of-law repository, publishing the conversion report, and **any** lexipedia contact including the one that follows R2's read-only probe.

In the driver, HG2 blocks `p10-publish` — which additionally refuses unconditionally today, because R1 is open — and it is the namespace under which the MCP leg refuses a non-loopback deployment.

**P2 is explicitly gate-free.** Searching is read-only and triggers no human gate. That is a ruling, not an oversight.

---

## How a gate is granted

```
etc/go/gate-request.sh HG1 --run "$TMPDIR/l4-go/<run-id>"
```

That builds a payload **from the journal** — the run id, the repo HEAD and tree state, the pinned clock, the sha256 of every corpus file, and the receipt hash of every stage that has run — writes it to the run directory, and prints the signing command:

```
ssh-keygen -Y sign -f ~/.ssh/id_ed25519 -n l4-go-gate <rundir>/HG1.payload.txt
```

The signature is made **out of band**, with a private key that never enters the worktree. `etc/go/gate-verify.sh` then runs `ssh-keygen -Y verify` against `specs/todo/single-instruction-demo/gate-allowed-signers`.

The asymmetry is the whole point: **an agent can verify a signature and cannot make one.** No new infrastructure, no network, no service — `ssh-keygen` is already on every machine this runs on.

HG2 uses the same mechanism in namespace `l4-go-gate-hg2`, so an HG1 signature cannot be replayed as an HG2 one.

### Nothing is enrolled, deliberately

`gate-allowed-signers` ships with no public key. Every gated stage therefore refuses with exit 3 and an explanation. The orchestrator does not invent an approver and does not carry a key it was not given.

---

## Why the signature binds to content

The payload is a digest of what the run has done, not a token that says "approved". Two consequences follow, and both are load-bearing:

**A post-gate edit re-opens the gate.** Touch `regcf.l4` after HG1 is granted and the corpus sha changes, so the rebuilt payload no longer matches the signed one, so `gate-verify.sh` refuses. The approval covered a specific encoding and stops covering it the moment the encoding moves.

**Re-running is cheap.** HG1 over an unchanged corpus is effectively a _standing_ signature: the payload is the same, so the same signature keeps verifying, run after run, until something it covered changes.

`gate-verify.sh` rebuilds the payload from the journal on every check rather than reading the file on disk, so a stale payload file cannot be what gets verified.

---

## Waivers

When no signer is enrolled — or when the gate genuinely does not apply to what this run is doing — the honest route is an explicit waiver, passed to the driver as `--waive HG1="<reason>"`. The invocation is in SKILL.md step 5; it is written down once, there, so there is only one copy to keep true.

A waiver **is a verdict, not an absence.** It lands on the journal as a gate record with `state: waived` and your reason, and it prints in the report's Gates section next to any signature. The report's gate table has exactly two shapes for a gate that let the run proceed: `satisfied by <signature file>` or `waived: <reason>`. There is no third shape and no way to be silent.

Three rules about writing one:

- **A waiver with no reason is refused at the command line.** The report has to be able to print something.
- **Write the reason for the person reading it a year from now**, not for the parser. It should let them decide whether the gate mattered.
- **Never waive HG2.** HG1 covers work that has usually been reviewed by other means, so waiving it during a replay is defensible. HG2 covers acts other people will see, and no agent should decide that on its own — the whole reason the gate exists is that the decision is not the agent's.

There is no `--skip-gate` and no environment override. Adding one would have to be a diff.

---

## What this machinery does not do

Stated plainly, because a security claim that overreaches is worse than none.

**The threat model is a hurried agent, not a malicious root user.** An agent with write access to this worktree can edit `gate-verify.sh`, or append a key it controls to `gate-allowed-signers`, or rewrite the journal wholesale.

Three partial mitigations, in decreasing strength:

1. **`etc/go/go.sh verify --gates`, run later by a different party.** This recomputes every verdict from the journal, re-hashes every artifact a receipt names, and checks that each granted gate was recorded _before_ the first stage it gates began. It is the only check the acting agent cannot pre-satisfy, because it happens after the run and is performed by somebody else.
2. **The hash chain.** Editing, deleting, or rewriting-and-rehashing a journal record all break it, and `render-report.mjs` prints the failure **in the report**. A laundered journal produces a report saying the journal was laundered.
3. **The diff.** Every route past a gate leaves a change in the repository — a modified verifier, a new key, an added override.

The claim this design makes is that gate circumvention is **undeniable**, not that it is **unfakeable**. Those are different, and only the first one is true.

---

## The MCP leg, which is the interesting case

Everywhere else, "this orchestrator does nothing outward-facing" is guaranteed by there being no code that could. The MCP leg breaks that: it posts a deployment to a `jl4-service`.

So the fence is explicit rather than implied:

- the deployable zip is built **locally** and hashed unconditionally — that half needs no service and is a real artifact;
- the POST target must be **loopback**. A non-loopback host is refused with exit 3 citing HG2, because deploying somewhere other people can reach is outward-facing and that is Meng's decision, not an environment variable's;
- with no `JL4_GO_SERVICE_URL`, the leg is `SKIPPED` with a named reason and the zip is still recorded;
- the deployment id carries the run id, so a re-entered or concurrent run never collides on the service side.

If a non-loopback deployment is genuinely wanted, it needs its own HG2 signature. It does not need a wider default.

---

## See also

- [phases.md](phases.md) — which stages each gate blocks
- [status-vocabulary.md](status-vocabulary.md) — how a refused gate becomes a milestone verdict
- <file:specs/todo/single-instruction-demo/ORCHESTRATOR.md> — the gate machinery as built, in the present tense
