# Call rules over REST

Call a deployment's rules from your own application as a plain REST API, and generate a client from its OpenAPI document. No model is involved: the same inputs always give the same result, which is what back-end workflows, batch jobs and audited systems need.

**Before you start:** a deployment ([Deploy your rules](../deploying-rules/exporting-rules-for-deployment.md)). For API keys, permissions and self-hosted addresses, see [Choose an integration](README.md).

The examples use the `insurance-premium` deployment from [Deploy your rules](../deploying-rules/exporting-rules-for-deployment.md). Replace `{orgSlug}` with your organization and `sk_...` with an API key.

---

## Names in the API

In addresses and arguments, spaces in names become hyphens: the rule `` `qualifies for discount` `` is called as `qualifies-for-discount`, and the field `` `risk score` `` is passed as `"risk-score"`.

## List the rules

```bash
curl https://api.legalese.cloud/{orgSlug}/insurance-premium/functions \
  -H "Authorization: Bearer sk_..."
```

## Run a rule

Send the rule's inputs under `arguments` to `/functions/{name}/evaluation`:

```bash
curl -X POST https://api.legalese.cloud/{orgSlug}/insurance-premium/functions/qualifies-for-discount/evaluation \
  -H "Authorization: Bearer sk_..." \
  -H "Content-Type: application/json" \
  -d '{
    "arguments": {
      "applicant": {
        "age": 35,
        "risk-score": 0.4,
        "existing-customer": true
      }
    }
  }'
```

```json
{
  "contents": { "presumed": [], "result": { "value": true } },
  "report": "default",
  "tag": "SimpleResponse"
}
```

The answer is in `value`, under `result`. With the same applicant, `calculate-premium` gives `{ "value": 1400 }`.

`presumed` lists the inputs the call left out that took a default (a `TYPICALLY` value, or `NOTHING` for a `MAYBE`) and that the answer used; here there are none. `report` says which report the answer carries; the default report is the only one so far.
The one exception to "a left-out input takes its default" is an event's party or action record in a request for a rule that describes obligations, in a batch case as in a single request: every field of it must be written, and a request that leaves one out is answered with an error (see [An event's party and action record](../../reference/types/TYPICALLY.md#an-events-party-and-action-record)).
The typed schema of an event is published in the function document (`GET .../functions/{fn}`) and in `openapi.json` under each batch case's `events`; the [service's own documentation](../../../jl4-service/README.md#an-events-party-and-action) says more.

## Read the answer

What `value` holds depends on what the rule gives back:

| The rule gives back                                    | `value` is                                                                                                                  |
| ------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------- |
| `TRUE` or `FALSE`                                      | `true` or `false`                                                                                                           |
| a number                                               | that number; one that is not whole comes back as a decimal, to about 16 significant digits: a third is `0.3333333333333333` |
| a string                                               | that string                                                                                                                 |
| a `DATE`                                               | the date as text, year first: `"2026-01-31"`                                                                                |
| `NOTHING`, from a `MAYBE`                              | `null`                                                                                                                      |
| `JUST` a value, from a `MAYBE`                         | the value itself, with nothing around it                                                                                    |
| a list                                                 | a JSON array, even when the list has only one item                                                                          |
| one of a list of choices, such as `` `under review` `` | the name as a string, without backticks: `"under review"`                                                                   |
| a record, such as a `Pair` of `left` and `right side`  | an object with one key, the record's name, holding its fields: `{"Pair": {"left": 5, "right side": 6}}`                     |

Four things to know:

- Field names inside an answer are spelled as the rule spells them, spaces included; they are not turned into hyphens.
- A rule that gives back a `MAYBE` of a `MAYBE` answers `null` both for `NOTHING` and for `JUST NOTHING`, so the two cannot be told apart.
- Each rule's description includes a `returnSchema` for its answer. It does not show the record's name around a record's fields, or that a `MAYBE` answer can be `null`; go by the table above for those two.
- A long list can come back cut short. A list answer of around 200 items or more may end with two `null`s in place of the rest, still with status 200, so two `null`s at the end of a long list mean it was cut, not that items were empty.

## Ask only the questions that matter

The query-plan endpoint takes the inputs you have so far and returns the inputs that are still needed, ranked by how much they can change the result:

```bash
curl -X POST https://api.legalese.cloud/{orgSlug}/insurance-premium/functions/calculate-premium/query-plan \
  -H "Authorization: Bearer sk_..." \
  -H "Content-Type: application/json" \
  -d '{"arguments": {"applicant": {"existing-customer": true}}}'
```

## Evaluating many cases at once

Sometimes you have a list of cases rather than one: every row of a spreadsheet of applicants, say, or every claim in last month's file.
You can send them all in one request, to the rule's batch operation; the spec lists it beside the rule's ordinary operation, under a path that ends in `/evaluation/batch`.
Give each case an `@id` of your own, such as its row number, so that you can match each answer to its row.
The `@id` must be a whole number, and every case needs one; the service does not check that they are all different. For a rule that takes three yes-or-no facts:

```json
{
  "outcomes": [],
  "cases": [
    { "@id": 1, "walks": true, "eats": true, "drinks": true },
    { "@id": 2, "walks": false, "eats": true, "drinks": true }
  ]
}
```

The request must include `outcomes`; an empty list is fine, because every case comes back with the rule's whole answer.

The request as a whole has to be well formed before any case is looked at. If one case has no `@id`, or an `@id` that is not a whole number (`"APP-0042"`, or `1.5`), or `outcomes` is missing, the service turns the whole request away with an error, and no case is evaluated.

Each case comes back with its own answer, under its `@id`, in the order you sent them:

```json
{ "@id": 1, "@presumed": [], "value": true }
```

What else a case can carry:

- **`@error`**: the case failed, and the message says why, for example a fact the rule needs that the case left out. Once the request has been accepted, a case that fails does not spoil the others: they still get their answers.
- **`@limit`**, beside `@error`: the service stopped the case because it took longer than the service allows (`"time"`) or used more memory than it allows (`"memory"`). Sending it again may give an answer, for a `"time"` case especially when the service is less busy. A `"memory"` stop does not depend on what earlier cases worked out, so the same case sent again under the same limit is stopped again; a `"time"` stop can differ from one try to the next, because the time limit is measured on the clock and depends on how busy the service is. <!-- decided by Claude 2026-11-26, pending Meng's review (smucclaw/l4-ide#1116) -->
- **`@refused`**: the rule itself declined to answer this case, and says why. A case turned away before the rules ran is an `@error`, not `@refused`.
- **`@presumed`**: the usual values the case's answer rests on, as [What `presumed` lists](../../reference/types/TYPICALLY.md#what-presumed-lists) describes them. An empty list means the answer rests only on what the case supplied.

For every detail of the request and the response, see the [decision service's own documentation](../../../jl4-service/README.md#batch-evaluation).

## Turn the defaults off

Some inputs have a default, written with [`TYPICALLY`](../../reference/types/TYPICALLY.md): a value the rule uses when a request leaves that input out, and `presumed` says so.
To have a rule use no default at all, send `"presumption": "hard"`.
The input the request leaves out is then missing, as it would be if it had no default.
For an ordinary rule that holds whether or not the rules would have read it; [At the boundary](../../reference/types/TYPICALLY.md#at-the-boundary-l4-batch-and-the-decision-service) says what `hard` does for a rule that describes obligations.
A request to `/evaluation` is answered with HTTP status 422 and a message that names the input, such as `Parameter 'c': missing required parameter (it has a TYPICALLY default, but presumption is hard, so the default is not used)`.
The value `"soft"` is the default: it uses the defaults, as a request without the field does.

In a request to `/evaluation`, `presumption` sits beside `arguments`, not inside it:

```json
{
  "arguments": {
    "applicant": { "age": 35, "risk-score": 0.4, "existing-customer": true }
  },
  "presumption": "hard"
}
```

In a batch request it sits at the top of the request body, beside `outcomes` and `cases`, and applies to every case:

```json
{
  "outcomes": [],
  "cases": [{ "@id": 1, "walks": true, "eats": true, "drinks": true }],
  "presumption": "hard"
}
```

A batch request is still answered with status 200, and a case that leaves such an input out is an `@error` naming it, while the other cases are answered:

```json
{
  "@error": "Parameter 'b': missing required parameter (it has a TYPICALLY default, but presumption is hard, so the default is not used)",
  "@id": 1,
  "@presumed": []
}
```

In the `summary` (the part of the batch response that counts the cases), that case is counted in `casesIgnored`, the cases that failed with an `@error`, and not in `casesProcessed`.
Without `"presumption": "hard"` the same case is answered with the default, and its `@presumed` lists `b`.
Each case still carries its own `@presumed`.
A default that the rules take inside their own text is still used, and still listed, under `"hard"`, because no request could have supplied it.
The two values are accepted in any capitalisation, and any other value is an error.
A deployment has no setting that makes `"hard"` the default: each request, batch request or tool call sends the switch itself.
An AI agent sets the same switch through [MCP](ai-agents.md#telling-a-rule-not-to-assume-anything).

## Generate a client from the OpenAPI document

Every deployment publishes an OpenAPI document, with one operation per exported rule: the `GIVEN` inputs as the request body and the rule's result as the response.

```bash
curl https://api.legalese.cloud/{orgSlug}/insurance-premium/openapi.json \
  -H "Authorization: Bearer sk_..."
```

Give the address to any OpenAPI tool, or import it into Postman, Insomnia or Swagger UI:

```bash
openapi-generator-cli generate \
  -i https://api.legalese.cloud/{orgSlug}/insurance-premium/openapi.json \
  -g typescript-fetch -o ./generated
```

The document is regenerated on every redeploy. Run the generator again after a deploy that changes a rule's inputs or result.
