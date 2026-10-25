# Provenance of the reference LTSs

These three `.aut` files are the oracle for the bisimulation check of [REGULATIVE-LOWERING-SPEC.md](../../../../../specs/proposals/REGULATIVE-LOWERING-SPEC.md) §6.2.
They are the probes' hand models of the brief's system, one per design, as labelled transition systems in mCRL2's Aldebaran format, relabelled to the dinner names of the fixtures beside this directory.
Nothing in this repository reads the private repository they were relabelled from, and nothing here needs it to be rebuilt: the relabelled sources are vendored beside the `.aut` files.

| file     | design                   | states | transitions | labels                                                                                                      |
| -------- | ------------------------ | ------ | ----------- | ----------------------------------------------------------------------------------------------------------- |
| `d1.aut` | D1, naive                | 12     | 21          | `step(BobBuys)`, `step(Deliver)`, `step(CheckBought)`, `step(Done)`, `step(Buy)`, `step(Abandon)`           |
| `d2.aut` | D2, re-read then buy     | 15     | 30          | as D1 without `Buy` and `Abandon`, plus `step(ReadAgain)`, `step(NoAnswer)`, `step(Send)`, `step(AbandonR)` |
| `d3.aut` | D3, atomic check-and-buy | 10     | 21          | as D1 without `Buy` and `Abandon`, plus `step(BuyChecked)`, `step(NoAnswer)`                                |

The counts were read from each file's `des (0,T,S)` header and confirmed by `ltsinfo`.

## How they were built

Built on 2026-10-26 with mCRL2 202607.0 (Release), the macOS arm64 bundle, as `mcrl22lps --version` prints it.
From this directory, with the mCRL2 tools on `PATH` and a scratch directory for the intermediate `.lps`:

```sh
mcrl22lps -q d1-viz.mcrl2 "$SCRATCH/d1.lps"
lps2lts   -q "$SCRATCH/d1.lps" d1.aut
```

and the same for `d2` and `d3`.
Both tools are deterministic here: rebuilding gives byte-identical files.

## Where the sources came from

Each `dN-viz.mcrl2` is a relabelled copy of the probes' `verification/mcrl2/build/dN-viz.mcrl2` in the private `legalese/solutions` repository at commit `b0de1114bfeca12a9305125bbea87c7941fb37d2` (draft PR legalese/solutions#1), the data-free build whose only action is `step(t)`.
The relabelling renamed sorts, state variables, constructors and transitions, and rewrote every comment; it added, removed and reordered nothing.
The map from the original names is kept in the private record, as the spec says (§6.2), and none of the original names appears in this directory.

Three checks, run on 2026-10-26, show that the relabelling preserved the model:

1. **Tokens.** With comments removed and the private map applied to the original source, the original and the relabelled source are the same sequence of tokens: 1,039, 1,045 and 1,037 tokens for D1, D2 and D3.
2. **Graphs.** The original source built by the same two commands gives LTSs with the same counts, 12/21, 15/30 and 10/21; after the private map is applied to its labels (four of them differ) each is byte-identical to the `.aut` here.
3. **Bisimulation.** `ltscompare -ebisim` and `ltscompare -ebranching-bisim` of each renamed original against the `.aut` here print `true`; as a control, `ltscompare -ebisim d1.aut d3.aut` prints `false`.

Check 2 is the strongest of the three: byte identity is isomorphism with the states numbered the same, which no equivalence of `ltscompare` states directly (in 202607.0 its `--help` lists none for isomorphism).
Check 3 is the comparison the harness in [`../../harness/`](../../harness/README.md) makes (spec §6.2), run here once so that its command is known to answer both ways.

## Hashes

SHA-256, of the files in this directory as committed:

| file           | SHA-256                                                            |
| -------------- | ------------------------------------------------------------------ |
| `d1-viz.mcrl2` | `97168f60d833dbfbf77da390b45fef222c6445b372a06c3f1ec48210447319bd` |
| `d2-viz.mcrl2` | `c2b8b67a8627d6ccc769848ba6e684ccdc8f702032f406ba9c17cde7a8b26eb8` |
| `d3-viz.mcrl2` | `127cd70e83c66244744893f0aa1d809eafedcb43a1931252fc2834735b8b0a59` |
| `d1.aut`       | `981104041e01d2ad2c557823c7ff8bd91a8793a22de817f4d680359ba5bf7ab1` |
| `d2.aut`       | `daeabb40f0de14cd6656e818869b949ade5d91d01e60d34eb8bd9ff95444728b` |
| `d3.aut`       | `57754f38e34d745870b094976c1a99388e2d51145a9e18f5aadc1b99310de086` |

and of the original sources they were relabelled from, at the commit above, so that a changed brief cannot leave the bisimulation green against a stale oracle:

| original source | SHA-256                                                            |
| --------------- | ------------------------------------------------------------------ |
| D1              | `6cd202c88fae64cb4eddaad28ed911b4224e3461da57db637375931985ff925b` |
| D2              | `8aec0a6e7331aba55f312e60dc846f09d5337cf4bbae5ea653176e0f9b6ea536` |
| D3              | `98df25f0da1aad6c5400ff3fe08b7062755ab1d894418753d068e46819a395e7` |

## Reading the labels against the fixtures

The fixtures name their acts in L4, and one L4 act can stand for two labels: a `BOOLEAN` payload `ledger answered` splits the act that asks the ledger into its answered and unanswered cases.
The [README](../README.md) one directory up has the table from each fixture's acts to these labels.
