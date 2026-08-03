The encoding is not a document about the rules. It runs, it answers questions,
and it will show its working. Here is how to make it answer yours, on your own
machine, end to end.

**This document makes no claim that anything is hosted.** Deploying to a host
other people can reach is outward-facing, and outward-facing work in this
pipeline is gated behind a human approval that has not been given. Everything
below is loopback.

**One. Start the service.** Bare `./dev-start.sh` prints instructions and starts
nothing; the mode that runs the decision service is `service-only`. The fresh
store path is deliberate rather than tidy: deployment ids are reused, so a
deployment called `regcf` left in the default store by an earlier session
answers as `ready` before yours has compiled, and you will be reading somebody
else's corpus with nothing anywhere to tell you so.

```
JL4_SERVICE_STORE=$(mktemp -d) ./dev-start.sh service-only
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
corpus. Poll until `status` reads `ready`. Do **not** add `--fail` here: until the
deployment record exists the route reports the deployment as not found, which
is the ordinary first answer rather than a failure — and `--fail` turns it into
a non-zero exit that ends your loop on the normal case.

```
curl http://localhost:8080/deployments/regcf
```

**Four. Ask it something.** The interface is a JSON-RPC endpoint that a model
can call directly:

```
curl --fail -X POST http://localhost:8080/deployments/regcf/.mcp \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

Use `--fail` on this one. A `GET` on that route is refused by design — the
transport is POST-only — and a `curl` without `--fail` swallows the refusal and
hands you an empty result that looks like an answer.

What comes back is every tool the deployment serves, which is **not** the same
as the module's exported entry points: the service adds generic file-browsing
tools of its own to every deployment, whatever the module contains. The
paragraph at the end of this section names the tools this run's service actually
enumerated, and how many of them came from the module. Nothing in this section
enumerates them by hand.

The one worth calling first is the law-time control. The corpus exports the
investment-limit calculation twice — once as it stands today, and once
[under the rules in force on a chosen date — for checking a past investment against the rules that actually applied to it](src:jl4/examples/legal/regcf/regcf-wizard.l4#L585 "verbatim").
Call the second with a `rule date` from before the substantive amendment and
again with one from today, on the same income and net worth, and you get the two
figures the **How much** section above describes, out of the same code, with
nothing switched by hand.

**Five. Ask it to show its working.** Evaluation has a REST route of its own —
`POST /deployments/{id}/functions/{fn}/evaluation` — and the service's own
documentation describes how to make it explain itself:

> [Include execution traces with `?trace=full` or the `X-L4-Trace: full` header. Add `?graphviz=true` to include DOT source in the response (requires `trace=full`).](src:jl4-service/README.md#L168 "verbatim")

Each node of that tree names the rule that was applied and the expression it
evaluated. It does **not** quote the Federal Register: there is no citation
field in a trace node. What makes the trace readable as law here is a property
of _this corpus_ rather than of the tool — the field names are the regulation's
own words, so a node reading `has sold securities in reliance on section 4(a)(6)
and has not filed the ongoing annual reports…` is quoting the rule only because
somebody made the identifier the rule. Point the same machinery at a corpus with
terse names and the trace stops being quotable. That is the argument for the
naming discipline this document keeps pointing at, made from the other end.

**In a web page instead.** The service also registers the same tools with a
browser page, so a model driving a browser can use them:

```
<script src="http://localhost:8080/.webmcp/embed.js" data-scope="regcf"></script>
```

The [`data-scope`](src:jl4-service/README.md#L375 "verbatim") attribute filters
by deployment and by function. This run exercised the JSON-RPC endpoint and not
the browser embed, so treat this block as documented rather than as measured
here.

**Three things it will not do, said here rather than discovered.** The
state-graph endpoint returns nothing for the deployed façade, because the
extractor does not follow imports — the state machines are in the module the
façade imports, not in the façade. The façade's own ladder diagram has two
leaves and its query plan is empty, which is the structural cost of the façade
being a thin wrapper rather than a restatement: making the picture interesting
would mean duplicating the statutory connectives, which is the duplication this
whole exercise exists to remove. And if you draw a query plan's ranked atoms
onto a ladder diagram, join them on the `unique` field and not on `atomId` —
the two sides number their atoms independently, so joining on `atomId` draws one
diagram and answers a different question, with no error anywhere.
