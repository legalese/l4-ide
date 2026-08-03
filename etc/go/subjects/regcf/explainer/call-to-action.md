The encoding is not a document about the rules. It runs, it answers questions,
and it will show its working. Here is how to make it answer yours, on your own
machine, end to end.

**This document makes no claim that anything is hosted.** Deploying to a host
other people can reach is outward-facing, and outward-facing work in this
pipeline is gated behind a human approval that has not been given. Everything
below is loopback.

**One. Start the service.**

```
./dev-start.sh
```

**Two. Deploy the corpus.** Both modules go in the bundle: the regulation module
carries no exported entry points of its own, and the façade module supplies
them.

```
cd jl4/examples/legal/regcf
zip -r /tmp/regcf.zip regcf.l4 regcf-wizard.l4
curl --fail -X POST http://localhost:8080/deployments -F id=regcf -F sources=@/tmp/regcf.zip
```

**Three. Wait for it, and this step is not optional.** That POST answers
immediately and compiles asynchronously. A tool listing issued in the gap comes
back with a perfectly healthy response carrying only the service's own generic
tools and none of the regulation — a green-looking result that blames the
corpus. Poll first:

```
curl --fail http://localhost:8080/deployments/regcf   # wait for .status == "ready"
```

**Four. Ask it something.** The interface is a JSON-RPC endpoint that a model
can call directly:

```
curl --fail -X POST http://localhost:8080/deployments/regcf/.mcp \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

Use `--fail`. A `GET` on that route is refused by design — the transport is
POST-only — and a `curl` without `--fail` swallows the refusal and hands you an
empty result that looks like an answer.

The tools are the exported entry points of the façade module, under their own
names: a check on whether a company can raise at all, an investment-limit
calculator, a resale check, a reporting-exit check, and a control that answers
the investment-limit question **under the rules in force on a date you choose**.
That last one is the whole temporal argument made usable in one call.

**Five. Ask it to show its working.** Append `?trace=full` to an evaluation and
you get the reasoning tree — each step with the rule it applied and the words of
the rule it applied. That is the point of the exercise. A model that answers a
regulatory question out of its own memory is guessing; a model that calls this
and quotes the trace is citing.

**In a web page instead.** The service also registers the same tools with a
browser page, so a model driving a browser can use them:

```
<script src="http://localhost:8080/.webmcp/embed.js" data-scope="regcf"></script>
```

**Three things it will not do, said here rather than discovered.** The
state-graph endpoint returns nothing for the deployed façade, because the
extractor does not follow imports — the state machines are in the module the
façade imports, not in the façade. The façade's own ladder has two leaves and
its query plan is empty, which is the structural cost of the façade being a thin
wrapper rather than a restatement: making the picture interesting would mean
duplicating the statutory connectives, which is the duplication this whole
exercise exists to remove. And a client joining a query plan to a ladder must
join on the stable identifier and not on the atom identifier, whose intersection
across the two responses is empty — join on the wrong one and you will draw one
diagram and answer a different question, with no error anywhere.
