# The Singularity Needs a Compiler

### A chapter proposal for _Beyond Superjustice_

_Drafted 2026-09-21. **Not sent.** Nothing in this directory has been communicated to Becher, Alarie, OUP, or the Creative Destruction Lab._
_Target: the _Beyond Superjustice_ response volume edited by Samuel I. Becher (City University of Hong Kong) and Benjamin Alarie (University of Toronto), with workshops on 18–19 March 2027 at CityU and 25–26 May 2027 at Toronto. No call for papers has been published; see [`../README.md`](../README.md) §Venues and deadlines._

---

## Abstract (150 words)

_Superjustice_ and its predecessors describe a legal order that is simultaneously more complex in specification and more knowable in operation.
Those two properties do not arrive together.
Complexity of specification requires no enabling technology; legislatures and drafting offices produce it for free, and adhesion contracts produce it faster.
Knowability requires a compiler, and the Becher–Alarie corpus never names one.
This chapter takes the authors' own definition of the legal singularity — "once found, the facts will map on to clear legal consequences" — and reads it as a type signature, `Facts → Consequences`.
Statistical prediction does not inhabit that type; it computes a distribution over what a tribunal would do, which cannot be appealed, diffed against an amendment, or interrogated for a defect.
Drawing on a decade of building L4, a typed functional language for legal rules, we argue that each of the three pathways in _Legal Order in the Age of AI Agents_ presupposes a shared computable artifact, and we report where, measurably, law stops being computable.

## The argument, in four moves

1. **The concession is in the text.** The singularity is defined as a state "at once extraordinarily more complex in its specification than it is today, and yet operationally vastly more knowable." Both halves are asserted; only one is mechanised. We separate them and show the failure mode where the first arrives alone: a rule system the subject cannot read *and* a probability they cannot appeal, which is worse than the present.

2. **The definition is a type, and prediction does not inhabit it.** `Facts → Consequences` is a function. A predictor computes `Facts → Distribution Outcome`. There is no total map from the second to the first that does not introduce an unwritten decision rule — and a decision rule about legal consequence is itself law, unpromulgated and unreviewable. The practical corollaries are the ones institutions feel: you cannot appeal a distribution, version one against a commencement date, or locate a drafting defect inside one.

3. **The jurisprudence is older than the technology.** Functional completeness is Dworkin's one-right-answer thesis with better hardware, and it inherits Dworkin's exposure to Hart. More data closes an epistemic gap and nothing closes a semantic one. We make this precise rather than rhetorical: the obstruction is **non-monotonicity**, not Gödel. Legal reasoning retracts conclusions when facts are added; "notwithstanding anything to the contrary" is the drafting profession's standing admission that the set of defeating facts cannot be closed in advance.

4. **We can report where the boundary actually is, because we built the instrument.** L4 type-checks quantified obligations but does not yet evaluate them; `SUBJECT TO` and `NOTWITHSTANDING` remain analysis-only behind a 1,788-line specification whose sole ruling to date is that the syntax is not ready to be spelled. These are not complaints about our implementation. They are the first empirical boundary markers for the computable fraction of law, and they are the sort of thing only a builder can report.

## What the chapter contributes that the volume otherwise will not

Most responses to a book of this kind will be normative — bias, legitimacy, the professional monopoly, access to justice.
Ours is **constructive and falsifiable**.
We bring artifacts rather than positions: a deontic race condition found by a model checker in live secondary legislation; an ambiguity in a commercial insurer's payout formula; a `NOT`-scoping defect that awarded a widow an entire estate where the Intestate Succession Act gives her half.
Each is a found defect, checkable by any reader against the source.
The chapter's constructive claim follows from them: **the singularity, if it arrives, will not be a prediction engine but a compiler, a verifier, and a standard library — and we can say how much of that exists today.**

## Fit, and a declared interest

The book's own objection O5 identifies privatisation of law as a transformative challenge and lists open-source alternatives among the remedies.
L4 is open-source, and the chapter argues that this is the load-bearing property rather than a licensing preference.
We declare the interest plainly: the authors of this chapter build the tool the chapter argues is missing.
The argument is therefore offered as an interested party's submission — the same disclosure posture the authors themselves adopt on `superjustice.com/for-ai` — and it is constructed so that every empirical claim in it can be checked without taking our word for anything.

## Open questions before this is sent

- No CFP exists. The route is direct contact with the editors, or via the CDL reading group; **which, and when, is Meng's call.**
- Which of the two workshops to target. CityU (March) is Becher's institution and comes first; Toronto (May) is Alarie's and is nearer the NUS visit.
- Whether to lead with the type-signature argument or the boundary-markers report. The first is more provocative; the second is more defensible and is uniquely ours.
