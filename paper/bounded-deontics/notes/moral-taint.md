# Moral taint: when a fine is not a price

> Design note, 2026-09-23, from Meng's observation that some rules treat any past failure as leaving a party in a state they must put right before other acts are allowed, even when the failed norm offered a reparation.
> Companion to `per-party-ordering.md` (the force-gap and the "fine is a price" failure mode) and to `specs/todo/NORM-LOG-SPEC.md` §3, which holds the examples, the four shapes and what L4 would need to express them.
> Working theory; no prior-art pass yet.

## 1. The phenomenon

A library patron with an overdue book cannot borrow another.
The loan's own norm has a reparation path — return it late and pay the fine — but the block sits on a different norm, the permission to borrow, and it reads the history of the first.
The same shape appears in loan drawstops, passport denial for child-support arrears, registration holds, unlawful-presence bars, the clean-hands maxim, and, most literally, the canon-law rule that grave sin bars communion until confession: repentance, which is not the same act as restitution.
`NORM-LOG-SPEC.md` §3 lists them with confidence levels, and sorts them into four shapes by how the block lifts: while the failure continues, for a period, never, or only by a distinct act of repentance.

## 2. Where it sits against the force-gap

`per-party-ordering.md` §3 defines deontic force as the gap the sanction opens in the party's own ordering: `Force(MUST_p K) = rank_{⪯_p}(comply) − rank_{⪯_p}(breach)`.
"A fine is a price" is the failure mode where the gap stays ≤ 0 because the fine is priced in.

The moralistic block manufactures force through a **different channel**.
It does not make the breach dearer in `⪯_p`; it changes `nec`.
Take the goal J = "borrow another book", and a patron whose first book is already overdue.
Under the functionalist reading the patron may borrow now and settle the late return later: there are paths to J on which the cure comes **after** the borrowing, so the cure does not dominate J.
Under the moralistic reading every path to J passes through the cure first, so **the cure dominates J**, and a patron who wants J faces a `MUST cure, and cure first` that the fine alone never created.
The block does not add an act the patron would otherwise skip — the book comes back either way — it **reorders** acts: it moves the cure ahead of everything the patron wants next.

So the frame is a force-gap instrument that works through the **modal base**, not the ordering source.
That adds a second channel beside the magnitude/crowding-out discussion in `OUTLINE.md` §6, and it predicts something the magnitude view does not: an institution can drop the price entirely and keep the force.
Fine-free libraries appear to have done exactly that — abolishing overdue fines while keeping the block on borrowing — whatever their motive was (the stated one was equity, not crowding-out, and this note does not claim otherwise).

## 3. What it demands of the object level

The channel only exists if the violation is part of the **state** later norms see.
Meyer's violation atom `V` does not settle this: whether `V` survives later actions is a modelling choice layered on the reduction, not part of it.
The moralistic frame is the case for a **sticky** `V`, cleared only by performance, repentance, lapse of time or pardon, and not by the reparation itself.

L4's runtime currently implements the transient reading by construction: a `LEST` that reaches `FULFILLED` is the same value as performance (`NORM-LOG-SPEC.md` §1).
A drafter can make `V` sticky by hand with a `RECORD` in the `LEST`, but only if they also author the upstream norm.
`NORM-LOG-SPEC.md` proposes the machine keep the sticky record itself.

For the paper this matters in one precise place.
The state space the dominator analysis runs over must include a **history summary** — at least, for each norm a later norm reads, whether it has failed and how the failure was discharged.
Without it the `nec` computation of `OUTLINE.md` §5 cannot see the moralistic block, and would report the late path as reaching J.
The cost is the usual one of history-dependence: the state space grows with the number of norms whose history is read, which bears on the model-checking story of `OUTLINE.md` §7.

## 4. Open for the paper

- Whether this belongs in v1 as a third illustration beside the fine-is-a-price and protestor cases, or in a later facet.
- The prior-art pass: contrary-to-duty obligations, violation persistence in dynamic deontic logic, and the reparational-obligation literature (Governatori and Rotolo's work on compensation chains is the obvious first stop) all need checking before any claim of novelty.
- Whether "repentance" (shape (d)) is a deontic notion at all, or a constitutive one — an act that counts as restoring standing — which would move it to the sorter of `OUTLINE.md` §4.
