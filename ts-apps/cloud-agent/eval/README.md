# Harness eval

Runs the real harness on small statute-to-L4 tasks and scores the result, so a
change to the tools, the prompt or the model can be judged on evidence. Run it
before and after a change that trades tokens against accuracy.

```bash
# Prove every task first: its reference must pass, its seed must fail.
node eval/run.mjs --check-tasks --l4 l4

# Run against a local backend (npm run build first). This spends model tokens.
node eval/run.mjs --ai-url http://localhost:3000 --lsp jl4-lsp --l4 l4 --out after.json

node eval/run.mjs --compare before.json after.json
```

It reports whether each answer is correct and compiles, plus rounds, tokens and
seconds. "Correct" means the task's `oracle.l4` passes.

## Rules for tasks

- **Public-domain text only.** US federal statutes are. Never use client
  documents or anything else private.
- **Expected values are written by hand**, in `oracle.l4`, from the statute.
  Never generate them with a model. The agent writes its own tests too, and
  those prove little, so they aren't what's scored.
- **Each task states the function names and types**, so the oracle can call them.
- **`keepLines`** lists text that must survive. It catches a model that makes a
  failing test pass by editing the test.
- **Keep some tasks out of your tuning.** A prompt tuned to these exact tasks
  would pass them without getting better, so judge prompt changes on tasks you
  didn't look at while writing them.

Model-written L4 can call `FETCH` or `POST`, so scoring blocks the network
(`sandbox-exec` on macOS, `unshare` on Linux) and refuses to run without that
unless you pass `--allow-network`.
