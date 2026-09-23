# Four sentences do not determine an implementation

A differential reading of Heydari & Leowald (2026), _Closing the Loop_, Part III.A, against
BGB §§ 186–193 — the German statutory rules for computing deadlines.

## The result

Part III.A describes German deadline calculation in four sentences of prose and reports that a
verification kernel discharges it. We encoded those four sentences in L4 alongside an
isomorphic encoding of the statute itself, and ran both arms over the same inputs.

**The prose admits at least three implementations, and they disagree by up to four days.**

One trigger — an event on 30 January 2026, a one-month period, a bare legal consequence,
Berlin — produces three different answers depending on how one reads the same four sentences:

| reading                                            | answer               |
| -------------------------------------------------- | -------------------- |
| the statute (BGB §§ 187(1), 188(2) Alt. 1, 188(3)) | **28 February 2026** |
| Part III.A, read charitably                        | **27 February 2026** |
| Part III.A, read literally                         | **2 March 2026**     |

That spread is three days. The widest is four, and the model prints it too: move the event to
28 February 2026 (`Beispiel 6d`, everything else unchanged) and the same three readings give
**28 March**, **31 March** and **1 April 2026**.

That is the finding. The off-by-one against the statute is a consequence of it, not the
argument: the argument is that the description is _under-determined_, and that a reader who
implements it faithfully cannot know which of the three they have built.

The fixture that separates all three is `Beispiel 6c` in the model. It matters that the
Gegenstand is a bare legal consequence rather than a performance: with a performance, the
literal reading lands on Saturday 28 February, § 193 carries it to Monday 2 March, and it
coincides with the statute _by accident_. Changing the Gegenstand removes § 193 from the
statutory arm while the paper's unconditional § 193 stays on the paper's arm, and the three
separate.

## What else the differential found

Running the two arms over every day of 2026 (a one-month Ereignisfrist, performance due,
Berlin):

- **12 days of 365 diverge before § 193 is applied.** Not the month-ends a reviewer expects.
  31 January does _not_ diverge; 31 March, 31 May, 31 July, 31 August, 31 October and
  31 December do not either. The divergent set is 28, 29, 30 January; 28 February; 30 March;
  30 April; 30 May; 30 June; 30 August; 30 September; 30 October; 30 November. **28 February
  diverges by three days** — statute 28 March, paper 31 March.
- **10 of those 12 survive § 193** and reach the user as a wrong date.

The cause is that § 188(3)'s clamp **does not commute with § 187's shift**. The statute clamps
the day derived from the _event date_; the paper's pipeline ("compute the start date, then add
the duration, rounding mode DOWN") clamps a day derived from the _shifted start_. Whichever arm
clamps is the arm that loses days, so the divergence has **two shapes, not one**:

- **the paper is one day EARLY on seven of the twelve** — 28, 29 and 30 January, 30 March,
  30 May, 30 August, 30 October. The statute clamps here and the paper does not.
- **the paper is one to three days LATE on the other five** — 28 February (by three), 30 April,
  30 June, 30 September, 30 November (by one). The paper clamps here and the statute does not.

Only the first group runs in the dangerous direction — a deadline reported earlier than the law
allows is a missed deadline waiting to happen, and that is the malpractice case. The second
group is the mirror error and is merely wrong. An earlier draft of this page said the paper was
short by a day for _every_ event on the 29th, 30th or 31st; the model's own sweep falsifies that
in three separate ways, and 31 January — the day a reviewer expects to diverge — does not
diverge at all.

## The other claims in Part III.A

Twelve verdicts of three different evidentiary kinds. The third column says which is which,
because without it they read alike — and reading an argued verdict as a measured one is the
paper's own mistake. **evaluated** means a fixture in the model prints the number; **type model**
means the language's exhaustiveness checker carries it; **argued** means we read the statute and
say so, with no fixture behind it.

| the paper's claim                                                                                            | verdict                                                                                                                                                                                                                                                                                                | how we know                                                                                                                                        |
| ------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| "German deadline calculation has four components"                                                            | **Incomplete.** At least nine operative rules across eight sections. §§ 188(1), 189(1), 189(2), 190, 191, 192 are each absent, and each breaks the paper's single "duration" parameter differently.                                                                                                    | argued; each missing rule is then encoded and exercised (Beispiel 1, 12, 13, 14, 15)                                                               |
| "an event-triggered period begins the day after the event; a date-triggered period begins on the named date" | **Effect right, condition wrong.** § 187(2)'s trigger is that _the beginning of a day_ is decisive, not that a date is named. A 14:00 delivery on a known date is § 187(1).                                                                                                                            | argued only — nothing in the model separates "is a date named?" from "is the beginning of a day decisive?", because both readings are inputs to it |
| — and § 187(2) sentence 2 (the day of birth)                                                                 | **Materially omitted.** It is the carrier of the majority-age cases.                                                                                                                                                                                                                                   | argued; the effect is evaluated (Beispiel 9, 9b)                                                                                                   |
| "the period ends on the day corresponding to the day preceding the trigger"                                  | **Wrong, and not fixable by one rule.** § 188(2) has two branches with two _different_ reference days, only one of which subtracts. The same date yields 1 April or 31 March depending on the branch.                                                                                                  | evaluated — Beispiel 3a against 3b, one trigger date, two answers                                                                                  |
| "if the corresponding day does not exist … the period ends on the last day of that month"                    | **Right as stated, wrong where applied** (see above), and unscoped: § 188(3) reaches only month-determined periods, never weeks.                                                                                                                                                                       | evaluated for the clamp (Beispiel 4, 5, 6, 16); argued for the scope                                                                               |
| "deadlines falling on Sundays, public holidays, or Saturdays extend to the next working day"                 | **Over-broad.** § 193 has a precondition — a declaration of intent must be made or a performance rendered. Where a legal effect merely occurs, it does not apply. That the courts reached limitation periods only _by analogy_ (BGH III ZR 146/07) is direct evidence the precondition is real.        | evaluated in both directions — Beispiel 10 against 10b on one trigger date, plus 9 and 11                                                          |
| "the working-day shift parameterized by jurisdiction"                                                        | **The parameter is a _place_, sometimes two, not a jurisdiction.** § 193's hook is _am Erklärungs- oder Leistungsort_, which may be neither party's domicile nor the forum. Two obligations under one contract can shift on different dates.                                                           | evaluated — Beispiel 8a against 8b, and 8c against 8c in Berlin                                                                                    |
| "the base case is § 187(1), the exception § 187(2), exactly one applies"                                     | **True, and the one claim here that is discharged outright** rather than sampled — the constructor domain is finite and enumerable.                                                                                                                                                                    | evaluated exhaustively, backed by the type model: a fourth constructor makes the dispatch non-exhaustive, and that diagnostic reaches the golden   |
| "the kernel verifies this statically"                                                                        | **True of the dispatch, false of the classification.** Whether _this_ period is an Ereignis- or a Beginnfrist is an interpretive question under § 186, and it is where practitioners actually go wrong.                                                                                                | argued — and the model makes it visible by carrying the classification as an input field rather than deriving it                                   |
| "the kernel verifies for all inputs that deadline > trigger"                                                 | **False as stated, at date granularity.** A one-day Beginnfrist ends _on_ the trigger day.                                                                                                                                                                                                             | evaluated — `Gegenbeispiel zu I1`                                                                                                                  |
| — the repaired `deadline ≥ trigger`                                                                          | **Holds within the default § 186 regime, and is false outside it.** Where the instrument fixes an earlier day, the statutory computation is displaced and the comparison is about a computation that did not determine the answer.                                                                     | evaluated over two 365-day sweeps (Ereignis- and Beginnfrist, 2026); the boundary is pinned red by `Beispiel 17b`                                  |
| "… and deadline ≥ raw_deadline"                                                                              | **True by construction within the default § 186 regime**, and false outside it, for the same reason. Inside it: the § 193 roll's base case returns its argument and every recursive call moves forward one day. That is a structural argument, corroborated by the sweeps, **not discharged by them.** | argued structurally; sampled by the two sweeps; boundary pinned red by `Beispiel 17b`                                                              |
| "… and that the calculations are correct"                                                                    | **Not discharged, by us or by them.**                                                                                                                                                                                                                                                                  | —                                                                                                                                                  |

## What our own encoding cannot do

Stated here because a reader finds these out anyway, and the only question is whether they find
out from us or from a wrong answer in production. The full list is the `§§ Grenzen` block at the
foot of the model.

1. **It cannot classify.** The § 187 limb and the § 193 Gegenstand are interpretive inputs under
   § 186. We make that visible — they are input fields — rather than fix it.
2. **`DATE` is day-granular.** Every field names a day, not an instant. This is exactly why the
   paper's I1 is false as stated.
3. **Sub-Land holidays are unreachable.** Mariä Himmelfahrt in Bavaria, Fronleichnam in parts of
   Saxony and Thuringia, the Augsburger Friedensfest. Those pairs set a
   `die Feiertagsangabe ist gesichert` flag to FALSE rather than answering — but **nothing forces
   a caller to read that flag.** This is the model's one remaining wrong-answer-with-exit-0 path.
   The ceiling here is _auditable_, not checkable, and saying so is more honest than claiming
   otherwise.
4. **The calendar's time axis is only partly modelled.** Four post-2017 introductions are
   year-gated; the rest of the table is as at 2026-09-14 and pre-2000 is outside the window.
5. **§ 193's analogy is a stipulation, not a derivation.** L4 has no analogy; every future
   analogical extension is a code change.
6. **§ 186's defeasance seam is coarse.** One optional date can say "the instrument fixes a
   different day". It cannot say "a different _regime_ applies" — § 222 ZPO, § 31 VwVfG and
   Regulation (EEC, Euratom) No 1182/71 all differ. It also cannot say "and § 193 is displaced
   too". We ruled that a stipulated day displaces the §§ 187–189 _computation_ and **not**
   § 193, because the stipulated day is precisely the _bestimmter Tag_ § 193 governs — and
   because the model's own Termin path already routes an identical question through § 193, so
   the other reading would make one file answer the same legal question two ways. Displacing
   § 193 as well needs a further finding (the parties fixed an exact moment) and a second field
   the model does not have. `Beispiel 17` fixes a performance on Sunday 15 March 2026 and the
   model answers Monday 16 March.
7. **Nothing here but the § 187 exhaustiveness check is a proof.** That one is discharged
   completely because its domain is finite. Everything else is a bounded check over a stated
   window, or a structural argument L4 cannot state.

On the last point, one mechanism deserves to be named precisely, because a reader who assumes
otherwise will be wrong in public: **the exhaustiveness diagnostic is a warning, not an error, so
`l4 check` does not exit non-zero on it.** The enforcement lives in the test suite, which
captures the diagnostic transcript into a golden file. `fristbeginn-nonexhaustive-control.l4` is
the same rule with one arm deleted; it exists so that a clean run of the main model is _evidence_
that the checker was looking, rather than merely consistent with it.

## The SMT rung, named and out of scope

To prove the repaired invariants over the unbounded domain — rather than over one sampled year —
needs linear integer arithmetic over day serials plus `add months` encoded as a finite case split
(days-in-month is a twelve-way conditional with a leap sub-case). Under that encoding the clamp's
non-commutation becomes _provable_ rather than sampled. Target Z3; the in-tree shape precedent is
`paper/formal-methods-in-law/the-letter-and-the-spirit/cheating-415-surplusage.z3.py`. Naming it
precisely is in scope here; building it is not.

We also ran `l4 verify` and report the result for what it is. **Measured on this model on
2026-09-14: zero findings — 15 decisions analysed, 72 skipped, 16 further decisions nested in a
`WHERE` clause not visited at all, and the largest formula it built had 2 atoms.**
Every decision that returns a date is skipped outright ("Can only visualize, as a ladder diagram, a
DECIDE that returns a boolean"), which is most of the statute; every date comparison and every
`add months` is an opaque atom; and each decision is read on its own, so a call to another decision
is a leaf rather than an inlined body. A clean result from it is the weak statement its own
`--help` footer insists it is — _"in a corpus written as many small named limbs — which is the
house style — that is most of the corpus, and it is why a clean run over such a file is a weak
statement"_ — and we do not dress it up as more. It did not touch the off-by-one, and could not
have.

## Files

**Model of record:** [`jl4/examples/ok/closing-the-loop/fristberechnung.l4`](../../jl4/examples/ok/closing-the-loop/fristberechnung.l4)

| file                                                                                                                  | what it is                                                                      |
| --------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| [`fristberechnung.l4`](../../jl4/examples/ok/closing-the-loop/fristberechnung.l4)                                     | the statute, the paper's arm, the fixtures, the invariants and the sweeps       |
| [`feiertage.l4`](../../jl4/examples/ok/closing-the-loop/feiertage.l4)                                                 | the German holiday calendar — computus, sixteen Länder, year-gated              |
| [`fristbeginn-nonexhaustive-control.l4`](../../jl4/examples/ok/closing-the-loop/fristbeginn-nonexhaustive-control.l4) | the control fixture that makes a clean run mean something                       |
| [`REPRODUCE.md`](REPRODUCE.md)                                                                                        | every computational claim above, mapped to the command that produces it         |
| [`reproduce.sh`](reproduce.sh)                                                                                        | runs them                                                                       |
| [`SIDEBAR-intuitionism.md`](SIDEBAR-intuitionism.md)                                                                  | why a trace is the answer rather than a report about it — conceptual, unsourced |

These are linked, not copied. A second copy of a model is a claim with no way to learn it was
corrected.

## Sources

German statutory text from [gesetze-im-internet.de](https://www.gesetze-im-internet.de/bgb/) and
[dejure.org](https://dejure.org/gesetze/BGB/); official English from the
[Federal Ministry of Justice translation](https://www.gesetze-im-internet.de/englisch_bgb/englisch_bgb.html).
BGH, Urt. v. 6.12.2007 – III ZR 146/07 via [lexetius.com](https://lexetius.com/2007,3949).
Holiday tables checked against the sixteen Landesfeiertagsgesetze via
[de.wikipedia.org/wiki/Gesetzliche_Feiertage_in_Deutschland](https://de.wikipedia.org/wiki/Gesetzliche_Feiertage_in_Deutschland)
and [de.wikipedia.org/wiki/Reformationstag](https://de.wikipedia.org/wiki/Reformationstag),
retrieved 2026-09-14. Easter cross-checked against the Gauss computus for 2015–2035.
