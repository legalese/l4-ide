# Embed rules in a website

Add one `<script>` tag to your website so that your visitors' browser AI assistants can run your deployed rules, through [WebMCP](https://webmachinelearning.github.io/webmcp/). An eligibility checker or a clause evaluator on your page becomes a set of tools the visitor's agent can call, with no back end of your own.

**Before you start:** a deployment ([Deploy your rules](../deploying-rules/exporting-rules-for-deployment.md)), and access to your site's HTML. For permissions and self-hosted addresses, see [Choose an integration](README.md).

---

## The script

```html
<script
  src="https://api.legalese.cloud/.webmcp/embed.js"
  data-org="{orgSlug}"
  data-scope="insurance-premium"
  data-tools="auto"
  data-api-key="sk_..."
></script>
```

The **Integrate** dialog of a deployment in VS Code shows this tag filled in for that deployment.

| Attribute      | Meaning                                                                                         |
| -------------- | ----------------------------------------------------------------------------------------------- |
| `src`          | The script, served by Legalese Cloud or by your own jl4-service.                                |
| `data-org`     | Your organization on Legalese Cloud.                                                            |
| `data-scope`   | The deployments to offer: `*` for all, a deployment name, or several names separated by commas. |
| `data-tools`   | Which kinds of tools to register (see below). Default: `auto`.                                  |
| `data-api-key` | A Legalese Cloud API key that may run the rules.                                                |

## Which tools are registered

`data-tools` chooses kinds of tools, not individual rules:

| Value        | Registers                                                                                |
| ------------ | ---------------------------------------------------------------------------------------- |
| `rules`      | One tool per exported rule, which runs that rule directly.                               |
| `rule-tools` | Three search tools: `search_rules`, `get_rule_schema` and `evaluate_rule`.               |
| `file-tools` | `list_files`, `read_file`, `search_identifier` and `search_text`, to read the L4 source. |
| `auto`       | `rules` when the scope has at most 10 exported rules, otherwise `rule-tools`.            |
| `all`        | All of the above.                                                                        |

Values can be combined: `data-tools="rules,file-tools"`. With `auto`, the tools follow your redeploys without any change to the page. The search tools do the same job as the all-deployments MCP server's `search_rules`, `get_schema` and `evaluate`, under different names; see [Connect an AI agent](ai-agents.md#tool-names-in-webmcp).

## The API key

1. Open the [Legalese Cloud console](https://legalese.cloud).
2. Create an API key with only the `l4:rules` and `l4:evaluate` permissions, limited to the deployment you are embedding.
3. Put your organization in `data-org` and the key in `data-api-key`.

The key is part of your page's HTML, so anyone can read it. Treat it as a publishable key, not a secret: leave out `l4:read`, which the browser does not need, and replace the key if it is misused. See [API keys and permissions](README.md#api-keys-and-permissions).

## Check it

Open a page with the script in a browser with a WebMCP-aware assistant. Your rules appear among its tools; calling one runs the deployed rule and returns its result.
