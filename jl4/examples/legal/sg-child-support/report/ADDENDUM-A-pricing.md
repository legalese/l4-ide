# Addendum A — the run of 2026-08-25, priced

**To:** the conversion report for `sg/child-support`, encoding `legalese`, pipeline run
`2026-08-25-423e1cb8-001`.
**Dated:** 2026-08-26. **Prices as at that date.** The report itself is unchanged by this addendum.

Section 10 of the report records what the run **consumed**. This addendum multiplies those measured
counts by a **published price list** to get a number in dollars. The separation is deliberate: the
token counts are a fact about the run and will never change; the prices are a fact about a rate card
on one particular day, and will. Anyone re-reading this in a year should re-multiply rather than
trust the right-hand column.

## A.1 The rate card

Anthropic's published list price for `claude-opus-5`, from
[platform.claude.com/docs/en/about-claude/pricing](https://platform.claude.com/docs/en/about-claude/pricing),
retrieved 2026-08-26:

|                   | base input | 1h cache write | 5m cache write |    cache hit |     output |
| ----------------- | ---------: | -------------: | -------------: | -----------: | ---------: |
| **Claude Opus 5** |  $5 / MTok |     $10 / MTok |   $6.25 / MTok | $0.50 / MTok | $25 / MTok |

Cache multipliers are 2× / 1.25× / 0.1× of base input. Reasoning tokens bill as output. Web search
is $10 per 1,000 searches; web fetch adds nothing beyond the tokens it returns.

## A.2 The run at list

| line                             | measured tokens |          rate |       cost | share |
| -------------------------------- | --------------: | ------------: | ---------: | ----: |
| Cache reads (hits)               |      76,274,229 |  $0.50 / MTok | **$38.14** |   71% |
| Cache writes (1h TTL)            |         832,674 | $10.00 / MTok |  **$8.33** |   16% |
| Output — incl. ~91,262 reasoning |         283,153 | $25.00 / MTok |  **$7.08** |   13% |
| Fresh (uncached) input           |             474 |  $5.00 / MTok |      $0.00 |    0% |
| Web search                       |      6 searches |   $10 / 1,000 |      $0.06 |    0% |
| **Total, at list, interactive**  |                 |               | **$53.61** |       |

Derived from that: **≈ $0.60 per minute** over the 90-minute wall clock, and **≈ 3.5¢ per line** of
the 1,536 committed lines of L4.

Two variants of the same measured run, for readers whose arrangement differs:

| variant                             |      total | why it differs                                                                                                 |
| ----------------------------------- | ---------: | -------------------------------------------------------------------------------------------------------------- |
| 5-minute cache TTL                  | **$50.48** | cache writes bill at 1.25× base rather than 2×                                                                 |
| Batch API (50% off both directions) | **$26.80** | not applicable here — the Batch API is asynchronous, and this run was interactive and human-steered throughout |
| Naive, un-deduped transcript sum    |      ~$118 | **wrong.** See §10's third caveat; recorded only so the error is recognisable if someone reproduces it         |

## A.3 Under a subscription, this run costs nothing and the capacity is ~40 a month

The $53.61 above is what this run would cost billed **per token at list on the API**. It is not what
it cost, and for most people running the pipeline it is not what it would cost.

Claude Code draws on whatever plan the operator already has. Anthropic's published consumer tiers
are Pro at $20/month and **Max from $100/month (5× Pro), with a $200/month 20× tier**; Claude Code
usage on those plans is included in the subscription rather than metered per token. On a Max seat,
this run's **marginal** cash cost was **$0** — it consumed a share of a fixed monthly allowance, not
a line on an invoice.

### A.3.1 What the operator observed, which is not what §A.2 predicts

The operator of this run reports, from the in-session usage display and offered as a fallible
impression rather than a measurement, that the whole session consumed **at most 10% of a weekly
allowance** on a Max 20× seat.

Pro-rate the seat and that is a number this addendum can be checked against:

|                                 |               |
| ------------------------------- | ------------: |
| Max 20× seat                    |  $200 / month |
| ÷ 4 weeks (÷ 4.35 gives $46.03) | $50.00 / week |
| × ≤10%, this session            |   **≤ $5.00** |
| The same session at list (§A.2) |        $53.61 |
| Implied ratio, as a floor       |   **≥ 10.7×** |

Two consequences, and the second is the one that matters.

**Capacity, not value.** At ≤10% of a week, the seat sustains **≥10 runs a week — on the order of 40
a month**, not the "about four" that dividing $200 by $53.61 suggests. Those two numbers answer
different questions and this addendum's first draft ran them together. **$53.61 is a valuation** —
what one encoding is worth per unit of work, the figure to set beside a quote for a lawyer's time.
**Forty a month is the capacity** — what the pipeline can actually be pointed at before anything
binds. Nobody holding a Max seat pays list, so the list figure never governs how often they run it.

**The subscription is worth about an order of magnitude more than list at this workload.** That is a
floor, since "at most 10%" bounds the consumption from above and not below.

One caveat on "forty", so nobody plans a quarter around it. **"Free" here means "already paid for",
not "unlimited"**: plan usage is capped by rolling windows rather than by a token budget, so forty is
a linear extrapolation from one observation of one session, and forty runs crammed into a week is
not the same proposition as forty spread across a month. The claim this addendum will stand behind
is the weaker and more useful one — **the binding constraint on how often this pipeline runs is not
money.**

### A.3.2 Why the gap is that large — two live explanations, neither confirmed

This addendum does not know, and says so rather than picking one.

- **Cache reads may barely register against a plan allowance.** They are 71% of the list invoice
  ($38.14 of $53.61) and 76.3M of the 77.4M tokens this session touched. Strip them and the residual
  is $15.41; strip cache writes too and output alone is **$7.08** — the same order as the ≤$5
  observed. If plan accounting weights a cache hit far below its 0.1× _price_, then list price
  systematically overstates the cost of exactly the long-context agentic work Claude Code does.
- **Or a flat plan is simply priced below list for heavy users**, which is what flat plans are for,
  and the 10× is the subsidy rather than a difference in what is being counted.

The first is testable without guessing: run a session engineered to be cache-read-heavy and
output-light, and watch whether the usage display moves with the reads or with the output. Until
someone does, both stay on the page.

## A.4 What is still not counted

No domain-expert review — HG1 was waived on the record, and the reason is §9.2's, not a shortcut. No
deployment. No human drafting, reading or review time, which for a subject of this size is the
larger cost of the two and is not denominated in tokens at all.
