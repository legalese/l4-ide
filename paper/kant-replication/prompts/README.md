# Cell prompts

Five distinct cells. The 2 × 3 factorial has six boxes but the **vanilla** condition involves
no encoding, so it is shared between the two languages — as `FOUNDATION.md` §5.1 already notes.

| cell              | prompt                    | derived from                                                               |
| ----------------- | ------------------------- | -------------------------------------------------------------------------- |
| `vanilla`         | `cell-vanilla.md`         | the paper's Appendix A.3.1, verbatim in substance                          |
| `prolog-unguided` | `cell-prolog-unguided.md` | the paper's Appendix A.3.2, verbatim in substance                          |
| `prolog-guided`   | `cell-prolog-guided.md`   | the paper's Appendix A.3.3 pattern + `bench/schema-prolog.md`              |
| `l4-unguided`     | `cell-l4-unguided.md`     | a mechanical translation of `cell-prolog-unguided.md`                      |
| `l4-guided`       | `cell-l4-guided.md`       | a mechanical translation of `cell-prolog-guided.md` + `bench/schema-l4.md` |

**The L4 prompts are translations, not rewrites.** They change the language name, the output
file contract, and nothing else. Where the Prolog prompt says something that has no L4
analogue (e.g. "do not redefine built-in predicates"), the nearest true statement is used and
the substitution is noted in the file. Any instruction that would help one arm and not the
other is a confound, and the point of writing them this way is that a reader can diff them.

## Two deviations from the original, both deliberate, both applied to every cell equally

**Encoders may check that their artifact loads; they may not run the nine queries.** The
original gave models no toolchain at all, which is why some of its encodings did not compile.
Letting both arms bring their own checker to the same bar — "it loads cleanly" — is the fair
version of that affordance, and each trial records whether it was used. Note that this is not
neutral between the languages and is not meant to be: L4's bar is a type check and Prolog's is
a parse, and the difference is a property of the languages that `FOUNDATION.md` §3.4 says is
part of what is being measured.

**Encoders never see the answer key.** They get `fixtures/chubb-policy.txt` and
`fixtures/queries-blind.md`. `bench/keys.json` is off limits.

## The contamination problem, stated because it cannot be fixed here

The policy (Appendix A.1) and all nine queries **with their answers** (Appendix A.2) have been
on arXiv since February 2025. A model with a later cutoff may be recalling the key rather than
deriving it. **This cuts against L4 in one direction and for it in another**: the vanilla cell
is pure recall risk, and the Prolog cells have published sibling encodings to recall while the
L4 cells have none — but the L4 cells are also asking for a language with a far smaller
pretraining footprint than Prolog, which cuts the other way and is not a small effect. Neither
is controlled in this pilot. The perturbation control that would separate recall from
derivation is specified in `FOUNDATION.md` T4 and is not run here.
