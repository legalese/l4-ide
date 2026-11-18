# Connect an AI agent: Claude, Codex, Cursor and VS Code

Let an AI agent answer questions by running your deployed rules instead of guessing. This page covers Claude (Claude Code, Claude Desktop and claude.ai), OpenAI Codex (the CLI, the Codex app and the IDE extension), Cursor, and VS Code with GitHub Copilot, as well as the GitHub Copilot CLI, Windsurf, Cline and any other client that speaks the [Model Context Protocol](https://modelcontextprotocol.io) (MCP).

**Before you start:** a deployment on Legalese Cloud ([Deploy your rules](../deploying-rules/exporting-rules-for-deployment.md)). For permissions and self-hosted addresses, see [Choose an integration](README.md).

There are two ways to connect:

- **All your rules at once** (recommended): one MCP server for your whole organization. The agent searches for the right rule, reads its inputs and runs it, however many deployments you have. Install it with the [skills marketplace](#install-all-your-rules-skills-marketplace) to also teach the agent when to use your rules.
- **One deployment**: an MCP server whose tools are exactly that deployment's rules. Install it [as a plugin](#install-one-deployment-as-a-plugin) to include a skill for that rule set.

---

## MCP endpoint

### All deployments

```
https://mcp.legalese.cloud
```

There is no organization in the address: it comes from your sign-in. The server offers these tools:

| Tool                                                          | Does                                                                              |
| ------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| `search_rules`                                                | Finds the deployments a question needs (keywords separated by spaces, any match). |
| `get_schema`                                                  | Returns a rule's inputs and output, and the deployment's version.                 |
| `evaluate`                                                    | Runs a rule and returns its result.                                               |
| `list_files`, `read_file`, `search_identifier`, `search_text` | Browse the L4 source of a deployment.                                             |

Only deployments with an **Intended use** description can be found with `search_rules`.

### One deployment

```
https://mcp.legalese.cloud/{orgSlug}/{deploymentId}
```

This server registers **one tool per exported rule**, plus the same four source-browsing tools. Tool names and input fields are the L4 names with spaces turned into hyphens, because tool names may only contain letters, digits, `_` and `-`: `` `calculate premium` `` becomes the tool `calculate-premium`, and the field `` `risk score` `` becomes `risk-score`. The server maps them back when it runs the rule. Each tool's description is your `@export` text, and its input schema comes from the `GIVEN` inputs and their `@desc` texts.

### Telling a rule not to assume anything

Some rules give an input a default (see [TYPICALLY](../../reference/types/TYPICALLY.md)): a value the rule uses when a caller leaves that input out.
By default an agent that leaves such an input out gets an answer computed from the default, and the result lists it under `presumed` so that the agent can tell the user what was assumed.
The one exception is an event's party or action record in a request to the decision service for a rule that describes obligations (a regulative rule, whose result is a contract; see [Regulative rules](../../reference/regulative/README.md)): every field of it must be written, and a request that leaves one out is answered with an error (see [An event's party and action record](../../reference/types/TYPICALLY.md#an-events-party-and-action-record)).

An agent that must not assume anything the user did not say can send the argument `presumption` with the value `"hard"`.
Then no default is used: if the call leaves out an input that has a default, the tool refuses the call and names the input, instead of answering, whether or not the rule would have read it (checked for an ordinary rule).
The value `"soft"` is the same as leaving the argument out.
Both values are accepted in any capitalisation, as in a service request; any other value is refused.
A default that the rule itself takes inside its own text is still used under `"hard"`, because it is part of the rule, not something a caller left out.

Where the argument goes depends on the kind of rule.
A call to a tool carries one object, the tool's input, which the client sends as the `arguments` member of a `tools/call` request.
The keys of that object are the ones the tool's input schema lists.

| The rule                                                 | Where `presumption` goes in the tool's input                                              | Example input                                                                  |
| -------------------------------------------------------- | ----------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| An ordinary rule, one that does not describe obligations | With the rule's own inputs, at the top level of the tool's input                          | `{"applicant": {...}, "presumption": "hard"}`                                  |
| A rule that describes obligations                        | Beside `arguments`, `startTime` and `events`; the rule's own inputs go inside `arguments` | `{"arguments": {...}, "startTime": 0, "events": [...], "presumption": "hard"}` |

For a rule that describes obligations the word `arguments` appears twice, because the request has two layers.
Here is a whole call, with the right place for `presumption`:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "service-requirement",
    "arguments": {
      "arguments": { "state": { "status": "Active" } },
      "startTime": 0,
      "events": [
        {
          "party": { "Name": "Alice" },
          "action": "maintain eligible service",
          "at": 1
        }
      ],
      "presumption": "hard"
    }
  }
}
```

The outer `arguments`, a member of `params`, is the tool's input.
The inner `arguments` holds the rule's own inputs, and `presumption` sits beside it.
Three other places are refused, each with a message that says where the argument goes:

- **Inside the inner `arguments`**, with the rule's own inputs, on a rule that describes obligations (unless the rule has an input of that name).
- **Beside the outer `arguments`**, as a member of `params`, which is the shape of an HTTP request body.
- **Inside an `arguments` object that wraps the inputs of an ordinary rule**: its inputs and `presumption` go at the top level of the tool's input, as in the table.

Anywhere else, such as in `_meta`, the argument is not read and is ignored.

On this service, every rule's tool advertises `presumption` in its input schema, so an agent finds it without being told.
The [WebMCP embed script](webmcp-embed.md) takes it too and passes it on to the service, but the refusals of a key in the wrong place described here are the MCP endpoint's: the script does not check where the key was put.
It is the same argument, with the same two values, as `l4 batch --presumption` and the `presumption` field of a service request (see [Call rules over REST](openapi-spec.md#turn-the-defaults-off)).

What this covers, and what it does not:

- This service's MCP tools advertise `presumption` and read it, and so do the WebMCP script's tools.
  A hosted server placed in front of this service may not list it until that server is updated, so look at the tool list (`tools/list`, or `get_schema` on the all-deployments server) before relying on it.
  The hosted servers on Legalese Cloud work from their own copy of each rule's schema.
  A server that does not know the argument reads it as it reads any name that matches none of a rule's inputs: where the call leaves out an input that has a default, it refuses the call, naming `presumption`, and where the call leaves out no such input, it ignores the argument.
  Where it is not listed, the REST API's `presumption` field does the same thing.
- An ordinary rule with an input called `presumption` cannot be offered as a tool, because the argument would be taken for the input or the input for the argument.
  The server leaves that rule's tool out of its list, and a call to it is refused and names the input.
  Rename the input in the rule, or call the rule through the [REST API](openapi-spec.md), where the inputs are nested inside `arguments`.
  A rule that describes obligations is still offered, because its inputs are inside `arguments` and `presumption` is beside them.

A rule's inputs go at the top level of a call, as its tool's schema lists them; only a rule that describes obligations takes them inside `arguments`.
If a call to an ordinary rule's MCP tool wraps its inputs in an `arguments` object, the tool refuses it and says where the inputs go, instead of answering from the defaults.
The WebMCP script does not do this: it sends such a wrapper on to the service, which refuses an unknown name only when another input the call left out has a default, so an agent using the script should put the inputs at the top level of the call too.

### Tool names in WebMCP

The [WebMCP embed script](webmcp-embed.md) offers the same search, schema and run steps under different names: `search_rules`, `get_rule_schema` and `evaluate_rule`. An agent that uses both sees both sets.

### Authentication

MCP clients that support it sign you in with your Legalese Cloud account in the browser the first time they connect. Otherwise, send an API key: `Authorization: Bearer sk_...`. The key needs `l4:rules` and `l4:evaluate`, and `l4:read` for full schemas and the source tools; see [API keys and permissions](README.md#api-keys-and-permissions).

### Add the server by hand

In Claude Code:

```bash
# All deployments
claude mcp add --transport http legalese-rules https://mcp.legalese.cloud

# One deployment
claude mcp add --transport http {orgSlug}-{deploymentId} \
  https://mcp.legalese.cloud/{orgSlug}/{deploymentId}
```

Without a header, Claude Code signs you in on first use. To use an API key instead, add `--header "Authorization: Bearer sk_..."`. The single-deployment server is named after the deployment, as the plugin install below names it, so the two kinds of server can sit side by side.

In Codex (the CLI, the Codex app and the IDE extension share one configuration):

```bash
# All deployments
codex mcp add legalese-rules --url https://mcp.legalese.cloud
codex mcp login legalese-rules
```

`codex mcp login` signs you in through the browser. To use an API key instead, keep it in an environment variable and name that variable in `~/.codex/config.toml`:

```toml
[mcp_servers.legalese-rules]
url = "https://mcp.legalese.cloud"
bearer_token_env_var = "LEGALESE_TOKEN"
```

For one deployment, use the address `https://mcp.legalese.cloud/{orgSlug}/{deploymentId}` and the server name `{orgSlug}-{deploymentId}`. In the Codex app or IDE extension, you can also add the server under **Settings → MCP servers** as a Streamable HTTP server; type `/mcp` to check that it is connected.

In any other MCP client, add an HTTP server with one of the addresses above, and an `Authorization` header if you use a key. The client then lists the tools, and the model calls them with structured arguments.

Adding a server by hand gives the agent the tools, but not the skill that tells it when to use them. The installs below add both.

---

## Install all your rules (skills marketplace)

The Legalese skills marketplace, the public repository [legalese/cloud-rules](https://github.com/legalese/cloud-rules), installs two things:

- a **skill** (a `SKILL.md` in the [Agent Skills](https://agentskills.io) format) that tells the agent to answer questions about eligibility, entitlements, deadlines, compliance and similar decisions by running your rules rather than reasoning them out;
- the **all-deployments MCP server** (`https://mcp.legalese.cloud`), which the skill uses to search for and run your rules.

The public catalogue contains only this one gateway plugin. Your deployments' names, descriptions and rules are visible only after sign-in, through `search_rules`.

### From the VS Code extension

In the L4 sidebar, open the **Deployments** tab, choose **Install Skills Marketplace**, and pick your agent: Claude Code, VS Code (Copilot), GitHub Copilot CLI, Cursor, Windsurf, Cline or Claude Desktop. The extension registers the MCP server in that agent's own configuration. For Claude Code and the Copilot CLI it installs the full plugin (skill and server) through their plugin commands, and falls back to registering only the server if that command is not on your `PATH`. No token is stored; the agent signs you in on first use.

### Claude Code and claude.ai

```
/plugin marketplace add legalese/cloud-rules
/plugin install rules@legalese-cloud
```

If `install` reports "not found in any marketplace", check that `/plugin marketplace list` shows `legalese-cloud`. Instead of the GitHub repository, you can also add `https://skills.legalese.cloud/marketplace.json` or `https://skills.legalese.cloud/marketplace.git`.

### GitHub Copilot CLI and VS Code

```sh
copilot plugin marketplace add legalese/cloud-rules
copilot plugin install rules@legalese-cloud
```

In VS Code, add `legalese/cloud-rules` (or `https://skills.legalese.cloud/marketplace.git`) to the `chat.plugins.marketplaces` setting, then search for `@agentPlugins` in the Extensions view. **Chat: Install Plugin From Source** with the git address also works.

These clients read the plugin's portable `mcp.json`, which has no credential in it (the Agent Plugins format does not allow secrets), so they sign you in on first connect. Claude Code reads `.mcp.json` instead, which can take an API key from the `LEGALESE_TOKEN` environment variable.

### Which agents support what

| Agent                        | MCP server | VS Code one-click | Skill                         |
| ---------------------------- | ---------- | ----------------- | ----------------------------- |
| Claude Code                  | Yes        | Yes               | Yes: `/plugin install`        |
| Claude Desktop, claude.ai    | Yes        | Yes               | Yes                           |
| VS Code (Copilot)            | Yes        | Yes               | Yes: `@agentPlugins`          |
| GitHub Copilot CLI           | Yes        | Yes               | Yes: `copilot plugin install` |
| Cursor, Windsurf, Cline      | Yes        | Yes               | Varies                        |
| OpenAI Codex (CLI, app, IDE) | Yes        | No                | Yes                           |
| Gemini CLI                   | Yes        | No                | Yes                           |

MCP is what they all share; the skill is an addition on top. Support changes quickly, so check your agent's own documentation.

### Troubleshooting

- **The server does not connect.** The address is `https://mcp.legalese.cloud`, with no organization in it. Sign in when the agent asks, or send an `Authorization: Bearer sk_...` header.
- **`forbidden`.** The credential lacks `l4:rules`, or belongs to a different organization.
- **A rule cannot be found.** Only deployments with an **Intended use** description are searchable.
- **`marketplace add` fails.** Check that [github.com/legalese/cloud-rules](https://github.com/legalese/cloud-rules) or `https://skills.legalese.cloud/marketplace.json` opens in a browser.
- **The install asks for git credentials.** You are using an old per-deployment repository address, not the gateway plugin.

---

## Install one deployment as a plugin

For a skill that triggers on one rule set specifically, install a single deployment as a plugin. In VS Code, open the deployment's **Integrate** dialog (Deployments tab, then **Integrate**). Under **Install as AI agent skill**, choose a target:

| Target             | Skill folder                                  | MCP server registered in     | Then                              |
| ------------------ | --------------------------------------------- | ---------------------------- | --------------------------------- |
| Claude Code        | `~/.claude/skills/{orgSlug}-{deploymentId}/`  | `~/.claude.json`             | Restart Claude Code.              |
| VS Code (Copilot)  | `~/.claude/skills/{orgSlug}-{deploymentId}/`  | VS Code's user `mcp.json`    | Reload the window.                |
| GitHub Copilot CLI | `~/.copilot/skills/{orgSlug}-{deploymentId}/` | `~/.copilot/mcp-config.json` | Restart, or run `/skills reload`. |

Claude Code and VS Code share the skill folder, so installing for both does not duplicate it. The Copilot CLI paths follow `COPILOT_HOME` if you have set it. Installing again refreshes the skill in place. Because each deployment gets its own name, several deployments can be installed side by side.

The download button next to the targets saves the plugin as a zip, to install with `claude --plugin-url file:///path/to/plugin.zip`, to inspect, or to give to a colleague who is not signed in to your organization.

### What the plugin contains

- `SKILL.md`: its name and description come from the deployment's **Intended use**; its body lists every exported rule with its description.
- `references/schemas.json`: the rules' schemas, the same as the MCP server's tool list.
- `plugin.json` and `mcp.json`: the [Agent Plugins](https://agent-plugins.org/specification) manifest, read by VS Code and the Copilot CLI, with no credential in it.
- `.claude-plugin/plugin.json` and `.mcp.json`: the same for Claude Code, with `Authorization: Bearer ${LEGALESE_TOKEN}`, so one API key covers both the install and the tool calls.

The plugin is generated from the deployment's details, with no AI involved. Edit **Intended use** in the sidebar and redeploy, and the next install has the new text.

A deployment needs an **Intended use** description before it can be installed: an agent would never use a skill with no description. Without one, the install shows an error.

### Other ways to get it

- The plugin is served at `https://mcp.legalese.cloud/{orgSlug}/{deploymentId}/.plugin`, with the same sign-in or API key as the MCP server (`l4:rules`). It is not available from a self-hosted jl4-service, so the install options appear only when the extension is connected to Legalese Cloud.
- Each deployment's skill is also a git repository, `https://skills.legalese.cloud/{orgSlug}/{deploymentId}.git`, for your own `marketplace.json` or a `git clone`. It uses HTTP Basic authentication with your token as the password. Let the `legalese` command supply it:

  ```sh
  git config --global credential.https://skills.legalese.cloud.helper "legalese git-credential"
  ```

---

## Example: Claude and Cursor

This example uses the `insurance-premium` deployment from [Deploy your rules](../deploying-rules/exporting-rules-for-deployment.md), with two exported rules: `` `calculate premium` `` ("Calculate the insurance premium for an applicant") and `` `qualifies for discount` `` ("Check whether the applicant qualifies for a discount"). Its MCP address is `https://mcp.legalese.cloud/{orgSlug}/insurance-premium`.

### Connect

**claude.ai:** go to **Settings**, then **Connectors**, then **Add custom connector**, and paste the address. You sign in to Legalese Cloud the first time it is used.

**Claude Code:**

```bash
claude mcp add --transport http {orgSlug}-insurance-premium \
  https://mcp.legalese.cloud/{orgSlug}/insurance-premium
```

**Cursor:** add the server to `.cursor/mcp.json` in the project, or `~/.cursor/mcp.json` for all projects:

```json
{
  "mcpServers": {
    "{orgSlug}-insurance-premium": {
      "url": "https://mcp.legalese.cloud/{orgSlug}/insurance-premium",
      "headers": {
        "Authorization": "Bearer sk_..."
      }
    }
  }
}
```

To check the connection by hand:

```bash
curl -X POST https://mcp.legalese.cloud/{orgSlug}/insurance-premium \
  -H "Authorization: Bearer sk_..." \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

Each rule appears as a tool, with your `@export` description and a schema built from its inputs and `@desc` texts:

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
          "existing-customer": { "type": "boolean" }
        }
      }
    },
    "required": ["applicant"]
  },
  "_meta": { "version": "1.0.3" }
}
```

These descriptions are all the model knows when it decides whether and how to call a rule, which is why the `@export` and `@desc` texts matter.

### A conversation

> **User:** Dana is 35, her risk score is 0.4, and she's an existing customer. What premium should we quote her, and does she get the discount?

The assistant finds two tools whose descriptions match the question and calls them instead of estimating:

```json
{
  "method": "tools/call",
  "params": {
    "name": "calculate-premium",
    "arguments": {
      "applicant": {
        "age": 35,
        "risk-score": 0.4,
        "existing-customer": true
      }
    }
  }
}
```

```json
{
  "content": [
    {
      "type": "text",
      "text": "{\"contents\":{\"presumed\":[],\"result\":{\"value\":1400}},\"report\":\"default\",\"tag\":\"SimpleResponse\"}"
    }
  ]
}
```

It calls `qualifies-for-discount` with the same applicant and gets `true`, then answers:

> **Assistant:** Per the deployed `insurance-premium` rules, Dana's premium is **1400** (her risk score of 0.4 is under the 0.7 high-risk threshold, and as an existing customer she gets the lower rate), and she **qualifies for the discount** (an existing customer with a risk score of at most 0.5).

The numbers come from the same type-checked L4 that serves the REST API: the model contributes the conversation, not the arithmetic.

### Citing the source

For a "why?" question, the source tools let the assistant quote the rule itself:

> **User:** Why 1400 exactly?

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

The assistant reads the `calculate premium` rule (an existing customer below the high-risk threshold pays age × 40) and answers 35 × 40 = 1400, grounded in the deployed source.

### When you redeploy

Tools and their schemas update automatically, and each tool reports the deployment version in `_meta`. Compatible changes, such as a new rule, simply appear in the tool list. Breaking changes are caught at deploy time; see [Manage rules in git and CI](../getting-started/version-control-for-rules.md#redeploy-when-a-merge-changes-a-live-api).

---

## The `legalese` command (shell and CI)

Where there is no MCP client, such as a shell script or a CI job, the `legalese` command reaches the same rules. Install it with `l4 install legalese` (macOS and Linux), or with:

```sh
curl -fsSL https://legalese.cloud/cli/install.sh | sh
```

Then:

```sh
legalese login                                   # sign in through the browser and choose your organization
legalese search "rent overdue"                   # find a rule
legalese schema <deployment> <function>          # see its inputs
legalese eval <deployment> <function> '<json>'   # run it
```

`legalese login --device` signs in with a code instead, for machines without a browser. In CI, skip the login and set an API key and organization: `LEGALESE_TOKEN=sk_...` and `LEGALESE_ORG={orgSlug}`. The same sign-in is what `l4 deploy` uses.
