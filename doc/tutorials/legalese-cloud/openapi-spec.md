# RESTful OpenAPI Specification

Every deployment publishes an OpenAPI (Swagger) JSON document so third-party systems can generate clients and call your rules as a plain REST API.

**Prerequisites:** A deployment ([Exporting Rules for Deployment](../deploying-rules/exporting-rules-for-deployment.md))

---

## When to Use This

Use the OpenAPI spec for **deterministic, server-to-server** integration: each exported rule is a typed REST operation with a documented request and response schema. No model is involved — the same inputs always produce the same decision, which is what you want for backend workflows, batch jobs, and audited systems.

For conversational or agent-driven use, see the [OpenAI- and Anthropic-compatible AI APIs](./openai-compatible-api.md) or [MCP server](./mcp-server.md).

## Endpoint

**Legalese Cloud:**

```
https://api.legalese.cloud/{orgSlug}/{deploymentId}/openapi.json
```

**Self-hosted jl4-service:**

```
http://{serviceUrl}/{deploymentId}/openapi.json
```

The VS Code **Integrate** dialog pre-fills the correct URL for your connection.

## Authentication

- **Legalese Cloud:** bearer token — your signed-in session or an API key (`Authorization: Bearer sk_...`) from the [console](https://legalese.cloud). Uses the `l4:rules`, `l4:evaluate` and `l4:read` permissions.
- **Self-hosted:** whatever auth your `jl4-service` is configured with.

### Legalese Cloud Permissions

| Permission    | Enables                                                                                                                      |
| ------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `l4:rules`    | Enumerate the deployment's rules — which REST operations (paths) the spec exposes.                                           |
| `l4:read`     | Fetch `openapi.json` itself: the request/response **schemas** for every operation. Code generators and Swagger UI need this. |
| `l4:evaluate` | Call an operation — POST inputs to a rule and receive its computed decision.                                                 |

A common split: a build-time key with `l4:rules` + `l4:read` to (re)generate clients from the spec, and a separate runtime key that also has `l4:evaluate` for the service that actually calls the rules.

## Use It

### Inspect the spec

```bash
curl https://api.legalese.cloud/{orgSlug}/{deploymentId}/openapi.json \
  -H "Authorization: Bearer sk_..."
```

The document lists one path per exported rule, with the `GIVEN` parameters as the typed request body and the rule's decision as the response.

### Generate a client

Feed the URL to any OpenAPI tool:

```bash
# openapi-generator
openapi-generator-cli generate \
  -i https://api.legalese.cloud/{orgSlug}/{deploymentId}/openapi.json \
  -g typescript-fetch -o ./generated

# or import the URL into Postman / Insomnia / Swagger UI
```

### Call a rule

```bash
curl https://api.legalese.cloud/{orgSlug}/{deploymentId}/<rule-operation> \
  -H "Authorization: Bearer sk_..." \
  -H "Content-Type: application/json" \
  -d '{ "applicant": { "age": 40, "risk-score": 0.8 } }'
```

The exact path and request shape for each rule come straight from the spec.

## Evaluating many cases at once

Sometimes you have a list of cases rather than one: every row of a spreadsheet of applicants, say, or every claim in last month's file.
You can send them all in one request, to the rule's batch operation; the spec lists it beside the rule's ordinary operation, under a path that ends in `/evaluation/batch`.
Give each case an `@id` of your own, such as its row number, so that you can match each answer to its row. For a rule that takes three yes-or-no facts:

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

Each case comes back with its own answer, under its `@id`, in the order you sent them:

```json
{ "@id": 1, "@presumed": [], "value": true }
```

What else a case can carry:

- **`@error`**: the case failed, and the message says why, for example a fact the rule needs that the case left out. A case that fails does not spoil the others: they still get their answers.
- **`@limit`**, beside `@error`: the service stopped the case because it took longer than the service allows (`"time"`) or used more memory than it allows (`"memory"`). A case like that may be worth sending again: a `"time"` case when the service is less busy, and either kind to a service with a higher limit. A case with `@error` and no `@limit` will fail the same way again, so change the case before you send it again.
- **`@refused`**: the rule itself declined to answer this case, and says why.
- **`@presumed`**: the facts the case left out for which the rule used its usual value instead, by name. An empty list means the answer rests only on what the case supplied.

For every detail of the request and the response, see the [decision service's own documentation](https://github.com/legalese/l4-ide/blob/main/jl4-service/README.md#batch-evaluation).

## Notes

- The spec regenerates on every redeploy, so generated clients stay in sync — re-run codegen after a schema-changing deploy.
- Responses are the rule's typed decision, suitable for storing as an auditable record.
- A self-hosted `jl4-service` serves the spec at `http://{serviceUrl}/{deploymentId}/openapi.json`.
