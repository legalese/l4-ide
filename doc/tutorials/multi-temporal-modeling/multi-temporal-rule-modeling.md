# Multi-Temporal Rule Modeling

Model rules that change over time, and understand the three independent
time axes L4 tracks while doing it.

**Audience:** Advanced legal engineers modeling amendments, effective
dates, or transitional provisions.

**Prerequisites:** Basic L4 knowledge ([Your First L4 File](../getting-started/first-l4-file.md)); some familiarity with dates ([Common Patterns](../getting-started/common-patterns.md) covers the `daydate` library).

**Complete example:** [gst-rate-change-example.l4](gst-rate-change-example.l4)

---

## Why more than one "now"?

Databases have a well-known problem: a row can have both a **transaction
time** (when the system recorded it) and a **valid time** (when the fact
it describes actually held true in the world). A bank might enter a
correction on 15 March for a transfer that happened on 2 March — the
system learned about it on the 15th, but the money moved on the 2nd.
Modeling both is called _bitemporal_ data.

Legal rules need a third axis. A rule isn't just a fact with a valid
time — it's itself a moving target. The GST rate that applied to a sale
depends on **which version of the law was in force**, and that can be
different again from both "when am I asking" and "when did the sale
happen." A tax office auditing a 2019 transaction in 2026 needs:

| Question                                  | L4 calls this           | Reader                                               | Override                        |
| ----------------------------------------- | ----------------------- | ---------------------------------------------------- | ------------------------------- |
| When is this evaluation actually running? | **system time**         | `TODAY` / `NOW`                                      | `EVAL AS OF SYSTEM TIME`        |
| When did/does the fact hold in the world? | **valid time**          | (falls through to `RULES EFFECTIVE DATE`, see below) | `EVAL UNDER VALID TIME`         |
| Which version of the law applies?         | **rule-effective time** | `RULES EFFECTIVE DATE`                               | `EVAL UNDER RULES EFFECTIVE AT` |

Each axis is tracked independently and defaults sensibly when you don't
pin it. The rest of this tutorial builds up the GST example file above
one axis at a time.

---

## Step 1: A rule that depends on its own version

```l4
`GST rate` MEANS
  IF (DATE_SERIAL `RULES EFFECTIVE DATE`) AT LEAST (DATE_SERIAL (Date 1 1 2024))
  THEN 9
  ELSE 7
```

`RULES EFFECTIVE DATE` is a nullary `DATE` builtin — it doesn't read an
argument, it reads the **rule-effective-time axis** out of the ambient
evaluation context. With nothing pinned, it falls all the way back to
today, so:

```l4
#EVAL `GST rate`
```

evaluates to `9` any time after the 2024-01-01 cutover — which is every
time you'll actually run this file. That's the point: the same
predicate, `GST rate`, means different things depending on what time
axis you evaluate it under. Nothing about its _definition_ changes.

---

## Step 2: Pin the rule-version explicitly

```l4
#EVAL `EVAL UNDER RULES EFFECTIVE AT` (Date 1 6 2023) `GST rate`
-- => 7

#EVAL `EVAL UNDER RULES EFFECTIVE AT` (Date 1 7 2024) `GST rate`
-- => 9
```

`EVAL UNDER RULES EFFECTIVE AT <date> <expr>` evaluates `<expr>` with the
rule-effective-time axis pinned to `<date>`, then restores the previous
context. It's an ordinary function, `DATE -> a -> a` (since 2026-07-29;
it previously took a `DATE_SERIAL` number, and the runtime still
tolerates one), so it composes: it works exactly the same way through a
dependent rule like `GST payable on`:

```l4
#EVAL `EVAL UNDER RULES EFFECTIVE AT` (Date 1 6 2023) (`GST payable on` 1000)
-- => 70

#EVAL `EVAL UNDER RULES EFFECTIVE AT` (Date 1 7 2024) (`GST payable on` 1000)
-- => 90
```

This is rule versioning as ordinary L4, with no special-cased amendment
syntax: one predicate, two rule-versions, two answers.

---

## Step 3: The default — law-time tracks fact-time

What if you _don't_ pin a rule-version, but you do pin the facts to a
particular date?

```l4
#EVAL `EVAL UNDER VALID TIME` (Date 1 6 2019) `GST rate`
-- => 7
```

`RULES EFFECTIVE DATE`'s fallback chain is: **(1)** an explicit
`EVAL UNDER RULES EFFECTIVE AT` pin, if present; else **(2)** the
valid-time axis, if pinned; else **(3)** today. With no rule-version pin
but the facts pinned to 2019, step (2) kicks in: the _old_ law applies.

This is the **presumption against retroactivity**, built into the
default: absent an explicit statement otherwise, the law that governs a
fact is the law that was in force when the fact occurred — not the law
in force when someone later asks about it. Pin the facts to the new
regime instead, and the new rate follows automatically:

```l4
#EVAL `EVAL UNDER VALID TIME` (Date 1 7 2024) `GST rate`
-- => 9
```

---

## Step 4: An explicit rule-version pin overrides fact-time

Sometimes you _do_ want to decouple the two — a transitional provision, a
savings clause, or an audit that asks "what would the old ruling have
said, restated in today's code, about a fact from the new regime?" Nest
the two overrides and the explicit, inner pin wins:

```l4
#EVAL `EVAL UNDER VALID TIME` (Date 1 7 2024)
      (`EVAL UNDER RULES EFFECTIVE AT` (Date 1 6 2019) `GST rate`)
-- => 7
```

Facts are pinned to 2024 (which would default to the new regime), but
the explicit `RULES EFFECTIVE AT` pin overrides that default. This is the
one case where "law-time tracks fact-time" is a **default**, not a law of
nature — an explicit statement always wins.

---

## Step 5: `TODAY` doesn't listen to the other axes

`TODAY` only ever reads the **system-time** axis. It is deliberately
independent of both valid time and rule-effective time:

```l4
#EVAL `EVAL UNDER VALID TIME` (Date 1 6 2019) (DATE_SERIAL TODAY)
#EVAL DATE_SERIAL TODAY
-- both give the same answer
```

This matters in practice: imagine a rule with a 30-day limitations
window computed from `TODAY`. If evaluating a fact from 2019 silently
shifted `TODAY` back to 2019 too, that window would compute against the
wrong wall clock. Keeping `TODAY` pinned to system time — and nothing
else — means "days since filing" style calculations stay correct no
matter which fact or rule-version you're reasoning about at the same
time.

---

## Step 6: Auditing a past evaluation clock

`EVAL AS OF SYSTEM TIME` overrides yet another axis: the evaluation clock
itself. It answers a different question from the other two — not "which
law applies" or "when did the facts hold," but "what would the system
have computed if this had been run back then?" That's the tool for audit
trails and regression snapshots.

There's a subtlety worth internalizing here. `RULES EFFECTIVE DATE`'s
own fallback bottoms out at _today_ when neither the rule-version nor
the valid-time axis is pinned — and "today" is computed the same way
`TODAY` computes it, from system time. So if you override system time
**without** pinning either of the other two axes, that override flows
through to `RULES EFFECTIVE DATE` as well:

```l4
#EVAL `EVAL AS OF SYSTEM TIME` (Date 1 6 2020) `GST rate`
-- => 7
```

No rule-version or valid-time is pinned here, so the fallback resolves
via the (overridden) system clock — 2020-06-01, pre-cutover, hence `7`.
The moment you _do_ pin rule-version or valid-time explicitly (Steps 2–4),
that pin takes priority and the system-time override no longer reaches
`RULES EFFECTIVE DATE` at all. System time only leaks into "which law
applies" through the unpinned fallback path — never past an explicit
statement.

---

## Step 7: Scanning a range of dates

`VALUE AT <date> (GIVEN d YIELD <expr>)` stamps **both** valid-time and
rule-effective-time to `<date>`, then evaluates `<expr>` — handy for
building a day-indexed table of what a rule would say across a
changeover, without threading two separate overrides by hand:

```l4
#EVAL `VALUE AT` (Date 1 6 2023) (GIVEN d YIELD `GST rate`)  -- => 7
#EVAL `VALUE AT` (Date 1 7 2024) (GIVEN d YIELD `GST rate`)  -- => 9
```

Separately, `EVER BETWEEN` / `ALWAYS BETWEEN` and `WHEN LAST` /
`WHEN NEXT` are general-purpose date-range search builtins — they scan a
range for a predicate of `DATE` and don't touch the rule-version
machinery at all. Shown here on a plain `is weekend` check:

```l4
`weekend?` d MEANS `is weekend` (DATE_SERIAL d)

#EVAL `EVER BETWEEN` (Date 5 1 2024) (Date 7 1 2024) `weekend?`    -- TRUE
#EVAL `ALWAYS BETWEEN` (Date 6 1 2024) (Date 7 1 2024) `weekend?`  -- TRUE
#EVAL `WHEN LAST` (Date 10 1 2024) `weekend?`  -- JUST OF (DATE OF 7, 1, 2024)
#EVAL `WHEN NEXT` (Date 10 1 2024) `weekend?`  -- JUST OF (DATE OF 13, 1, 2024)
```

Note `WHEN LAST`/`WHEN NEXT` return a `MAYBE DATE` (`JUST OF ...`), since
a bounded search can fail to find a match and return `NOTHING`.

---

## Mental Model Cheat Sheet

| Axis                | Answers                             | Reads via                             | Override                        | Independent of                  |
| ------------------- | ----------------------------------- | ------------------------------------- | ------------------------------- | ------------------------------- |
| System time         | "When is this evaluation running?"  | `TODAY` / `NOW`                       | `EVAL AS OF SYSTEM TIME`        | Valid time, rule-effective time |
| Valid time          | "When did the facts hold?"          | (via `RULES EFFECTIVE DATE` fallback) | `EVAL UNDER VALID TIME`         | System time                     |
| Rule-effective time | "Which version of the law applies?" | `RULES EFFECTIVE DATE`                | `EVAL UNDER RULES EFFECTIVE AT` | — (top of the fallback chain)   |

Fallback order for `RULES EFFECTIVE DATE`, most specific first: **explicit
rule-version pin → valid-time pin → today (via system time)**.

---

## Common Mistakes

### Assuming a valid-time override changes `TODAY`

```l4
-- ❌ Wrong assumption: TODAY shifts to match
#EVAL `EVAL UNDER VALID TIME` (Date 1 1 2000) (DATE_SERIAL TODAY)
-- Actually returns the REAL today — TODAY never reads valid time.
```

### Forgetting that an unpinned rule-version still listens to system time

```l4
-- If you only override system time, and pin NEITHER rule-version NOR
-- valid-time, RULES EFFECTIVE DATE's fallback follows the overridden
-- system clock too — it's not fully independent of system time, only
-- of an *explicit* rule-version/valid-time pin.
```

### Expecting `WHEN LAST`/`WHEN NEXT` to return a bare `DATE`

```l4
-- These return MAYBE DATE (JUST OF ... / NOTHING), not DATE directly,
-- since the search is bounded and can fail to find a match.
```

---

## What You Learned

- L4 tracks (at least) three independent time axes: system time, valid
  time, and rule-effective time — an extension of the classic bitemporal
  (transaction-time/valid-time) model with a third, law-version axis.
- `RULES EFFECTIVE DATE` implements the presumption against retroactivity
  by default: absent an explicit pin, the law that applies tracks the
  facts' valid time, falling back further to today.
- `EVAL UNDER RULES EFFECTIVE AT`, `EVAL UNDER VALID TIME`, and
  `EVAL AS OF SYSTEM TIME` are ordinary composable overrides
  (`DATE -> a -> a` since 2026-07-29), and an explicit inner pin always
  wins over an outer or ambient default.
- `TODAY` is pinned to system time only — it's the one thing an
  unpinned-fallback system-time override can still reach, but an
  explicit rule-version/valid-time pin cannot touch it at all.
- `VALUE AT`, `EVER`/`ALWAYS BETWEEN`, and `WHEN LAST`/`WHEN NEXT` give
  you day-indexed evaluation and date-range search without hand-threading
  overrides.

---

## Current Limitations

This tutorial covers what's implemented and demonstrated today. A few
related ideas are still design-stage, not shipped:

- A fourth axis, **rules-encoded time** (`EVAL UNDER RULES ENCODED AT`,
  tracking when the _L4 encoding itself_ was drafted, as distinct from
  when the law it encodes took legal effect), exists as a builtin but
  has no worked examples yet.
- Git-commit-based retroactive tooling (checking out the rule text as it
  existed at a past commit) was considered and explicitly **not**
  pursued in-language — see
  [`TEMPORAL-RULE-VERSION-DESIGN.md`](../../../specs/todo/TEMPORAL-RULE-VERSION-DESIGN.md)
  for the reasoning. Encoding-history counterfactuals are planned as a
  separate `l4 diff-eval` driver-level tool instead.
- `@effective` / `@repealed` decorator syntax for declaring an amendment
  directly on a rule (rather than composing `EVAL UNDER RULES EFFECTIVE
AT` by hand) is planned but not yet implemented.

---

## Next Steps

- [`TEMPORAL-RULE-VERSION-DESIGN.md`](../../../specs/todo/TEMPORAL-RULE-VERSION-DESIGN.md) — the full design rationale and decision log behind this feature, for readers who want the "why" in depth.
- [Common Patterns](../getting-started/common-patterns.md) — the `daydate` library used alongside these builtins in the example.
- [Encoding Legislation](../getting-started/encoding-legislation.md) — general technique for translating legal text into L4, if you haven't already.
