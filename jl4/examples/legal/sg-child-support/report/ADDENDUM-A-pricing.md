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

## A.3 Under a subscription, the cash cost of this run is nothing

The $53.61 above is what this run would cost billed **per token at list on the API**. It is not what
it cost, and for most people running the pipeline it is not what it would cost.

Claude Code draws on whatever plan the operator already has. Anthropic's published consumer tiers
are Pro at $20/month and **Max from $100/month (5× Pro), with a $200/month 20× tier**; Claude Code
usage on those plans is included in the subscription rather than metered per token. On a Max seat,
this run's **marginal** cost was **$0** — it consumed a share of a fixed monthly allowance, not a
line on an invoice.

Two honest consequences, in both directions:

- **The subscription pays for itself quickly at this workload.** A $200/month Max 20× seat is worth
  about **four runs of this size** at list. A team encoding one body of law a week is, in list-price
  terms, getting roughly **$215/month of inference for $200** — the fourth run crosses the
  line, and everything after it is free until the usage window binds.
- **"Free" means "already paid for", not "unlimited".** Plan usage is capped by rolling windows, not
  by tokens, so the ceiling is _how many such runs fit in a window_, which this run does not
  measure and which this addendum therefore does not claim. The list-price figure is the one that
  is comparable across arrangements, which is why §A.2 leads with it.

The reason to state both is that they answer different questions. **$53.61** answers _what is this
capability worth per unit of work_ — the number to put beside a quote for a lawyer's time.
**$0 marginal** answers _what does it cost me to run it again this afternoon_, which is the number
that decides whether anyone actually does.

## A.4 What is still not counted

No domain-expert review — HG1 was waived on the record, and the reason is §9.2's, not a shortcut. No
deployment. No human drafting, reading or review time, which for a subject of this size is the
larger cost of the two and is not denominated in tokens at all.
