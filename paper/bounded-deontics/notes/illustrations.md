# Bounded Deontics — illustrations & motivating vignettes

> Running collection of worked illustrations and their theoretical payloads.
> Companion to OUTLINE.md (§1 vignettes, §7 formal worked example).

## The chained protestor (Meng's cartoon) — §1 opening vignette

**Setup (two panels):**
- Policeman, sternly: "You **must** unchain yourself and move along, **or else** I'll
  arrest you and you'll spend the night in jail!"
- Protestor: "You **must** arrest me — I came from out of town for the protest and my
  AirBnB just cancelled!"

**Theoretical payload (why it earns the opening slot):**

1. **`S = J` (sanction IS goal).** The cop frames jail as Anderson's sanction
   constant `S` (the "or else what"); the protestor reveals it's his goal `J`
   (lodging). The "or else what?" probe is answered *"yes please."*
2. **Force is monotone in disvalue.** Deontic force ∝ how much the agent disvalues
   the breach-consequence, *relative to the agent's own goal ordering*. When the
   disvalue goes negative (the consequence is desired), the "must" doesn't weaken —
   it **inverts**. "A fine is a price" → "a punishment is a reward" (limit case of
   Gneezy-Rustichini).
3. **Non-temporal `may→must`.** Normally lodging has alternatives (hotel, drive home,
   a friend's couch). The AirBnB cancellation is **alternative-path elimination**;
   once the other routes lapse, "get arrested" is the *unique* path to the goal, so
   `MAY(arrested)` collapses to `MUST(arrested)`. Same collapse as a deadline, but
   triggered by the reachability graph losing edges, **not by a clock** — shows the
   may→must event is path-necessity in general; a deadline is just one cause. (This
   is the non-temporal core illustration we wanted.)
4. **Derived path-necessity, weaponized + a Hohfeldian wrinkle.** The protestor
   computes `nec(arrest, lodging)` off his own state machine, then **re-expresses his
   instrumental necessity as an obligation on a DIFFERENT party** (only the cop can
   perform the arrest). So the relation needs party-tags on both sides:
   `nec ⊆ State × (Party × Action) × (Party × Goal)` — action performed by one party,
   necessary for a goal held by another. The humor = the **illicit transfer** of the
   necessity onto the wrong party (deontic cousin of Saki's type error). Ties to the
   three-Hohfeldian-roles note (PROLEG work): adds performer-of-act vs holder-of-goal.
5. **Refutes the "implicit universal goal" default.** The ChatGPT thread assumed the
   background theory supplies "…if you want to stay out of jail." This is the
   counterexample: that implicit goal is **defeasible and agent-relative**, and here
   it's reversed. ⇒ an argument FOR making the goal explicit and agent-indexed, and a
   caution that it is never a global constant. (The joke argues our own thesis.)
6. **Game-theoretic kicker.** Once the cop realizes the sanction is a reward, the
   rational move is to *withhold* it (don't arrest). The threat is empty AND
   enforcement inverts: to punish this protestor, refuse him jail. (Spec's
   "Phase 4: game-theoretic" corner, in two panels.)

**Pairing:** open §1 with this beside **Saki's Lady Carlotta** (from the source
transcript). Both are **modal-equivocation jokes**: Saki crosses epistemic↔deontic;
the cartoon crosses sanction-deontic↔instrumental-deontic *with the parties swapped*.
A matched set.

**Placement decision:** §1 motivating vignette (NOT the §7 formal worked example —
UCC Art. 9 / PPSA perfection keeps that, for its richer many-to-many concept lattice).
Sourcing TODO: the cartoon is Meng's recollection; find/redraw or describe-in-prose
(check rights before reproducing any existing cartoon).
