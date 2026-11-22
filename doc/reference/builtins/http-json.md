# HTTP and JSON

Built-in functions for calling web APIs and for turning L4 values into JSON and back. They need no `IMPORT`.

**Example:** [http-json-example.l4](http-json-example.l4)

## Where HTTP requests are allowed

`FETCH` and `POST` make a real request every time they are evaluated, and only when their result is needed. They accept `https://` addresses only. Where L4 runs in safe mode, as it does in the browser, both give an error instead of making a request.

## When a request fails

In `l4 run`, a request that fails, for example because the server can't be reached, hides the results of every directive in the file, not only that one.
[Evaluate a file with `l4 run`](../../tutorials/getting-started/l4-cli.md#step-3-l4-run--evaluate-a-file) says what to do.

## FETCH

`FETCH url` sends a GET request and gives the response body as a STRING.

```l4
DECIDE uuid IS FETCH "https://www.uuidtools.com/api/generate/v4"
```

Query parameters can be written in the address: `"https://api.example.com/search?q=lease"`.

## POST

`POST url headers body` sends a POST request and gives the response body as a STRING. All three inputs are STRINGs.

- `headers` holds one header per line, each written `Name: value`. Separate the lines with `\n`: `"content-type: application/json\nauthorization: Bearer abc"`. Use `""` for no headers.
- `body` is sent as it is; build JSON with `JSONENCODE`.

```l4
DECIDE response IS
  POST
    "https://api.example.com/data"
    "content-type: application/json"
    "{\"name\": \"test\"}"
```

## ENV

`ENV name` reads an environment variable of the process that evaluates the file. It gives `JUST` the value, or `NOTHING` when the variable is not set. Use it to keep API keys out of your files.

```l4
DECIDE `the API key` IS
  CONSIDER ENV "API_KEY"
  WHEN JUST key THEN key
  WHEN NOTHING THEN ""
```

## JSONENCODE

`JSONENCODE value` gives the JSON text for any value.

| L4 value                                  | JSON                                                            |
| ----------------------------------------- | --------------------------------------------------------------- |
| NUMBER                                    | a number                                                        |
| STRING                                    | a string, with escapes                                          |
| BOOLEAN                                   | `true` or `false`                                               |
| LIST                                      | an array                                                        |
| record (`DECLARE ... HAS`)                | an object with one entry per field                              |
| constructor without fields, such as `Red` | its name as a string: `"Red"`                                   |
| constructor with fields                   | an object of its fields; the constructor's name is not included |
| `NOTHING`                                 | `null`                                                          |
| `JUST x`                                  | the JSON for `x`                                                |
| `LEFT x`, `RIGHT x`                       | an object with the side as its one key: `{"LEFT": x}`           |

```l4
DECLARE Person HAS
  name IS A STRING
  age IS A NUMBER

DECIDE alice IS Person WITH name IS "Alice", age IS 30

-- {"name":"Alice","age":30}
DECIDE `alice as JSON` IS JSONENCODE alice
```

## JSONDECODE

`JSONDECODE text` reads JSON text. It gives `RIGHT value`, or `LEFT message` when the text is not valid JSON. JSON that is valid but does not fit the expected type, such as a record with a field missing or a string where a number belongs, stops the evaluation with an error naming the problem.

The type you expect guides the decoding, so say it, with `GIVETH` or by the way the result is used:

- A JSON object decodes to a record whose field names match its keys. Keys the record does not declare are ignored.
- An array decodes to a LIST, a number to a NUMBER, a string to a STRING, `true` and `false` to a BOOLEAN.
- `null` decodes to `NOTHING` for a MAYBE type; any other value decodes to `JUST` it.
- A string with a constructor's name decodes to that constructor of an enumeration.
- A type declared as another name for a type (`DECLARE Year IS A NUMBER`) decodes as that type, and so does one for a MAYBE: with `DECLARE MaybeYear IS A MAYBE NUMBER`, `null` decodes to `NOTHING` and `2026` to `JUST 2026`.

```l4
DECLARE Person HAS
  name IS A STRING
  age IS A NUMBER

GIVETH AN EITHER STRING Person
parsed MEANS JSONDECODE "{\"name\":\"Bob\",\"age\":25}"

DECIDE person IS
  CONSIDER parsed
  WHEN RIGHT p THEN p
  WHEN LEFT problem THEN Person WITH name IS "Unknown", age IS 0
```

## Example: an authenticated request

```l4
DECLARE `payment request` HAS
  amount   IS A NUMBER
  currency IS A STRING

GIVEN `the request` IS A `payment request`
GIVETH A STRING
`send` `the request` MEANS
  CONSIDER ENV "PAYMENTS_API_KEY"
  WHEN JUST key THEN
    POST
      "https://api.example.com/payments"
      (CONCAT "content-type: application/json\nauthorization: Bearer ", key)
      (JSONENCODE `the request`)
  WHEN NOTHING THEN "PAYMENTS_API_KEY is not set"
```

## See also

- [llm](../libraries/llm.md): calls to Anthropic, OpenAI and OpenRouter built on `POST`.
- [Coercions](../types/coercions.md): `TOSTRING`, `TONUMBER` and other conversions.
