# dmn-differential — does the emitted DMN mean what the L4 means?

A prototype, not a gate. See `specs/todo/DMN-DIFFERENTIAL-CI-SPEC.md` for the finding that
motivates it, the design it is one quarter of, and — in §6 — exactly what has and has not been
measured.

## The one-sentence version

`etc/kie-dmn-check` and `etc/camunda-dmn-check` already compare a model's answers against each
case's `expect` block, but that block is **hand-written**, so a green run says *the DMN agrees with
what a human typed*. Derive `expect` from `l4` instead and their existing comparison becomes a
differential between L4 and the lowering — with no change to either harness.

## Use

```sh
# 1. derive expectations from the L4 module itself
python3 etc/dmn-differential/l4-derive-cases.py \
    l4 jl4/examples/dmn/gst-rate.l4 jl4/examples/dmn/gst-rate.cases.json \
    -o /tmp/derived.json

# 2. hand them to the UNMODIFIED engine harnesses
etc/kie-dmn-check/run.sh     jl4/examples/dmn/expected/gst-rate.dmn --cases /tmp/derived.json
etc/camunda-dmn-check/run.sh jl4/examples/dmn/expected/gst-rate.dmn --cases /tmp/derived.json
```

Measured on `gst-rate` at `c873bb5d`: 60/60 evaluations harvested, **0 disagreements** between the
derived and hand-written expectations, and KIE `60/60 value(s) as expected, 50/50 service output
value(s) as expected`, exit 0.

## The negative control matters more than the green run

Perturbing the L4 (`THEN 9` → `THEN 7` in `GST rate percent`) and re-deriving, against the
**unchanged** golden DMN:

```
GST_rate_percent  SUCCEEDED = 9   <<< EXPECTED 7
GST_payable_on    SUCCEEDED = 90  <<< EXPECTED 70
KIE ... 56/60 value(s) as expected   <<< FAILED      # exit 1
```

It names the diverging decisions and the cases they diverge in. A blocking count cannot.

## Three things that will bite whoever picks this up

1. **A stale `l4` silently invalidates everything.** A binary built before `c873bb5d` rejects the
   repo's own `doc/tutorials/multi-temporal-modeling/gst-rate-change-example.l4` with
   `EVAL UNDER RULES EFFECTIVE AT ... expected NUMBER, is DATE`. The first draft of this script was
   written against one, and all 60 of its evaluations failed to typecheck. **Check your binary
   against that tutorial before trusting a run.**
2. **Results pair by source line, never by position.** `l4 run` reports each `#EVAL` as a
   diagnostic carrying `Range: <line>:…` and `Source: eval`. Positional pairing misattributes every
   value after the first evaluation that returns nothing.
3. **FEEL-name folding is not `replace(" ", "_")`.** Hyphens fold too:
   `no GST rate exists before commencement on 1994-04-01` is keyed
   `no_GST_rate_exists_before_commencement_on_1994_04_01`. Getting it wrong fails to bind an
   `ASSUME`, and the decision then reports `UNEVALUABLE` rather than anything obviously wrong.

## Known limits

- **Only `gst-rate` has been run**, which is small, fully lowerable, and carries no Lossy notes. The
  spec's classification table (`DIVERGE-DECLARED`, `ABSENT-DECLARED`, `XPASS`) is therefore designed
  and **never exercised** — the corpus, with its 21 Lossy notes, is where it earns its keep or turns
  out wrong.
- **Only KIE has been run**, not Camunda. Both take `--cases`, so nothing in the design needs
  Camunda-specific work, but that is an argument rather than a measurement.
- `read_signatures` reads `GIVEN`/`GIVETH` with regexes over source lines. Adequate here; it should
  ask the compiler before it meets the corpus.
- Drivers are generated **per case** because an `ASSUME` is declared without a value and cannot be
  shadowed — binding it means replacing the declaration, and two cases may assume different values
  for the same name (`gst-rate`'s pre-commencement floor does).
