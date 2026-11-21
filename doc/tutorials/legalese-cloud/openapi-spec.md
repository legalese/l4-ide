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
        "is-existing-customer": true
      }
    }
  }'
```

```json
{ "contents": { "result": { "value": true } }, "tag": "SimpleResponse" }
```

The answer is in `value`, under `result`. With the same applicant, `calculate-premium` gives `{ "value": 1400 }`.

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
| a choice that carries data, such as `Card` with a fee  | an object with one key, the choice's name, holding its fields: `{"Card": {"card fee": 2}}`; send it the same way            |
| `LEFT` or `RIGHT` of a value, from an `EITHER`         | an object with one key, `LEFT` or `RIGHT`, holding the value in an array of one: `{"RIGHT": [5]}`; send it the same way     |

A type with only one choice, named like the type, such as ``DECLARE `Deposit Refund` IS ONE OF `Deposit Refund` HAS amount IS A NUMBER``, is a record: it comes back as a record does, `{"Deposit Refund": {"amount": 40}}`, and you send its fields alone, `{"amount": 40}`.

An input that is one of a list of choices is sent as one of its names.
Any other value, such as a name the type does not have, a number or `true`, is refused with status 422 and a message that names the input and the names it takes: ``Parameter 'payer': a `Party` is one of the strings "Landlord", "Tenant", the names of its constructors``.

An input of type `EITHER` is sent as it is answered: `{"the claim": {"RIGHT": [2000]}}` or `{"the claim": {"LEFT": ["withdrawn"]}}`, the value in an array of one.
Any other form, such as a bare `2000`, `{"RIGHT": 2000}` without the array, or an object with both keys, is refused with status 422 and a message that names the input:

```json
{
  "contents": {
    "contents": "Parameter 'the claim': an EITHER is written {\"LEFT\": [value]} or {\"RIGHT\": [value]}",
    "tag": "InterpreterError"
  },
  "tag": "Error"
}
```

Five things to know:

- Field names inside an answer are spelled as the rule spells them, spaces included; they are not turned into hyphens.
- A rule that gives back a `MAYBE` of a `MAYBE` answers `null` both for `NOTHING` and for `JUST NOTHING`, so the two cannot be told apart.
- Each rule's description includes a `returnSchema` for its answer. It does not show the record's name around a record's fields, or that a `MAYBE` answer can be `null`; go by the table above for those two.
- A long list can come back cut short. A list answer of around 200 items or more may end with two `null`s in place of the rest, still with status 200, so two `null`s at the end of a long list mean it was cut, not that items were empty.
- A rule can decline to answer, with a reason its author wrote ([REFUSE](../../reference/control-flow/REFUSE.md)). The call then has no `value`: it answers with status 200 and `{"contents": {"kind": "refused", "reason": "…"}, "tag": "Refused"}`. Tell it from an answer by its `"tag": "Refused"`; a 422 is only an evaluation that stops with an error.

## Ask only the questions that matter

The query-plan endpoint takes the inputs you have so far and returns the inputs that are still needed, ranked by how much they can change the result:

```bash
curl -X POST https://api.legalese.cloud/{orgSlug}/insurance-premium/functions/calculate-premium/query-plan \
  -H "Authorization: Bearer sk_..." \
  -H "Content-Type: application/json" \
  -d '{"arguments": {"applicant": {"is-existing-customer": true}}}'
```

A rule that may decline to answer has no query plan: the endpoint answers with status 400, `"kind": "declined"`, and the reasons the rule may decline with ([The query plan](../../reference/control-flow/REFUSE.md#the-query-plan)).

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
