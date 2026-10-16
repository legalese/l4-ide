# Choose an integration

A deployed rule set can be used in four ways, all served from the same deployment and always computing the same answers. This page compares them and collects what they share: addresses, API keys and permissions, and self-hosting. To create a deployment first, see [Deploy your rules](../deploying-rules/exporting-rules-for-deployment.md).

| You want                                                                                  | Use                                         | Page                                             |
| ----------------------------------------------------------------------------------------- | ------------------------------------------- | ------------------------------------------------ |
| An AI agent (Claude, Cursor, VS Code with Copilot, …) to find and run your rules as tools | MCP, optionally with an agent skill         | [Connect an AI agent](ai-agents.md)              |
| A chat assistant that answers from your rules, called with an OpenAI or Anthropic client  | Chat API with the `legalese-comply-4` model | [Chat with your rules](openai-compatible-api.md) |
| Your own application to call rules directly, with no model involved                       | REST, described by an OpenAPI document      | [Call rules over REST](openapi-spec.md)          |
| AI agents in your visitors' browsers to use your rules on your website                    | The WebMCP embed script                     | [Embed rules in a website](webmcp-embed.md)      |

REST is deterministic: the same inputs always give the same result, which suits back-end workflows, batch jobs and audited systems. MCP, chat and WebMCP put a model in front of the rules: the model chooses the rule and gathers the inputs, and the rule computes the answer.

In VS Code, the **Integrate** dialog of a deployment (Deployments tab) shows every address below, filled in for that deployment.

---

## Addresses

`{orgSlug}` is your organization on Legalese Cloud; `{deploymentId}` is the deployment's name.

| Integration          | Legalese Cloud                                                                    | Self-hosted jl4-service                         |
| -------------------- | --------------------------------------------------------------------------------- | ----------------------------------------------- |
| MCP, all deployments | `https://mcp.legalese.cloud`                                                      | `{serviceUrl}/.mcp`                             |
| MCP, one deployment  | `https://mcp.legalese.cloud/{orgSlug}/{deploymentId}`                             | `{serviceUrl}/{deploymentId}/.mcp`              |
| Chat API             | `https://ai.legalese.cloud/{orgSlug}/{deploymentId}/v1`                           | Not available                                   |
| OpenAPI document     | `https://api.legalese.cloud/{orgSlug}/{deploymentId}/openapi.json`                | `{serviceUrl}/{deploymentId}/openapi.json`      |
| REST: list rules     | `https://api.legalese.cloud/{orgSlug}/{deploymentId}/functions`                   | `{serviceUrl}/{deploymentId}/functions`         |
| REST: run a rule     | `https://api.legalese.cloud/{orgSlug}/{deploymentId}/functions/{name}/evaluation` | `{serviceUrl}/{deploymentId}/{name}/evaluation` |
| WebMCP embed script  | `https://api.legalese.cloud/.webmcp/embed.js`                                     | `{serviceUrl}/.webmcp/embed.js`                 |

`{name}` is the rule's name with spaces turned into hyphens: `` `calculate premium` `` becomes `calculate-premium`.

---

## API keys and permissions

Every call is authenticated, either with your Legalese Cloud sign-in or with an API key. Clients that support it (MCP clients, the VS Code extension) sign you in through the browser the first time they connect. For everything else, create an API key in the [Legalese Cloud console](https://legalese.cloud) and send it as `Authorization: Bearer sk_...`; the chat API also accepts `x-api-key: sk_...`, the Anthropic SDK's default header.

A key carries permissions. Give it only the ones the integration needs:

| Permission    | Allows                                                                                             |
| ------------- | -------------------------------------------------------------------------------------------------- |
| `l4:rules`    | Seeing which rules exist: their names and descriptions. Without it, a client sees no rules at all. |
| `l4:read`     | Reading each rule's full input and output schema, the OpenAPI document, and the L4 source.         |
| `l4:evaluate` | Running a rule and getting its result.                                                             |
| `ai:chat`     | Using the chat API.                                                                                |

| Integration         | Permissions                                                                                       |
| ------------------- | ------------------------------------------------------------------------------------------------- |
| AI agent over MCP   | `l4:rules`, `l4:evaluate`; add `l4:read` for full schemas and the source-browsing tools           |
| Chat API            | `ai:chat`, `l4:rules`, `l4:evaluate`                                                              |
| REST                | `l4:evaluate` to call rules; `l4:rules` and `l4:read` to list them and fetch the OpenAPI document |
| WebMCP embed script | `l4:rules`, `l4:evaluate` only                                                                    |

With `l4:rules` and `l4:read` but not `l4:evaluate`, a key gives a read-only catalogue: the rules are visible but cannot be run. A common split for REST is a build-time key with `l4:rules` and `l4:read` for generating clients, and a separate run-time key with `l4:evaluate` for the service that calls the rules.

The WebMCP key is visible to anyone who opens your web page. Treat it like a publishable key: give it only `l4:rules` and `l4:evaluate`, limit it to the deployment you embed, and replace it if it is misused.

---

## Self-hosted jl4-service

If you run your own jl4-service (deploy to it with `l4 deploy FILE --server URL`; see [Using the l4 CLI](../getting-started/l4-cli.md)):

- Every per-deployment address also works with a `/deployments` prefix: `{serviceUrl}/deployments/{deploymentId}/.mcp` and `{serviceUrl}/deployments/{deploymentId}/openapi.json` are the same as the short forms in the table above. Under that prefix, rules sit under `functions/`: `{serviceUrl}/deployments/{deploymentId}/functions/{name}/evaluation`. These pages use the short forms.
- Authentication is whatever your jl4-service is configured with, often none for a local instance.
- The chat API, the org-wide MCP search tools (`search_rules`, `get_schema`, `evaluate`) and the agent plugin download exist on Legalese Cloud only. A self-hosted MCP server offers one tool per exported rule and the source-browsing tools.
- The self-hosted embed script ignores `data-org`: the service already knows its own deployments.
