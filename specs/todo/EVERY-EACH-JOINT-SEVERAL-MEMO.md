# JOINTLY / SEVERALLY as names for the barrier / fork quantifiers

**For:** the L4 language designer, ruling on `EVERY-EACH-QUANTIFIER-SPEC.md` §2.2.6
**Date:** 2026-09-06
**Question:** should the barrier (join) and fork (distributive) semantics be spelled `JOINTLY` and
`SEVERALLY` instead of `EVERY` and `EACH`?

---

## 0. Recommendation in one paragraph

**No.** The joint/several distinction in common-law doctrine is not the barrier/fork distinction; it
is a distinction about _remedy and procedure_ — whom the creditor may sue, in what action, and what
discharges whom — and on the one axis where it does touch performance it says the **opposite** of
what L4's barrier says: under a joint obligation, performance by one promisor discharges the others
(Restatement (Second) of Contracts § 293), whereas under L4's `EVERY` barrier a performance by one
inhabitant leaves everyone else's obligation intact and unperformed inhabitants are blamed (spec
§6.1). Civil law inverts the word again — Louisiana Civil Code art. 1788 defines a _joint_ obligation
as one where "neither is bound for the whole", the reverse of the common-law sense. And the leading
contract-drafting authority, Ken Adams, has publicly retired all three terms as "ill understood…
more trouble than they're worth". Adopting them as keywords buys a false familiarity and pays for it
with four separate false friends. §7 proposes what to do instead; §7.4 gives the definitional
sentence to use if the words are adopted anyway.

---

## 1. What _joint_, _several_, and _joint and several_ actually mean

### 1.1 The black-letter axis is "same performance or separate performances"

Restatement (Second) of Contracts **§ 288** (verified against the 1981 text)¹:

> **§ 288. Promises of the Same Performance**
> (1) Where two or more parties to a contract make a promise or promises to the same promisee, the
> manifested intention of the parties determines whether they promise that the same performance or
> separate performances shall be given.
> (2) Unless a contrary intention is manifested, a promise by two or more promisors is a promise
> that the same performance shall be given.

Note what the black letter does **not** do: it never uses the words _joint_ or _several_. The axis it
draws is **same performance vs separate performances**. That axis is the closest thing in the
doctrine to L4's distinction, and it is worth keeping in view — but the words the spec proposes to
borrow are attached to a _different_ question, downstream of this one.

Williston, quoted by Adams (see §2), states the classical definitions:

> Copromisors are liable "jointly" if all of them have promised the entire performance which is the
> subject of the contract. The effect of a joint obligation is that each joint promisor is liable
> for the whole performance jointly assumed. […]
> When a "several" obligation is entered into by two or more parties in one instrument, it is the
> same as though each has executed separate instruments. Under these circumstances, each party is
> bound separately for the performance which he or she promises, and is not bound jointly with
> anyone else.
> A "joint and several" contract is a contract with each promisor and a joint contract with all […]
>
> — _Williston on Contracts_ § 36:1 (4th ed.), quoted in Ken Adams, "Exploring 'Joint and
> Several'", adamsdrafting.com, rev. 30 April 2012

So: **joint = each liable for the _whole_ performance, under one obligation.** That already conflicts
with the reading proposed in the spec ("discharged only when all perform").

### 1.2 The distinction the words actually carry is remedial and procedural

Adams reports that Restatement § 288 says "the distinction between 'joint' and 'several' duties is
primarily remedial and procedural." I have **not** independently verified that sentence against the
official comment: the copy of the Restatement I could obtain carries only black letter for §§ 288,
293 and 294, not the comments.² Treat it as Adams's quotation, not as verified primary text. It is
consistent with everything else below.

The procedural content, in Adams's own words:

> The procedural distinction is that if A and B are only jointly liable and not severally liable,
> failure to join both A and B in a suit for recovery might subject you to dismissal (or at least a
> lengthy argument on the subject). If A and B are severally liable, you can proceed against one
> without the other.

That is: joinder. Nothing about sequencing, completion, or what happens next.

Singapore and English authority put the same idea as **unity of the cause of action**. In _Park
Regis Hospitality Management Sdn Bhd v British Malayan Trustees Ltd_ [2013] SGHC 268, the court
quotes _Duck v Mayeu_ [1892] 2 QB 511 at 513 (Smith LJ):

> … a release granted to one joint tortfeasor, or to one joint debtor, operates as a discharge of the
> other joint tortfeasor, or the other joint debtor, the reason being that the cause of action, which
> is one and indivisible, having been released, all persons otherwise liable thereto are consequently
> released.

and Neill LJ's summary that "joint liability whether in contract or tort gave rise to a single cause
of action and that accordingly the release of one joint promisor or one tortfeasor discharged any
other persons jointly liable." Applied to guarantors in Singapore: _Industrial and Commercial Bank
Ltd v Li Soon Development Pte Ltd_ [1993] 3 SLR(R) 518 at [68] — release of one joint or joint-and-
several guarantor discharges all, absent a reservation of rights.

### 1.3 The four doctrinal consequences, and whether they matter computationally

| doctrinal consequence of _joint_                                                                                 | source                                                                                                                                         | bearing on a computational semantics                                                                                                                                                                                                                                                                                                                   |
| ---------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Vicarious discharge**: performance or satisfaction by one promisor discharges the others to the extent applied | Restatement § 293 (verified)                                                                                                                   | **Fatal to the mapping.** L4's barrier requires _every_ inhabitant to perform; §6.1 blames exactly the non-completers. Doctrine says one payer clears the rest. The word asserts the opposite of the construct.                                                                                                                                        |
| **Release of one discharges all**                                                                                | _Duck v Mayeu_; _ICB_ [1993] 3 SLR(R) 518 at [68]; Restatement § 294(1)(a) (verified)                                                          | A barrier has no operation that discharges the whole obligation by excusing one participant. This is a real expressive gap, not just a naming one.                                                                                                                                                                                                     |
| **Joinder / merger** — suing one bars or does not bar suing the rest                                             | UK Civil Liability (Contribution) Act 1978 s. 3; Singapore Civil Law Act s. 17, "borrowed from s 3 of the UK Act" per [2013] SGHC 268 at [62]³ | Purely procedural. No computational analogue. It is the bulk of what the words carry.                                                                                                                                                                                                                                                                  |
| **Survivorship / death of one obligor**; **contribution between obligors**                                       | Civil Liability (Contribution) Act 1978 s. 1; LCC art. 1804 ("virile portion"); French C. civ. art. 1317                                       | Contribution belongs to Pattern C only. Survivorship is worth a separate note: **it raises a question §13 of the spec does not list** — what happens to an armed barrier when the inhabitant set changes after arming? Doctrine's answer for joint obligations (liability survives against the survivors) is a real design option L4 has not ruled on. |

### 1.4 Default rules point in opposite directions

- **Common law**: Restatement § 288(2) — silence means **same performance** (i.e. the joint reading).
- **Civil law**: French Code civil art. 1309 — "An obligation binding multiple creditors or debtors is
  **divided by operation of law** as between them… Each creditor is entitled to only his share of the
  joint right; each debtor is liable for only his share of the joint debt." Art. 1310: solidarity
  "cannot be presumed."⁴ Louisiana art. 1796 to the same effect.

A reader's default expectation for a bare quantifier therefore depends on their training.

---

## 2. What drafting practice thinks the words mean

**Ken Adams is the most useful witness here, and he is against the words.** Two posts, quoted at
length because the parent asked for quotation rather than paraphrase.

From the 2007 post "Joint and Several" (adamsdrafting.com/joint-and-several/):

> But _joint and several_ applies to liability. According to _Black's Law Dictionary_, it means that
> a given liability can be apportioned equally among the members of a group or can instead, to a
> greater extent or entirely, be laid at the door of one or more select members of the group, at the
> discretion of whoever is apportioning the liability. […] It's unnecessary—in fact illogical—to seek
> to make other obligations, or representations, joint and several.

From "Exploring 'Joint and Several'" (rev. 26 and 30 April 2012), which supersedes it — Adams's own
framing is "it doesn't begin to adequately address the real issues, which turn out to be messy. It's
time for a serious rethink":

> Here's an example of a joint obligation: **A and B shall pay C $100.** And here's an example of
> several obligations: **A shall pay C $50 and B shall pay C $50.** You don't have to use the word
> _joint_ to create joint obligations or the word _several_ to create several obligations.

> The labels _joint_, _several_, and _joint and several_ are terms of art (or jargon, depending on
> your perspective), and they're **ill understood**. (At least, I didn't understand them!)

> Furthermore, the word _joint_ is subsumed by _several_—if you're able to go after each obligor
> separately, it follows that you can go after them all. So nothing is accomplished by using the
> phrase _joint and several_. […] So although in a previous version of this post I said that I was
> inclined to keep _joint and several_, in whatever combination, because getting rid of them would
> likely "make people nervous," **I've now decided that they're more trouble than they're worth.**

He then gives replacement language that uses none of the three words:

> Acme may elect to recover from any one or more WidgetCo Entities the full amount of any collective
> liability of the WidgetCo Entities under this agreement, and Acme may bring a separate action
> against any one or more WidgetCo Entities with respect to any such liability.

He cites **MSCD §§ 13.350–13.361** for the extended treatment (per his other posts, e.g. "When More
Than One Party Makes a Given Set of Representations"). I could not obtain the MSCD text itself — see
§8.

Two things follow that bear directly on the ruling.

1. **Adams's own example of "several" is a _divided_ payload** — $50 each, not $100 each. L4's fork
   _replicates_ the same obligation across every inhabitant. So even the practitioner-facing example
   of "several" is not the fork.
2. **The leading style authority is retiring these words.** Making them L4 keywords means teaching
   beginners a vocabulary that the reference work on contract drafting tells professionals to stop
   using.

**Garner: not found.** I could not obtain the _Garner's Dictionary of Legal Usage_ entry for "joint
and several" / "jointly and severally", nor the _Black's_ entry in its own words; Adams's summary of
_Black's_ above is the closest I have, and it is a paraphrase by him, not a quotation of _Black's_.

**Cornell LII (Wex)**, as a lowest-common-denominator practice statement: "When two or more parties
are jointly and severally liable for a tortious act, each party is independently liable for the full
extent of the injuries stemming from the tortious act." Wex gives no separate entries for joint
liability and several liability. This is Pattern C, not the barrier and not the fork.

---

## 3. Civil law: a genuinely cleaner three-way split — which is why the false friend is worse

Louisiana codifies the taxonomy explicitly, and its terms line up with L4's patterns almost exactly
— but its word _joint_ is **not** the common-law _joint_.

> **Art. 1786.** When an obligation binds more than one obligor to one obligee […] the obligation may
> be several, joint, or solidary.
>
> **Art. 1787.** When each of different obligors owes a **separate performance** to one obligee, the
> obligation is **several** for the obligors. […] A several obligation produces the same effects as a
> separate obligation owed […] by each obligor to an obligee.
>
> **Art. 1788.** When different obligors owe together **just one performance** to one obligee, **but
> neither is bound for the whole**, the obligation is **joint** for the obligors.
>
> **Art. 1789.** When a joint obligation is divisible, each joint obligor is bound to perform […]
> only his portion. When a joint obligation is indivisible, joint obligors […] are subject to the
> rules governing solidary obligors.
>
> **Art. 1794.** An obligation is **solidary** for the obligors when each obligor is liable for the
> whole performance. A performance rendered by one of the solidary obligors relieves the others of
> liability toward the obligee.
>
> **Art. 1815.** An obligation is **divisible** when the object of the performance is susceptible of
> division. An obligation is **indivisible** when the object […] is not susceptible of division.
>
> **Art. 1818.** An indivisible obligation with more than one obligor or obligee is subject to the
> rules governing solidary obligations.
>
> — Louisiana Civil Code, Acts 1984, No. 331 §1, via LSU Law's Louisiana Civil Code Online

French law, in the Ministry of Justice's own English translation of the 2016 reform:⁴

> **Art. 1313.** The joint and several nature of an obligation amongst debtors imposes on each of
> them an obligation for the whole of the debt. Satisfaction by one of them discharges them all as
> regards the creditor.
>
> **Art. 1320.** Where an act of performance is **indivisible**, either by its nature or by the terms
> of the contract, each creditor of the obligation may require and receive satisfaction in full […]
> Each of the debtors of such an obligation is bound to the whole […]

Two observations:

- **The civil-law taxonomy maps to L4's four patterns better than the common-law one does**:
  _several_ (art. 1787, separate performances) → fork; _joint/divided_ (arts. 1788–1789, one
  performance, portions) → barrier; _solidary_ (art. 1794) → Pattern C; _indivisible_ (art. 1815, 1320) → Pattern D. That is a four-for-four fit, and it is not a coincidence: the civilian
  taxonomy was built to classify the _structure_ of the obligation, while the common-law one was
  built to sort out _procedure_.
- **But "joint" flips sign between the two systems.** Common law: each joint promisor is liable for
  the whole (Williston). Louisiana: "neither is bound for the whole" (art. 1788). And the official
  French translation renders _solidaire_ as "joint and several", so a comparative reader meets
  "joint" attached to the each-for-the-whole idea in one breath and to the none-for-the-whole idea
  in the next. Any L4 documentation using `JOINTLY` acquires this problem for free.

---

## 4. Formal and computational treatments

### 4.1 Deontic logic and MAS: the vocabulary is _collective_ vs _distributive_, and L4's barrier is neither cleanly

The established pair is **collective** vs **distributive** obligation. Garion & Cholvy, "Deriving
individual obligations from collective obligations" (Dagstuhl Seminar Proceedings 07122, Normative
Multi-agent Systems, 2007), summarising Royakkers & Dignum and Norman & Reed:

> According to Royakkers and Dignum, a collective obligation is an obligation directed to a group of
> individuals […] A collective obligation addressed to a group of agents is such that this group, as
> a whole, is obliged to achieve a given task. […] one must notice that in the example, the mother
> does not oblige each of her boys to set the table. This shows the difference between collective
> obligations and what Royakkers and Dignum call "restricted general obligations" which are addressed
> to every member of the group. […] Norman and Reed use the terms **collective group** and
> **distributive group** to make this distinction. If distributive, a group is addressed
> distributively ("Boys, you have to eat properly"); if collective, a group is being addressed as a
> collective ("Boys, you have to set the table").

**This is a precision the spec should absorb.** L4's `EVERY` barrier is **not** the deontic-logic
_collective_ obligation: a collective obligation is satisfied if the task gets done, however the
group divides it, and some members may do nothing. L4's barrier requires _every_ inhabitant to
perform and blames each who does not. In this vocabulary, **both** of L4's constructs are
_distributive_ (Royakkers & Dignum's "restricted general obligation"); they differ only in the
continuation. Related: Grossi, Dignum, Royakkers & Meyer, "Collective Obligations and Agents: Who
Gets the Blame?", DEON 2004 — the closest formal work to the spec's §6 blame attribution.

> **Addendum 2026-09-06, from the Alchourrón–Bulygin memo (§6.2, §6.4).** Two corrections. First, L4
> _does_ model the collective obligation, at the combinator level rather than the quantifier: `(PARTY a
MUST pay) ROR (PARTY b MUST pay)` is Lindahl's collectivistic `O(E_a F ∨ E_b F)`, and the machine
> breaches it only when every alternative has been definitively lost
> (`jl4-core/src/L4/EvaluateLazy/Machine.hs:1698-1730`, "consistently with CSL"). Second, the reason no
> quantifier can express it is a theorem, not a gap: obligation distributes over conjunction and does
> **not** distribute over disjunction (Sergot, "A computational theory of normative positions", ACM
> TOCL 2001), so `EVERY`/`EACH` over `MUST` can only ever build the conjunction, and `EACH p MAY` is
> not the disjunction either. The table row below is corrected accordingly.

Nobody in this literature uses _joint_ or _several_. Governatori's FCL/PCL line and Symboleo (Sharifi,
Amyot, Mylopoulos et al.) likewise: I found **no** treatment of joint vs several obligations in either
— see §8.

### 4.2 The distinction _does_ already have an established name — in workflow patterns

The barrier/fork split is the multiple-instance family of the van der Aalst / ter Hofstede / Russell
control-flow patterns (workflowpatterns.com):

- **WCP-12, "Multiple Instances without Synchronization"** = the fork. "Within a given process
  instance, multiple instances of a task can be created. These instances are independent of each
  other and run concurrently. **There is no requirement to synchronize them upon completion.**"
  Synonyms it lists: "Multi threading without synchronization, spawn off facility."
- **WCP-14, "Multiple Instances with a priori Run-Time Knowledge"** = the barrier, and it is
  specifically L4's case, since the inhabitant set is computed at run time before the obligations are
  created. "The required number of instances may depend on a number of runtime factors […] but is
  known before the task instances must be created. Once initiated, these instances are independent of
  each other and run concurrently. **It is necessary to synchronize the instances at completion
  before any subsequent tasks can be triggered.**" (WCP-13 is the design-time-known variant; WCP-15
  the variant where instances may still be spawned after others have finished.)

This matters practically, not just for citation hygiene: **L4 already exports BPMN**, where this is
the multi-instance activity marker, and BPMN/workflow readers have a name for the distinction that
does not collide with anything in contract doctrine. If a lawyer-facing word is wanted the patterns
do not supply one — but they settle the question of whether the distinction is real and named. It is.

---

## 5. Mapping table

| Term                                                           | Source / grounding                                                                   | L4 semantics it corresponds to                                                                                                                      | Ambiguity / caveat                                                                                                                                              |
| -------------------------------------------------------------- | ------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **joint** (common law)                                         | Williston § 36:1; Restatement §§ 288, 293, 294(1)(a); _Duck v Mayeu_ [1892] 2 QB 511 | **Barrier — only partially.** One obligation, one breach ✓. But _each liable for the whole_ and _performance by one discharges the rest_ (§ 293) ✗✗ | Directly contradicts the barrier on discharge. Also carries joinder, release-of-one, survivorship.                                                              |
| **several** (common law)                                       | Williston § 36:1; Adams 2012                                                         | **Fork — partially.** Separate promises, separately enforceable, separate breaches ✓                                                                | Adams's and Williston's canonical example _divides_ the payload ($50 + $50); L4's fork _replicates_ it. Also: "several" reads as "a few" to a layperson (§7.2). |
| **joint and several**                                          | Restatement § 289 (via Adams); _Black's_ (via Adams); Wex                            | **Pattern C** (shared-debt resource)                                                                                                                | Adams: "_joint_ is subsumed by _several_… nothing is accomplished." Practitioners use it for liability only, never for performance structure.                   |
| **solidary** (civil law)                                       | LCC art. 1794–1795; French C. civ. art. 1313                                         | **Pattern C**                                                                                                                                       | The official French→English translation renders _solidaire_ as "joint and several", which is how the false friend gets manufactured.                            |
| **joint / divided** (civil law)                                | LCC arts. 1788–1789; French C. civ. art. 1309                                        | **Barrier** (one performance, portions, all must render their portion)                                                                              | **Opposite sign to common-law "joint"**: "neither is bound for the whole."                                                                                      |
| **several** (civil law)                                        | LCC art. 1787                                                                        | **Fork** — "each of different obligors owes a separate performance"; "produces the same effects as a separate obligation"                           | The cleanest single citation for the fork anywhere in this memo.                                                                                                |
| **indivisible**                                                | LCC arts. 1815, 1818; French C. civ. art. 1320                                       | **Pattern D** (single coordinated act) — but with solidary _remedies_ attached (LCC 1818)                                                           | LCC art. 1820: "A stipulation of solidarity does not make an obligation indivisible" — Patterns C and D are orthogonal, which the spec has right.               |
| **collective obligation**                                      | Royakkers & Dignum; Norman & Reed ("collective group"); Garion & Cholvy 2007         | **Neither quantifier — but `ROR` across named parties does** (addendum, §4.1). Group-as-a-whole must achieve the task; individuals may do nothing   | Do **not** use "collective" for the barrier — the spec's §2.2 heading "Distributive vs Collective" is already slightly off in this vocabulary.                  |
| **distributive obligation / "restricted general obligation"**  | Norman & Reed; Royakkers & Dignum                                                    | **Both** barrier and fork (they are both distributive; the difference is in the continuation)                                                       | Confirms the distinction L4 draws is a _continuation_ property, not a quantification property.                                                                  |
| **WCP-12 "Multiple Instances without Synchronization"**        | workflowpatterns.com; Russell/ter Hofstede/van der Aalst/Mulyar, BPM-06-22 (2006)    | **Fork** — exact                                                                                                                                    | No legal reading to import.                                                                                                                                     |
| **WCP-13/14/15 "Multiple Instances (…) with synchronization"** | ibid.                                                                                | **Barrier** — exact; WCP-14 is L4's run-time-known case                                                                                             | WCP-15 raises the unruled question of instances added after arming.                                                                                             |

---

## 6. Does _joint_ correspond to the barrier? The direct answer

Partially, and it fails on the decisive point.

- ✓ **One obligation, one breach.** Joint promisors are bound by "a single cause of action" ([2013]
  SGHC 268 at [62], summarising Neill LJ); the barrier has one `HENCE` and one `LEST`. Restatement
  § 288's "same performance" default is the same structural idea.
- ✗ **Discharge.** Restatement § 293: "Full or partial performance or other satisfaction of the
  contractual duty of a promisor discharges the duty to the obligee of each other promisor of the
  same performance to the extent of the amount or value applied." Under L4's barrier, Alice signing
  does nothing whatever for Bob's obligation. A lawyer reading `JOINTLY` will expect one obligor to
  be able to satisfy the whole thing. That is a wrong answer, not an approximation.
- ✗ **Release.** Releasing one joint obligor discharges all. The barrier has no such operation.

Are _several_ obligations the fork? Closer — LCC art. 1787 is an almost exact statement of the fork —
but on the common-law side the canonical example divides rather than replicates the payload, and
nothing in the doctrine says anything about per-obligor continuations, which is the entire content of
L4's fork.

**The deepest problem is structural: doctrine has no notion of a continuation.** Joint/several answer
"whom may the creditor sue, for how much, in what action, and what discharges whom". L4's barrier/fork
answer "when does the next stage of the contract fire, and how many times". These are different
questions. The overlap on obligation-identity is real but partial, and a reader who "already draws
this distinction" draws a _different_ distinction with the same words.

---

## 7. Recommendation

### 7.1 Do not use `JOINTLY` / `SEVERALLY` for barrier / fork

Five grounds, in descending weight:

1. **`JOINTLY` asserts the opposite of the barrier on discharge** (Restatement § 293). This is a
   contradiction, not a nuance.
2. **The sign of "joint" flips between common law and civil law** (LCC art. 1788), so the word
   cannot be given one safe definitional sentence for a mixed readership. Singapore's own bar reads
   both traditions.
3. **The leading drafting authority has retired the words** — "ill understood", "more trouble than
   they're worth" (Adams 2012). Teaching beginners a vocabulary the profession's style manual is
   discarding is a poor trade for familiarity.
4. **`SEVERALLY` fails the beginner worse than `EACH` does.** The distinctness sense is the _older_
   one; the numeral sense ("several = a few") arose c. 1530s "growing out of legal meanings of the
   word", and by the mid-17c. "several" was "a vague numeral" in which "the notion of distinctness
   had largely faded" (Online Etymology Dictionary, s.v. _several_). A first-time reader hears
   "severally, every Person must sign" as "some of them must sign" — a _wrong_ reading, where `EACH`
   at worst gives an _incomplete_ one. The proposal's stated purpose is to survive a noob persona;
   on this word it makes the noob problem worse while fixing the lawyer problem only partly.
5. **The spec's own Patterns C and D need the words more than the quantifiers do**, and there they
   are doctrinally correct: `JOINTLY AND SEVERALLY` for the shared-debt resource (Wex, _Black's_,
   LCC 1794 all agree), and `JOINTLY execute` for the single indivisible act (LCC 1815/1818, French
   art. 1320). A keyword pair whose juxtaposition means something unrelated to either member — which
   §2.2.6 explicitly concedes `JOINTLY AND SEVERALLY` would be — is a language-design smell.

### 7.2 What to do instead: mark the join at the continuation, not at the quantifier

The spec already contains the argument for this and does not act on it. §3.3: "When there is no
continuation clause, EVERY and EACH are semantically equivalent." The distinction is a property of
the **continuation**, not of the quantification. Encoding it in the quantifier word is what forces
the whole vocabulary problem: it asks one word to carry information that belongs somewhere else, and
then requires that word to be memorised because nothing about `EVERY` vs `EACH` — or `JOINTLY` vs
`SEVERALLY` — announces which is which.

Put the marker where the semantics lives, and it becomes self-documenting for both audiences:

```l4
EVERY Person p MUST sign WITHIN 30 days
    HENCE ONCE ALL HAVE   closing_complete          -- barrier: fires once
    LEST  ONCE ALL HAVE   deal_falls_through

EVERY Person p MUST sign WITHIN 30 days
    HENCE FOR EACH        company MUST notify_board -- fork: fires per completion
```

This costs one quantifier keyword instead of two, needs no glossary entry, imports no doctrine, and
leaves `JOINTLY` / `SEVERALLY` free for Patterns D and C. The exact spelling is yours — `ONCE ALL` /
`FOR EACH`, `AFTER ALL` / `PER PARTY`, `TOGETHER` / `SEPARATELY` all work; the recommendation is the
placement, not the particular words.

### 7.3 Second best, if single modifier words are wanted

`TOGETHER` and `SEPARATELY`. They are plain English, they read correctly to a layperson and a lawyer
alike, they carry no doctrinal cargo to import wrongly, and `SEPARATELY` is what LCC art. 1787
actually says the several obligation does ("owes a **separate** performance… produces the same
effects as a **separate** obligation"). They are also, not incidentally, close to WCP-12's own gloss
("independent of each other", "no requirement to synchronize"). They are strictly better than
`JOINTLY`/`SEVERALLY` on every axis in §7.1 and better than `EVERY`/`EACH` on beginner legibility.

### 7.4 If `JOINTLY` / `SEVERALLY` are adopted anyway

Then every page that introduces them must carry a sentence of this shape, and the negations are the
load-bearing half:

> In L4, **`JOINTLY`** means that all the obligations complete before one shared consequence fires,
> and **`SEVERALLY`** means each obligation carries its own consequence. These are _not_ the
> liability senses: `JOINTLY` here does **not** mean that any one obligor may perform the whole and
> discharge the rest, and it does **not** mean that releasing one releases all — every obligor must
> still perform. `SEVERALLY` does **not** divide the obligation into shares; each obligor owes the
> same thing. For each-obligor-liable-for-the-whole, see `JOINTLY AND SEVERALLY`, which is a separate
> construct and is not `JOINTLY` combined with `SEVERALLY`.

That is four denials before the reader can use the feature — which is itself the argument for §7.2.
Note also that a barrier's blame set (spec §6.1) is the non-completers, which is exactly _several_
liability's per-obligor breach, so under this naming the `JOINTLY` construct produces `SEVERALLY`-
shaped blame. If the words are adopted, that wrinkle needs its own sentence.

### 7.5 Two consequential notes for the spec regardless of the ruling

- **§2.2 heading "Distributive vs Collective" is off in the formal vocabulary.** In Norman & Reed /
  Royakkers & Dignum terms, both `EVERY` and `EACH` are _distributive_; a _collective_ obligation is
  one the group may discharge without every member acting, which L4 does not model at all. Worth a
  line in §14 Related Work, and it strengthens §7.2's point that the difference lives in the
  continuation.
- **Cite WCP-12 / WCP-14 in §3.1–3.2 and §14.** The spec currently reaches for CSP and Petri nets;
  the workflow-patterns names are more exact, are the standard reference for this precise pair, and
  connect to the BPMN export.
- **An unlisted open question, from the survivorship doctrine (§1.3):** what happens to an armed
  barrier when the inhabitant set changes after arming — an inhabitant added, or removed, mid-window?
  WCP-14 vs WCP-15 is exactly this distinction, and §13 does not raise it.

---

## 8. What I could not find

- **Garner.** No access to the _Garner's Dictionary of Legal Usage_ (3d ed., 2011) entry on "joint
  and several" / "jointly and severally", nor to _Black's Law Dictionary_ in its own words. Adams's
  characterisation of _Black's_ (§2) is his paraphrase and is reported as such.
- **MSCD §§ 13.350–13.361** — the section numbers are Adams's own citation from his blog; I have not
  read the sections.
- **Restatement comments.** Only the black letter of §§ 288, 293 and 294 was verifiable; §§ 289–292,
  295–296 and all comment text were not. The much-quoted "primarily remedial and procedural" line
  reaches this memo through Adams and is flagged in §1.2.
- **Statute text for UK LPA 1925 s. 81 and Civil Liability (Contribution) Act 1978 s. 3.**
  legislation.gov.uk bot-walls both `curl` and WebFetch (empty HTTP 202s from CloudFront); mirrors
  were 403. Singapore's Civil Law Act s. 17 is quoted above _as reproduced in_ [2013] SGHC 268, which
  states it is borrowed from UK s. 3 — that is second-hand for the UK provision. LPA 1925 s. 81 was
  not reached at all; note from the search result that it concerns covenants made **with** two or
  more jointly, i.e. the _promisee_ side, so it is likely less relevant to this question than the
  brief supposed.
- **Glanville Williams, _Joint Obligations_ (1949).** Not available online; only secondary reports of
  its two central propositions (a joint promise creates a single obligation; the presumption is that
  a contract by two or more is joint, express words being needed to make it joint and several). Not
  quoted here for that reason.
- **Joint/several in Symboleo, Governatori's FCL/PCL/Regorous, Hvitved's CSL, Accord/Ergo, Lexon.**
  Searched; **no treatment found in any of them.** Hvitved's CSL is confirmed to have contract
  conjunction/disjunction with compositional blame assignment, which is the mechanism the spec cites,
  but I found nothing on multi-party quantification or on joint/several as such. So far as this
  research goes, **no formal or computational contract language uses joint/several as vocabulary** —
  which is weak evidence either way, but it does mean adopting them would not be following anyone.
- **Quebec CCQ arts. 1518–1540** and Roman correality/solidarity: not researched; Louisiana and the
  French code covered the civilian point adequately and time went to the primary sources above.

---

### Notes

¹ Restatement (Second) of Contracts (1981), selections PDF hosted at
`businesslitigator.law/wp-content/uploads/2022/08/Restatement-Second-of-Contracts-1981.pdf`. Contains
black letter only for §§ 288, 293, 294 of Chapter 13.
² Same document; the comments are not reproduced in it.
³ _Park Regis Hospitality Management Sdn Bhd v British Malayan Trustees Limited & Ors_ [2013] SGHC
268, https://www.elitigation.sg/gd/s/2013_SGHC_268, at [60]–[66].
⁴ _The Law of Contract, the General Regime of Obligations, and Proof of Obligations_ — the official
English translation of the reformed French Civil Code by John Cartwright, Bénédicte Fauvarque-Cosson
and Simon Whittaker, commissioned by the Direction des affaires civiles et du sceau, Ministère de la
Justice, revised 2018:
https://www.justice.gouv.fr/sites/default/files/migrations/textes/art_pix/Translationrevised2018final.pdf

### Sources

- Ken Adams, "Exploring 'Joint and Several'", https://www.adamsdrafting.com/exploring-joint-and-several/ (rev. 30 Apr 2012; retrieved via Internet Archive snapshot 20260113032451)
- Ken Adams, "Joint and Several", https://www.adamsdrafting.com/joint-and-several/ (2007; snapshot 20251013143513)
- Restatement (Second) of Contracts §§ 288, 293, 294 — https://businesslitigator.law/wp-content/uploads/2022/08/Restatement-Second-of-Contracts-1981.pdf
- Louisiana Civil Code arts. 1786–1806, 1815–1820 — https://lcco.law.lsu.edu/?uid=66&ver=en and https://lcco.law.lsu.edu/?uid=67&ver=en
- French Civil Code (2016 reform), official English translation — https://www.justice.gouv.fr/sites/default/files/migrations/textes/art_pix/Translationrevised2018final.pdf
- _Park Regis v British Malayan Trustees_ [2013] SGHC 268 — https://www.elitigation.sg/gd/s/2013_SGHC_268
- Garion & Cholvy, "Deriving individual obligations from collective obligations", Dagstuhl Seminar Proceedings 07122 — https://drops.dagstuhl.de/storage/16dagstuhl-seminar-proceedings/dsp-vol07122/DagSemProc.07122.11/DagSemProc.07122.11.pdf
- Grossi, Dignum, Royakkers & Meyer, "Collective Obligations and Agents: Who Gets the Blame?", DEON 2004 — https://link.springer.com/chapter/10.1007/978-3-540-25927-5_9
- Workflow Patterns Initiative, control-flow patterns WCP-12 and WCP-14 — http://www.workflowpatterns.com/patterns/control/
- Cornell LII (Wex), "joint and several liability" — https://www.law.cornell.edu/wex/joint_and_several_liability
- Online Etymology Dictionary, s.v. _several_ — https://www.etymonline.com/word/several
