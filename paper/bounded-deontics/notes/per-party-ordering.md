# Per-party ordering: from the protestor cartoon to a two-ordering jurisprudence

> Design note, 2026-06-24. Chasing the thread the chained-protestor vignette opened
> (`notes/illustrations.md`): does the goal index become `Party → ordering`, and does
> that subsume the sanction/goal duality? Companion to `notes/fca-verdict.md` (the
> de-risked `nec` core) and `OUTLINE.md` §§5–6. Working theory; prior-art pass TODO.

## 1. The factoring: index the ordering source, not the relation

Keep the necessity relation **party-neutral** (Kratzer's _modal base_); make the
**ordering source** party-indexed (Kratzer's second conversational background, which
he never indexed by agent — the cartoon is the counterexample forcing the indexing).

- **Modal base** = transition system. `nec ⊆ State × Action × Goal`, `(K,J) ∈ nec_s`
  iff K **dominates** J (every path s→J passes through K). MUST = dominator,
  MAY = `EF J`. Party-free, preference-free. (The de-risked §5 core.)
- **Ordering source** = `⪯_p`, party p's preorder over outcomes. The **teleological
  MUST is the composition**:
  `MUST_p(s) = ⋃ { dom(J) : J reachable from s and J is ⪯_p-good }`.

So `Party → ⪯` (the ordering source is party-indexed); `nec` is NOT party-indexed.
Letter/spirit preserved: object level stays goal- and party-free; party preferences
live at the assertion level.

## 2. Sanction/goal duality = the sign of the outcome under `⪯_p`

Anderson's sanction `S` and the teleological goal `G` are not two primitives but the
**avoid-side and reach-side of one necessity relation**, selected by sign:

| outcome X    | sign under `⪯_p` | stance | modality       | necessity                                                                |
| ------------ | ---------------- | ------ | -------------- | ------------------------------------------------------------------------ |
| goal `J`     | good             | reach  | liveness `EF`  | MUST = dominators of `J`                                                 |
| sanction `S` | bad              | avoid  | safety `AG ¬S` | MUST = acts to stay in `¬S`; SHANT acts that commit to `S` (Meyer's `V`) |

"To reach the good you must K" and "to avoid the sanction you must K" are one rule at
opposite polarity. **The cartoon = a sign flip between parties:** jail is the
protestor's `⪯`-good (goal), but the cop _modelled_ it as the protestor's `⪯`-bad
(sanction) — a **misattributed ordering source**.

## 3. The prize: two distinguished orderings ⇒ Holmes/Hart formalised

Legal "must" is imposed, not derived from the agent's goals, so there are (≥) two
orderings:

- `⪯_p` — the **agent's** ordering (descriptive; Holmes's _bad man_ steers by it);
- `⪯_law` — the **legal system's** ordering (normative; what one _ought_).

Then:

- **legal obligation** = `nec ∘ ⪯_law`;
- **predicted behaviour** = `nec ∘ ⪯_p`;
- **enforcement gap** = where `⪯_p` and `⪯_law` diverge — _the bad man lives here_;
- **Hart's internal point of view** = the agent adopting `⪯_law` as its own (orderings
  coincide);
- **sanctions** = the law's instrument to realign `⪯_p` toward `⪯_law` (depress the
  `⪯_p`-rank of non-compliance until compliance dominates).

Failure modes become precise:

- **"A fine is a price"** — the sanction fails to push `⪯_p`(breach) below
  `⪯_p`(comply); the gap stays ≤ 0.
- **The protestor** — the sanction _raises_ `⪯_p`(breach) (jail desired); gap goes
  negative; the "must" inverts.

**Quantitative "bounded":**
`Force(MUST_p K) = rank_{⪯_p}(comply) − rank_{⪯_p}(breach)`.
Deontic force = the `⪯_p`-gap the sanction induces — finite, agent-relative, and
exactly what the law tries to manufacture. This is "bounded" made into a number, and
it subsumes the spec's penalty-_magnitude_ test (magnitude is just one input to the
gap; framing/crowding-out is another — ties to Hart + Gneezy-Rustichini).

## 4. Escalation ladder (environment assumption per rung)

1. **Party-neutral `nec`** — CTL dominators. Neutral/cooperative world. (§5.)
2. **Single-party teleological MUST** — `nec ∘ ⪯_p`. The anankastic "if p wants J, p
   must K." (§6.)
3. **Multi-party strategic MUST** — the cartoon's kicker: the cop can _deny_ the
   protestor the needed act. The right notion is then "what must p do to **force** J
   against adversarial others" = **ATL** strategic ability `⟨⟨p⟩⟩F J`, not "K on all
   paths." Single-party `nec` (CTL dominators) is the cooperative special case of ATL
   strategic necessity. (Future facet / §6.5.)

## 5. Hohfeldian wrinkle (carried from the vignette)

Goal-holder ≠ action-performer: the protestor (goal-holder) tries to obligate the cop
(only party who can perform `arrest`). `MUST_p` must therefore be read with a
performer index: an act necessary for p's goal but performable only by q is not p's
obligation but p's **dependency on q's agency** (Hohfeldian power/liability; the
"control-holder" role from the PROLEG three-roles note).

## 6. Honesty flags / prior-art pass TODO

- Ordering-/"betterness"-based deontic semantics is ESTABLISHED — Hansson (preference
  semantics); **van Benthem, Grossi & Liu, "Deontics = Betterness + Priority"** /
  priority structures; ⇒ the per-party ordering is NOT novel by itself.
- Strategic obligation in **ATL** has a literature — Pauly (coalition logic);
  Broersen (deontic/STIT-ATL). ⇒ rung 3 is not novel apparatus.
- **Our novelty claim must be:** (a) the party-indexed ordering **composed with the
  dominator-`nec`** from a transition system, and (b) **`⪯_law` vs `⪯_p` divergence as
  the formal locus of the Holmes/Hart debate** + the `Force = ⪯_p-gap` quantification.
  NOT ordering semantics per se. Verify against the above before drafting §6.
- `⪯_p` is often **private/unknown until revealed** (the protestor surprised the cop)
  ⇒ a runtime input; compile-time verification runs against the known `⪯_law`. Slots
  into the ∃/runtime side of `notes/static-vs-runtime.md`.

## 7. Where it lands

- §5 stays party-neutral (the dominator `nec`).
- §6 (the boundary) gains its spine: the `⪯_law` vs `⪯_p` divergence, the `Force` gap,
  and the two failure modes (fine-is-a-price, protestor).
- A multi-party/ATL treatment (rung 3) is a strong **future facet** in the series.
