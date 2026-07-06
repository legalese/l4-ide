# The State Ledger — RECORD / COMMIT / ATTEST / RECALL

A regulative contract residuates over a trace of timestamped events (see [regulative.md](regulative.md) for
`MUST`/`MAY`/`SHANT`, `HENCE`/`LEST`, `RAND`/`ROR`, and `#TRACE`). The **state ledger** lets a contract also
*write* and *read* facts as it runs: an append-only, event-sourced store (Reader-over-Writer) that shares the
same trace. Constitutive predicates can `RECALL` from it; deontic steps can `RECORD`/`COMMIT` into it.

> **Availability caveat.** `RECALL ALL`, recipient-qualified `RECORD`, and the `HENCE`-block sugar live on the
> **state-ledger line** (PRs #31 / #38) and are available in those builds. A reader on a plain `main` build will
> **not** have them yet — check your build before relying on them.

---

## Two ledgers: own vs official

There are two kinds of store:

- **A party's own ledger** — what a party privately knows / has recorded. Written with `RECORD`, read with
  `RECALL` (own) or `RECALL <party>'s …` (cross-party).
- **The official record** — the shared, world-visible record. Written with `COMMIT` / `ATTEST`, read with
  `RECALL OFFICIAL's …`. `OFFICIAL` is a **case-sensitive all-caps keyword**.

---

## Writing: `RECORD`, `COMMIT`, `ATTEST`

- `RECORD <cell> IS <v>` — append to the **acting party's own** ledger.
- `RECORD <party>'s <cell> IS <v>` — recipient-qualified write into **party q's own** ledger (the NOTIFY
  mechanism; see below).
- `COMMIT <cell> IS <v>` / `ATTEST <cell> IS <v>` — append to the shared **official record**.
  (`COMMIT`/`ATTEST` always target the official record; there is no party qualifier on them.)

A write can sequence into a continuation (deontic sequencing): `p HENCE RECORD <cell> IS <v> HENCE q` — the write
is a step that then continues. Because `MUST`'s `HENCE` fires on *performance*, a wrapper

```l4
PARTY p MUST <act> WITHIN n HENCE RECORD <cell> IS <v> HENCE onwards LEST onwards
```

makes "doing `<act>` IS the ledger write" — recorded iff `<act>` is actually performed, and *soft* when `LEST`
routes to a benign continuation rather than `BREACH`.

---

## Reading: `RECALL` (last-write-wins) vs `RECALL ALL` (collect-all)

Plain `RECALL` is **last-write-wins**: it returns only the *latest* write to a cell, as `MAYBE a` (`NOTHING` if
never written). `RECALL ALL` instead folds **every** write to the cell into a `LIST OF a`, **oldest → newest**
(`[]` if never written). Both come in three address forms — own, `<party>'s`, and `OFFICIAL's`:

| Read | Returns | Reads from |
| --- | --- | --- |
| `RECALL <cell>` | `MAYBE a` (latest) | acting party's own ledger |
| `RECALL <party>'s <cell>` | `MAYBE a` (latest) | a named party's own ledger |
| `RECALL OFFICIAL's <cell>` | `MAYBE a` (latest) | the official record |
| `RECALL ALL <cell>` | `LIST OF a` (oldest→newest) | acting party's own ledger |
| `RECALL ALL <party>'s <cell>` | `LIST OF a` (oldest→newest) | a named party's own ledger |
| `RECALL ALL OFFICIAL's <cell>` | `LIST OF a` (oldest→newest) | the official record |

```l4
#EVAL LIST (RECORD `seq` IS 1), (RECORD `seq` IS 2), (RECORD `seq` IS 3),
           (sum (RECALL ALL `seq`))     -- 6  (the list [1,2,3], oldest->newest)

-- official record: count and sum every COMMIT, vs last-write-wins for the latest
(count (RECALL ALL OFFICIAL's `rate`))      -- 3
(fromMaybe 0 (RECALL OFFICIAL's `rate`))    -- 110  (plain RECALL = last only)
```

---

## Recipient-qualified `RECORD` (NOTIFY)

`RECORD <party>'s <cell> IS <v>` writes into **party q's own** ledger — the symmetric WRITE to the cross-party
read `RECALL <party>'s <cell>`. The acting party performs the write; the value lands in the *recipient's* ledger,
keyed by the same party key the cross-party `RECALL` reads (provenance source `NOTIFY`). This **is** the NOTIFY
mechanism — there is no new keyword; "giving notice" is just a recipient-qualified `RECORD`:

```l4
PARTY Landlord MUST `serve notice` WITHIN 14
  HENCE RECORD Tenant's `noticeReceived` IS
          Notice WITH body IS "possession may be recovered on Ground 1" ; ground IS 1
        HENCE PARTY Tenant MUST acknowledge WITHIN 14
```

After this performs, `RECALL Tenant's `noticeReceived`` sees a `JUST`; the acting party's own `RECALL` does not.
**"Notify the world" is still `COMMIT`/`ATTEST` to `OFFICIAL`** (anyone can `RECALL OFFICIAL's …` it);
recipient-qualification is a `RECORD`-only feature.

---

## Deontic sequencing and the `HENCE`-block sugar

A `RECORD`/`COMMIT`/`ATTEST` continuation may be given by an **aligned same-column sibling** instead of an
explicit `HENCE` — the sibling is parsed into the preceding write's continuation slot, desugaring to the
**identical right-nested AST** as the flat `HENCE` chain:

```l4
PARTY P MUST serve WITHIN 10
  HENCE RECORD `a` IS TRUE      -- block form: aligned siblings, no repeated HENCE
        RECORD `b` IS FALSE
        PARTY P MUST serve WITHIN 20
-- == HENCE RECORD `a` IS TRUE HENCE RECORD `b` IS FALSE HENCE PARTY P MUST serve WITHIN 20
```

- Reached via **`HENCE` or `LEST`**.
- The block **terminates at the first non-`RECORD` provision** (which may itself be a `RAND`/`ROR` expr — that
  expr becomes the continuation).
- Flat `HENCE` and block siblings **mix freely** in one chain.
- Works for `COMMIT`/`ATTEST` blocks too (`HENCE COMMIT `a` IS … / ATTEST `b` IS …`).

---

## Framings worth knowing (formalization guidance)

- **The trace IS the ledger IS the CSL event stream** — one structure. The deontic graph *residuates* over it
  (`HENCE`/`LEST`); constitutive predicates *`RECALL`* from it. A single event can both advance the contract and
  record a fact.
- **Epistemic modals as a thin cap on the ledger.** "Giving notice" = a write into the recipient's epistemic
  state — `RECORD <recipient>'s <cell> IS <v>` (the recipient-qualified RECORD / NOTIFY mechanism, above);
  "notify the world" = `COMMIT` to the official record (anyone can `RECALL OFFICIAL's …` it); "was notified" /
  "is aware that" = a `RECALL <recipient>'s <cell>` projection.
- **Operative vs forensic framing.** Prefer writing the *live* contract (e.g. a tenancy agreement) authored at
  signing and run forward, with formation-time obligations placed where the parties heed them. A court-facing
  question ("must possession be ordered?") is then a query over the *same* trace, not a separate after-the-fact
  contract.

---

## Reference files (in the l4-ide repo)

- `jl4/experiments/state-ledger.l4`, `state-ledger-m45.l4` — the ledger ops (RECORD/COMMIT/RECALL).
- `jl4/experiments/housing-act-ground-1-traced.l4`, `housing-act-schedule2-aspect.l4` — the ledger + RAND
  aspect-weaving applied to UK Housing Act 1988 Sch 2 Ground 1.
