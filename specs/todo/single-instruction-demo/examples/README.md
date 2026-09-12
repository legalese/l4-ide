# `examples/` — worked illustrations of the P4 fork-register schema

These are **not** fixtures (see `../schemas/README.md` for the one-valid-one-invalid-per-schema
fixtures `etc/go/selftest.mjs` actually asserts against) and **not** a committed corpus subject —
a real body-of-law encoding belongs in `legalese/canon`, not here. They exist to show the
fork-register schema (P4, [`R4-FORK-REPRESENTATION.md`](../R4-FORK-REPRESENTATION.md)) applied to
real statutory text, independent of running the encoding pipeline.

| file | subject | what it shows |
| --- | --- | --- |
| [`nz-online-safety-s5-fork-register.json`](./nz-online-safety-s5-fork-register.json) | one clause of a live NZ bill | three independent, stacked grammatical forks in a single nine-word phrase — a right-node-raising/last-antecedent split, a squinting-modifier (adverb attachment) split, and a design-intent-vs-observed-effect split with a discriminating witness — validated against `fork-register.schema.json` |

Each file's own `note` field says so as well, per schema convention (every register that isn't a
committed subject's real deposit says why). Validate any file here the same way a real deposit
is validated:

```
node etc/go/lib/register-validate.mjs fork-register examples/<file>
```

No `.l4` file backs the `site.file` path these entries name — there is nothing to encode or run,
only the grammar to reason about. If a subject named here is later taken up as a real corpus
encoding, the register moves with it into its proper home and this copy should be deleted rather
than left to drift out of sync.
