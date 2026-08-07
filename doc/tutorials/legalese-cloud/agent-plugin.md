# Install a deployment as an AI agent plugin

Bundle a deployment's rules into a Claude Code / VS Code (Copilot) plugin so an agent can both **read the rules' "Intended use"** (a SKILL.md the model matches by description) and **call the rules as MCP tools**.

**Prerequisites:** A deployment with a non-empty **Intended use** description ([Exporting Rules for Deployment](../deploying-rules/exporting-rules-for-deployment.md))

---

## When to Use This

A bare [MCP server](./mcp-server.md) entry registers the tools but leaves the agent guessing about _when_ to reach for them. A plugin install adds the deployment's `SKILL.md` — the operator-supplied "Intended use" text — so the agent knows the domain of the rules and triggers the right tool on the right user question.

Prefer the plugin install over the raw MCP entry whenever you want the agent to invoke rules proactively (rather than only when the user explicitly asks).

## What gets installed

A single plugin bundle that contains:

- `SKILL.md` — frontmatter `name` + `description` come from the deployment's **Intended use**; body lists every exported decision with its `@desc`.
- `references/schemas.json` — the deployment's function schemas (the same JSON the agent gets from MCP `tools/list`), bundled so it can be inspected offline.
- `plugin.json` + `mcp.json` — the [Agent Plugins 1.0](https://agent-plugins.org/specification) manifest pair, read by VS Code (Copilot) and the GitHub Copilot CLI. The MCP entry carries no credential: the spec forbids secrets in headers, so these clients run the endpoint's OAuth flow on first connect.
- `.claude-plugin/plugin.json` + `.mcp.json` — the same two things in Claude Code's native layout. Its `.mcp.json` pins `Authorization: Bearer ${LEGALESE_TOKEN}`, so one API key covers both the install and the tool calls.

Both manifest pairs ship in every bundle. Each client reads its own and ignores the other, so a single plugin installs unmodified across all three.

Everything is templated deterministically from the deployment's metadata — there is no LLM step. Editing the **Intended use** field in the sidebar and redeploying regenerates the SKILL.md the next time you install.

## Install

In the L4 VS Code extension, open the deployment's **Integrate** dialog (Deployments tab → **Integrate**). Its **Install as AI agent skill** section has an **Install as Skill** dropdown to pick a target harness, plus a download button for the raw zip:

### Add to Claude Code

Writes the skill to `~/.claude/skills/{orgSlug}-{deploymentId}/` and registers the MCP server in `~/.claude.json` under the same name. Restart Claude Code to pick it up.

### Add to VS Code (Copilot)

Writes the skill to `~/.claude/skills/{orgSlug}-{deploymentId}/` (VS Code reads this path natively per the [Agent Skills spec](https://code.visualstudio.com/docs/copilot/customization/agent-skills)) and adds an entry to VS Code's user-level `mcp.json`. Reload the window to pick it up.

### Add to GitHub Copilot CLI

Writes the skill to `~/.copilot/skills/{orgSlug}-{deploymentId}/` and the MCP server to `~/.copilot/mcp-config.json`. Both honour `COPILOT_HOME` if you have set it. Restart Copilot CLI, or run `/skills reload` in an interactive session, to pick it up.

### Download plugin zip (⤓)

Saves the raw plugin zip to disk. Useful for:

- `claude --plugin-url file:///path/to/plugin.zip` — installs into Claude Code from the CLI
- Sharing with a teammate who isn't signed in to the org
- Inspecting the generated content before installing

## Endpoint

The same bundle is also served directly from the MCP host:

```
GET https://mcp.legalese.cloud/{orgSlug}/{deploymentId}/.plugin
```

It is authenticated with the same session or API key as the MCP endpoint itself. (The sibling `.skill` route on the same host is a different surface — the skills-CLI / [agentskills.io](https://agentskills.io) discovery format, not the plugin zip; see [the Skills Marketplace](./agent-marketplace.md).)

This endpoint is hosted on Legalese Cloud only — a self-hosted `jl4-service` does not serve `.plugin`, which is why the install section only appears when the extension is connected to Legalese Cloud.

## Authentication

Authenticate with your Legalese Cloud session or an API key (`Authorization: Bearer sk_...`) with the `l4:rules` permission.

## Notes

- A deployment **must have an "Intended use" description** before it can be installed as a plugin. Without one the endpoint returns `422` and the install flow surfaces a clear error — a plugin with no description is one the agent will never trigger.
- The skill folder is shared across Claude Code and VS Code (both read `~/.claude/skills/`), so installing for one target after the other doesn't duplicate files; only the MCP server registration changes. Copilot CLI reads its own root (`~/.copilot/skills/`) and therefore gets its own copy.
- Re-installing refreshes the skill in place — no need to uninstall first.
- Per-deployment names (`{orgSlug}-{deploymentId}`) mean multiple deployments of the same org coexist as separate skills + MCP servers, each scoped to its own ruleset.
