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
- [What a Section Needs to Know](section-given/what-a-section-needs-to-know.md): name the facts a whole run of rules needs once, under the heading, instead of repeating them in every rule.
- [Grouping and Precedence: What Binds to What](getting-started/grouping-and-precedence.md): why L4 groups by indentation, and three cases where a comma was the whole dispute.
- [Sets, and the Two Meanings of "And"](set-operators/sets-and-the-two-ands.md): why a drafter's "and" is sometimes a union of people and sometimes both conditions at once, and how L4 keeps them apart.
- [When a Rule Cannot Answer](refuse/when-a-rule-cannot-answer.md): say `REFUSE` where your model stops, and tell a refusal apart from the other kinds of "no answer". An uncommon construct: you can encode a dozen Acts and contracts without it.

## Model obligations and time

Who must do what, by when, and what follows: one tenancy, carried through four pages. Start from [Install L4 and write your first rule](getting-started/first-l4-file.md); [The Regulative Layer, Whole](../concepts/legal-modeling/regulative-layer-whole.md) shows how the pieces fit together.

- [One Obligation](obligations/one-obligation.md): who, what, by when, then what: write one obligation, play it forward, and read the three things the screen can say.
- [What Follows](obligations/what-follows.md): a receipt follows a payment, a late fee follows a missed one, a guarantor pays when the tenant does not: `HENCE`, `LEST`, and the two kinds of guarantee.
- [Several Parties](obligations/several-parties.md): three flatmates and one rent: all of these, any of these, one pays and the other repays, and paying in instalments, with the two honest defects of the last.
- [What Is Coming](obligations/what-is-coming.md): the pieces that are designed but not built: everyone-then-one-thing, each-with-its-own, and "enough of them".
- [Multi-Temporal Rule Modeling](multi-temporal-modeling/multi-temporal-rule-modeling.md): system time, valid time and rule-effective time, the three axes L4 tracks, and how amendments and effective dates fall out of them.

## Publish rules

- [Deploy your rules](deploying-rules/exporting-rules-for-deployment.md): mark rules with `@export`, deploy them to Legalese Cloud and call them.
- [Exporting L4 to Blawx (and Importing Back)](blawx/l4-to-blawx.md): compile L4 decisions into a Blawx project with `l4 export blawx`, run them under s(CASP) with English justification trees, and lift Blawx projects back into L4.

## Use deployed rules

- [Choose an integration](legalese-cloud/README.md): compare the ways to use a deployment; addresses, API keys and permissions.
- [Connect an AI agent](legalese-cloud/ai-agents.md): Claude, Codex, Cursor, VS Code and other MCP clients, with skills and plugins.
- [Chat with your rules](legalese-cloud/openai-compatible-api.md): ask a deployment questions from an OpenAI or Anthropic client.
- [Call rules over REST](legalese-cloud/openapi-spec.md): run rules from your own application, and generate a client from OpenAPI.
- [Embed rules in a website](legalese-cloud/webmcp-embed.md): one script tag lets visitors' browser agents use your rules.

## Advanced

- [Using the l4 CLI](getting-started/l4-cli.md): check, run, batch-evaluate, render and deploy rules from the command line.
- [Manage rules in git and CI](getting-started/version-control-for-rules.md): commits, review, automatic checks and safe redeployment.
