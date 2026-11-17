# Reproducers for the O4 option B review

These are the programs and requests behind the findings in [`../O4-B-EVENT-DEFAULTS-PARKED.md`](../O4-B-EVENT-DEFAULTS-PARKED.md).
They were written by an independent reviewer on 2026-11-18 and replayed on option B as it stands at commit `c99088fbb`.
The answers listed below were recorded in that replay; the author of this directory re-read them and did not re-run them.

**They are not checked by anything.**
`doc/test-docs.sh` type-checks the `.l4` files under `doc/` only, and the corpus goldens cover the globs named in `CLAUDE.md` §3.1, which do not include `specs/`.
So a program here can stop type-checking without any gate noticing.
The answers below are the answers of option B (the build at `c99088fbb`), not of the service as it is today: option A refuses most of these requests.

## How to replay one

1. Build `jl4-service` from `c99088fbb`, and start it with a store directory of your own and an in-memory ledger: `jl4-service --port 8823 --store-path <dir> --ledger-store memory --ledger-allow-nondurable`.
2. Zip the program (for `programs/imp/`, both files) and deploy it: `POST /deployments` as a multipart form with the fields `id` and `sources` (the zip).
3. Send the request file as the body of `POST /deployments/<id>/functions/<function>/evaluation`, with `Content-Type: application/json`.
   A function name with a space is percent-encoded (`outer%20rule`).
4. Read `presumed` and the value in the answer.

Leave the service's evaluation limit at its default (256 MB) for the two scale requests, which are about that limit.

## The requests

| request                                               | program (deploy as)                                    | function               | what it shows, and the answer on `c99088fbb`                                                                                                                                                                     |
| ----------------------------------------------------- | ------------------------------------------------------ | ---------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `nestarg-1`                                           | `programs/nestarg.l4`                                  | `outer rule`           | S1, the baseline. The argument leaves `licence` out; one matching event. `presumed` is `["driver.licence"]`, the value `FULFILLED`.                                                                              |
| `nestarg-2`                                           | same                                                   | same                   | S1. A `drive` event first (skipped on its action), then the same matching event. `presumed` is `[]`, the value `FULFILLED`: the default the answer rests on is not listed.                                       |
| `nestarg-2w`                                          | same                                                   | same                   | S1, the control. As `nestarg-2`, with `licence` written `"learner"` in the argument: the value is a residual obligation, so the verdict of `nestarg-2` does rest on the default.                                 |
| `nestarg-2h`                                          | same                                                   | same                   | S1 under `hard`. 422, `Missing required field 'driver.licence'`: `hard` is right, `soft` drops the entry.                                                                                                        |
| `nest-1`, `nest-2`, `nest-2-h`                        | `programs/nest.l4`                                     | `outer rule`           | S1 with the rules' own default (listed `WITH Driver: licence`), which is taken in both modes. `nest-1`: listed, `FULFILLED`. `nest-2` and `nest-2-h` (a `drive` event first): `presumed` is `[]`, `FULFILLED`.   |
| `nestl-2`                                             | `programs/nest-learner.l4` (the default flipped)       | `outer rule`           | The control for `nest-2`: with the default `"learner"` the value is a residual obligation (and the default is listed), so `nest-2`'s verdict rests on its default.                                               |
| `nestw-2`                                             | `programs/nest-written.l4` (the rule writes `licence`) | `outer rule`           | The other control: with the field written, `FULFILLED` and `[]`, nothing to list.                                                                                                                                |
| `guard-G`, `guard-F`, `guard-L`                       | `programs/multi.l4`                                    | `guard rule`           | C1, a false `PROVIDED`. `guard-G` leaves `licence` out and lists `events[0].party.licence`; `guard-F` writes `"full"` and `guard-L` writes `"learner"`, both `[]`. All three give the same residual obligation.  |
| `early-G`, `early-L`                                  | same                                                   | `early rule`           | C1, an act before its window opens (`AFTER 3`, event at 1). `early-G` lists `events[0].party.licence`; `early-L` (written `"learner"`) gives `[]`; the value is the same.                                        |
| `ord-8c1a95`, `ord-7b174d`                            | `programs/order.l4`                                    | `seatbelt requirement` | C1, a party that differs after the defaulted field (`licence` is declared before `name`). `ord-8c1a95` leaves `licence` out and lists it; `ord-7b174d` writes `"learner"` and gives `[]`; the value is the same. |
| `mb-gap`, `mb-lrn`                                    | `programs/imp/` (both files)                           | `seatbelt requirement` | C1, and the `MAYBE`-of-record defect of the README: a two-key `zhome` is read as `NOTHING`, so the event is skipped, yet `mb-gap` lists `licence`; `mb-lrn` (written) gives `[]` and the same value.             |
| `fk-w-hard`, `fk-w-soft`                              | `programs/fnkey.l4`                                    | `seatbelt requirement` | H1. Every input of the rule `mkAddr` is written. `fk-w-hard` is refused, `Not a constructor 'mkAddr' at 'events[0].party.zhome.mkAddr'`; `fk-w-soft` answers with `[]`.                                          |
| `p2one-100-gap`, `p2one-150-gap`, `p2one-150-written` | `programs/perf2.l4`                                    | `loop only`            | P1. 100 or 150 events, each leaving out one of 20 defaulted fields. 100: answered, 100 entries. 150: HTTP 500, "Evaluation resource limit exceeded". `p2one-150-written` (all fields written): answered.         |
| `p2loop-70-gap`, `p2loop-80-gap`                      | same                                                   | same                   | P1. 70 or 80 events, each leaving out all 20 fields. 70: answered, 1400 entries. 80: HTTP 500.                                                                                                                   |

The finding names (S1, C1, H1, P1) are those of the findings table in the parked spec.
`nestarg.l4` and the `nest*` programs are the shape S1 needs: an `EVALTRACE` evaluated inside a field of the obligation's party.
