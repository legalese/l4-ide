# Query Planning

The **query planner** turns a rule that decides `TRUE` or `FALSE` into a question-and-answer session.
Given the answers so far, it says whether the outcome is already settled and, if it is not, which inputs are still needed and which to ask next.

## An example

```l4
GIVEN
  adult IS A BOOLEAN
  citizen IS A BOOLEAN
  resident IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE `may vote` IF adult AND (citizen OR resident)
```

If `adult` is answered `FALSE`, the outcome is settled, and neither `citizen` nor `resident` is asked.
If it is answered `TRUE`, both are still needed.

## What it asks first

An input that can no longer change the outcome is not asked.
Of the inputs still needed, the planner puts first those whose answer could settle the outcome.
It treats every input as equally likely to be answered either way, so a [TYPICALLY](../types/TYPICALLY.md) value does not change the order.

## Where you meet it

- The ladder diagram in the web app uses the plan to show which inputs are still needed and which to ask next.
- `jl4-service` answers the same question for a deployed rule, at `POST /deployments/{id}/functions/{fn}/query-plan`; the service's README describes the request and the reply.

## See also

- [TYPICALLY](../types/TYPICALLY.md): writing down the usual value of an input
