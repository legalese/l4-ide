# Tutorials

Step-by-step guides for getting a task done with L4: from installing it and writing a first rule, to testing and publishing rules, to using them from AI agents and applications. Each guide stands on its own; for the exact meaning of a keyword, follow its links into the [reference](../reference/README.md).

## Start here

- [Install L4 and write your first rule](getting-started/first-l4-file.md): set up VS Code or the web editor, write a rule and run it.
- [Draft rules with Legalese AI](llm-integration/composing-l4-with-ai.md): turn a policy or contract into checked L4 with the AI assistant in VS Code.

## Write and check rules

- [Test your rules](getting-started/testing-your-rules.md): check outcomes with `#EVAL` and `#ASSERT`, and simulate obligations with `#TRACE`.
- [Fix errors](getting-started/debugging-type-errors.md): read a diagnostic, and fix the errors that come up most.
- [Encode legislation](getting-started/encoding-legislation.md): turn a statutory provision into a tested rule, alone or with an AI assistant.
- [Make rules read like law](natural-language-functions/optimising-natural-language-generation.md): infix and mixfix names, and rules that render as readable documents.
- [Common patterns](getting-started/common-patterns.md): recipes for records, decisions, calculations, lists, dates and obligations.

## Publish rules

- [Deploy your rules](deploying-rules/exporting-rules-for-deployment.md): mark rules with `@export`, deploy them to Legalese Cloud and call them.

## Use deployed rules

- [Choose an integration](legalese-cloud/README.md): compare the ways to use a deployment; addresses, API keys and permissions.
- [Connect an AI agent](legalese-cloud/ai-agents.md): Claude, Cursor, VS Code and other MCP clients, with skills and plugins.
- [Chat with your rules](legalese-cloud/openai-compatible-api.md): ask a deployment questions from an OpenAI or Anthropic client.
- [Call rules over REST](legalese-cloud/openapi-spec.md): run rules from your own application, and generate a client from OpenAPI.
- [Embed rules in a website](legalese-cloud/webmcp-embed.md): one script tag lets visitors' browser agents use your rules.

## Advanced

- [Using the l4 CLI](getting-started/l4-cli.md): check, run, batch-evaluate, render and deploy rules from the command line.
- [Manage rules in git and CI](getting-started/version-control-for-rules.md): commits, review, automatic checks and safe redeployment.
