# L4 Tutorials

Task-oriented guides to help you accomplish specific goals with L4. Each tutorial is self-contained and focused on a particular use case or audience.

## Getting Started

New to L4? Start here:

- **[Your First L4 File](getting-started/first-l4-file.md)** - Create and run a simple L4 program
- **[Using the l4 CLI](getting-started/l4-cli.md)** - Install and use the `l4` command-line tool
- **[Testing Your Rules](getting-started/testing-your-rules.md)** - Write tests for your L4 rules
- **[Debugging Type Errors](getting-started/debugging-type-errors.md)** - Understand and fix the type checker's error messages
- **[Version Control for Rules](getting-started/version-control-for-rules.md)** - Manage L4 files with git
- **[Encoding Legislation](getting-started/encoding-legislation.md)** - Turn legal text into L4
- **[Wedding Vows](getting-started/wedding-vows.md)** - Fun intro to regulative rules

See also: [Common Patterns](../reference/patterns/common-patterns.md) - a quick reference of frequently used L4 patterns.

## Natural Language Functions

Write functions that read like legal prose:

- **[Infix, Postfix, and Mixfix Functions](natural-language-functions/natural-language-functions.md)** - Call functions in natural word order
- **[Optimising for Natural Language Document Generation with `@nlg`](natural-language-functions/optimising-natural-language-generation.md)** - Make the rendered prose read as naturally as possible, then refine it with Legalese AI

**Prerequisites:** Basic function syntax

## Multi-Temporal Modeling

Model rules that change over time:

- **[Multi-Temporal Rule Modeling](multi-temporal-modeling/multi-temporal-rule-modeling.md)** - System time, valid time, and rule-effective time: the three axes L4 tracks, and how amendments/effective dates fall out of them

**Prerequisites:** Basic L4 knowledge, familiarity with dates

## Deployment and Legalese Cloud

Export your L4 rules as live REST API endpoints:

- **[Exporting Rules for Deployment](deploying-rules/exporting-rules-for-deployment.md)** - Mark rules with `@export`, deploy from VS Code, and call them via REST or WebMCP
- **[OpenAI- and Anthropic-Compatible AI APIs](legalese-cloud/openai-compatible-api.md)** - Chat with a deployment's rules from any OpenAI or Anthropic client (`legalese-comply-4`)
- **[MCP Server](legalese-cloud/mcp-server.md)** - Expose deployed rules as Model Context Protocol tools
- **[Using Your Rules from Claude](legalese-cloud/using-rules-from-claude.md)** - Connect Claude to your deployed rules
- **[Install a Deployment as an AI Agent Plugin](legalese-cloud/agent-plugin.md)** - Bundle a deployment's SKILL.md + MCP server into an agent plugin
- **[Use Deployed Rules from an AI Agent (MCP)](legalese-cloud/agent-marketplace.md)** - Connect an agent to the org's rules MCP server; it finds and calls the right rule (scales to many deployments)
- **[WebMCP Embed Script](legalese-cloud/webmcp-embed.md)** - One embed tag so your website serves its own rules
- **[RESTful OpenAPI Specification](legalese-cloud/openapi-spec.md)** - Generate clients and call rules as plain REST

**Prerequisites:** Basic L4 knowledge

## LLM Integration

Working with AI and language models in L4:

- **[Composing L4 with AI](llm-integration/composing-l4-with-ai.md)** - Draft L4 from prose using Legalese AI
- **[LLM Getting Started](llm-integration/llm-getting-started.md)** - Basics of LLM integration
- **[Legislative Ingestion](llm-integration/legislative-ingestion.md)** - LLM-assisted encoding

**Prerequisites:** Basic L4 knowledge
