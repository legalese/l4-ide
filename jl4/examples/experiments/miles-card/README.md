# Miles-card routing — "choose a credit card"

A two-stage decision app: given a transaction, pick which miles card to tap.
This is the worked example that motivated the display-width / ditto (`^`) column
work in the dmnmd→L4 backend.

## Files

| File | Role |
|------|------|
| `categorize.dmn.md` | dmnmd decision table → `Categorize` (txn → spend category) |
| `card-to-use.dmn.md` | dmnmd decision table → `CardToUse` (category + caps → card + mpd) |
| `miles-card.l4` | Generated L4 (both tables), with a runnable `#EVAL` demo at the bottom |

The `.dmn.md` tables are the **source of truth**; `miles-card.l4` is generated.

## Pipeline

```
cd <dmnmd>/languages/haskell
cabal run -v0 dmnmd -- -t l4 categorize.dmn.md    # default fn name f1     -> rename Categorize
cabal run -v0 dmnmd -- -t l4 card-to-use.dmn.md    # type F1 / ctor mkF1 / fn f1 -> rename CardToUse / mkCardToUse
```

Concatenate the `Categorize` block, a blank line, then the `CardToUse` block.
The emitter lays out each `BRANCH` row as a column-aligned ditto grid, where `^`
copies the token at the same start column on the previous line — alignment that
is display-width-accurate (wide chars advance two columns), which is the property
this example ultimately exercises.

## Run it

```
l4 check miles-card.l4    # typecheck only
l4 run   miles-card.l4    # typecheck + evaluate the #EVAL directives
```

## Provenance

Encodes the "Spend → card waterfall" from a personal miles-card cheatsheet
(revised periodically). The 2026-07 revision split Tesla charging into two
categories — `TeslaSupercharger` (Tesla in-app billing → always flat PRVI, can't
earn yuu) vs `TeslaChargePlus` (Charge+ stations → yuu while the cap has room,
else PRVI) — which the `#EVAL` block demonstrates.
