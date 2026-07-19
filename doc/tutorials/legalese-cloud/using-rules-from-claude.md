# Using Rules from Claude

Connect a deployed rule set to Claude or Cursor over MCP, and watch an AI assistant answer questions by _running your rules_ instead of guessing.

**Prerequisites:** A deployment ([Exporting Rules for Deployment](../deploying-rules/exporting-rules-for-deployment.md)), a [Legalese Cloud](https://legalese.cloud) account

---

## What You'll Do

Start from the insurance premium calculator deployed in [Exporting Rules for Deployment](../deploying-rules/exporting-rules-for-deployment.md) — a deployment named `insurance-premium` with two exported rules:

- `` `calculate premium` `` — _Calculate the insurance premium for an applicant_
- `` `qualifies for discount` `` — _Check whether the applicant qualifies for a discount_

You will connect its MCP endpoint to Claude (claude.ai, Claude Code) and Cursor, then run a real conversation where the assistant discovers the tools, evaluates the rules, and answers from their typed results.

---

## Step 1: Know Your Endpoint

Every Legalese Cloud deployment serves MCP at:

```
https://mcp.legalese.cloud/{orgSlug}/{deploymentId}
```

For this tutorial: `https://mcp.legalese.cloud/{orgSlug}/insurance-premium`.

**Authentication** works as described in [MCP Server](./mcp-server.md): sign in with your Legalese Cloud session via OAuth, or use an API key (`Authorization: Bearer sk_...`) created in the console. The key needs `l4:rules` (list tools), `l4:read` (schemas and source browsing), and `l4:evaluate` (run rules).

### What the server exposes

The deployment's MCP server registers **one tool per exported rule**, plus a set of source-browsing tools:

| Tool                     | Kind   | Purpose                                                 |
| ------------------------ | ------ | ------------------------------------------------------- |
| `calculate-premium`      | rule   | Evaluate `` `calculate premium` `` with typed arguments |
| `qualifies-for-discount` | rule   | Evaluate `` `qualifies for discount` ``                 |
| `list_files`             | source | List the deployment's `.l4` files and their exports     |
| `read_file`              | source | Read `.l4` source content, optionally a line range      |
| `search_identifier`      | source | Find definitions and references of an L4 identifier     |
| `search_text`            | source | Case-insensitive text search across the `.l4` sources   |

Two naming rules to notice, both applied automatically:

- **Tool names are sanitized**: backtick names with spaces become hyphenated (`` `calculate premium` `` → `calculate-premium`), matching the `^[a-zA-Z0-9_-]+$` character set tool names require.
- **Field names in schemas are sanitized the same way**: the `Applicant` record's `risk score` field appears as `risk-score` in the tool's input schema, `is existing customer` as `is-existing-customer`. The server maps them back to the original L4 names when it evaluates.

---

## Step 2: Connect a Client

### claude.ai (custom connector)

In claude.ai, go to **Settings → Connectors → Add custom connector** and paste the endpoint URL:

```
https://mcp.legalese.cloud/{orgSlug}/insurance-premium
```

Authentication runs through your Legalese Cloud sign-in (OAuth) on first use.

### Claude Code

```bash
claude mcp add --transport http legalese-rules \
  https://mcp.legalese.cloud/{orgSlug}/insurance-premium \
  --header "Authorization: Bearer sk_..."
```

Omit the `--header` to use the OAuth flow instead.

### Cursor

Add the server to `.cursor/mcp.json` (project) or `~/.cursor/mcp.json` (global):

```json
{
  "mcpServers": {
    "legalese-rules": {
      "url": "https://mcp.legalese.cloud/{orgSlug}/insurance-premium",
      "headers": {
        "Authorization": "Bearer sk_..."
      }
    }
  }
}
```

### Verify the connection

Ask the client to list its tools, or check by hand:

```bash
curl -X POST https://mcp.legalese.cloud/{orgSlug}/insurance-premium \
  -H "Authorization: Bearer sk_..." \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

The response lists each rule as a tool, with your `@export` description and a JSON Schema derived from its `GIVEN` parameters and `@desc` annotations:

```json
{
  "name": "calculate-premium",
  "description": "L4 Rule: Calculate the insurance premium for an applicant [insurance-premium/calculate premium]",
  "inputSchema": {
    "type": "object",
    "properties": {
      "applicant": {
        "type": "object",
        "description": "The applicant's details",
        "properties": {
          "age": { "type": "number" },
          "risk-score": { "type": "number" },
          "is-existing-customer": { "type": "boolean" }
        }
      }
    },
    "required": ["applicant"]
  },
  "_meta": { "version": "1.0.3" }
}
```

This is why the `@export` and `@desc` texts matter so much: they are the _only_ context the model has when deciding whether and how to call your rule.

---

## Step 3: A Real Conversation

With the connector active, ask Claude a question the rules can answer:

> **User:** Dana is 35, her risk score is 0.4, and she's an existing customer. What premium should we quote her, and does she get the discount?

The assistant sees two rule tools whose descriptions match the question, and calls them rather than estimating:

**Tool call 1:**

```json
{
  "method": "tools/call",
  "params": {
    "name": "calculate-premium",
    "arguments": {
      "applicant": {
        "age": 35,
        "risk-score": 0.4,
        "is-existing-customer": true
      }
    }
  }
}
```

**Result:**

```json
{
  "content": [
    {
      "type": "text",
      "text": "{\"contents\":{\"result\":{\"value\":1400}},\"tag\":\"SimpleResponse\"}"
    }
  ]
}
```

**Tool call 2:** `qualifies-for-discount` with the same applicant →

```json
{
  "content": [
    {
      "type": "text",
      "text": "{\"contents\":{\"result\":{\"value\":true}},\"tag\":\"SimpleResponse\"}"
    }
  ]
}
```

> **Assistant:** Per the deployed `insurance-premium` rules: Dana's premium is **1400** (risk score 0.4 is under the 0.7 high-risk threshold, and as an existing customer she gets the lower rate), and she **qualifies for the discount** (existing customer with risk score ≤ 0.5).

The numbers come from the same typechecked L4 that serves your REST API — the model contributes the conversation, not the arithmetic.

### Letting the model cite the source

The source-browsing tools close the loop for "why?" follow-ups:

> **User:** Why 1400 exactly?

The assistant can call `list_files` and then `read_file`:

```json
{
  "method": "tools/call",
  "params": {
    "name": "read_file",
    "arguments": {
      "deployment": "insurance-premium",
      "path": "insurance-premium.l4",
      "lines": "12:20"
    }
  }
}
```

…and quote the actual rule text back — ``IF applicant's `risk score` > 0.7 THEN applicant's `age` * 100, ELSE IF applicant's `is existing customer` THEN applicant's `age` * 40, ...`` — so 35 × 40 = 1400. The answer is grounded in the deployed source, not a paraphrase from training data.

---

## Step 4: When You Redeploy

Tools and their input schemas update automatically on redeploy — each tool also advertises the deployment version in its `_meta`. Compatible changes (a new rule, a new optional field) simply appear in the client's tool list. Breaking interface changes are detected and blocked at deploy time; see [Version Control for Rules](../getting-started/version-control-for-rules.md#redeployment-when-a-merge-changes-a-live-api).

---

## Going Further

- **All your deployments at once:** the org-wide rules MCP at `https://mcp.legalese.cloud` (no path — the org is resolved from your sign-in) exposes `search_rules`, `get_schema`, and `evaluate` discovery tools that span every deployment, so agents can find the right rule before calling it. See [Agent Marketplace](./agent-marketplace.md).
- **Pre-packaged for Claude Code:** every deployment also serves a ready-made agent plugin — see [Agent Plugin](./agent-plugin.md).
- **Deterministic integrations:** for server-to-server calls without a model in the loop, prefer the [REST API and OpenAPI spec](./openapi-spec.md) at `https://api.legalese.cloud/{orgSlug}/{deploymentId}`, or the [OpenAI/Anthropic-compatible AI API](./openai-compatible-api.md) at `https://ai.legalese.cloud/{orgSlug}/{deploymentId}`.

---

> **Self-hosted note:** a self-hosted `jl4-service` serves the same MCP surface from your own host at `http://{serviceUrl}/{deploymentId}/.mcp` (no separate `mcp.` hostname), with whatever auth your instance is configured to use.
