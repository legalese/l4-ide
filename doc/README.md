![L4 Logo](./l4.svg)

# L4 Language Documentation

L4 is a domain-specific language for law that enables computer-readable formalizations of contracts, legislation, and regulations.

---

## Getting Started

New to L4? Start here:

1. **[Get L4](https://marketplace.visualstudio.com/items?itemName=Legalese.l4-vscode)** - Download the L4 VS Code extension with Legalese AI and MCP tools
2. **[Your First L4 File](tutorials/getting-started/first-l4-file.md)** - Hands-on in 15 minutes
3. **[Composing L4 with AI](tutorials/llm-integration/composing-l4-with-ai.md)** - Draft L4 from prose using Legalese AI
4. **[Exporting Rules for Deployment](tutorials/deploying-rules/exporting-rules-for-deployment.md)** - Deploy L4 rules as REST APIs and use with MCP

---

## Documentation Types

Our documentation is organized by **what you need**:

| Type                                 | Purpose                | When to Use                 |
| ------------------------------------ | ---------------------- | --------------------------- |
| **[Courses](courses/README.md)**     | Learning-oriented      | "Teach me L4"               |
| **[Tutorials](tutorials/README.md)** | Task-oriented          | "How do I do X?"            |
| **[Reference](reference/README.md)** | Information-oriented   | "What is X?"                |
| **[Concepts](concepts/README.md)**   | Understanding-oriented | "Why does X work this way?" |

---

## Courses

Structured learning paths from beginner to advanced:

### [Foundation Course](courses/foundation/README.md)

Learn L4 from scratch. No prior programming experience required.

- Module 0: Introduction - What is L4?
- Module 1: Your First Legal Rule
- Module 2: Legal Entities and Relationships
- Module 3: Control Flow
- Module 4: Decision Logic
- Module 5: Functions
- Module 6: Regulative Rules (Obligations & Permissions)
- Module 7: Capstone Project

### [Advanced Course](courses/advanced/README.md)

Deep dives for production use.

- Module A1: Real Regulatory Schemes
- Module A2: Cross-Cutting Concerns
- Module A3: Complex Contracts
- Module A4: Production Patterns

**Prerequisites:** Foundation Course

---

## Tutorials

Task-focused guides for specific goals:

### Getting Started

- [Your First L4 File](tutorials/getting-started/first-l4-file.md) - Create, run, test
- [Using the l4 CLI](tutorials/getting-started/l4-cli.md) - Install and drive the command-line tools
- [Testing Your Rules](tutorials/getting-started/testing-your-rules.md) - #EVAL, #CHECK, #ASSERT, and #TRACE
- [Debugging Type Errors](tutorials/getting-started/debugging-type-errors.md) - Read and fix common compiler errors
- [Encoding Legislation](tutorials/getting-started/encoding-legislation.md) - Turn legal text into L4
- [Wedding Vows Example](tutorials/getting-started/wedding-vows.md) - Fun intro to regulative rules
- [Version Control for Rules](tutorials/getting-started/version-control-for-rules.md) - Git workflow for legal rules

### Deployment and Legalese Cloud

- [Exporting Rules for Deployment](tutorials/deploying-rules/exporting-rules-for-deployment.md) - Deploy L4 rules as REST APIs and use with MCP
- [Using Rules from Claude](tutorials/legalese-cloud/using-rules-from-claude.md) - End-to-end: deployed rules called from Claude and Cursor via MCP
- [OpenAI- and Anthropic-Compatible AI APIs](tutorials/legalese-cloud/openai-compatible-api.md) - Chat with a deployment's rules from any OpenAI or Anthropic client
- [MCP Server](tutorials/legalese-cloud/mcp-server.md) - Expose deployed rules as Model Context Protocol tools
- [WebMCP Embed Script](tutorials/legalese-cloud/webmcp-embed.md) - Serve your rules from your own website
- [RESTful OpenAPI Specification](tutorials/legalese-cloud/openapi-spec.md) - Generate REST clients from the spec

### LLM Integration

- [Getting Started with LLM](tutorials/llm-integration/llm-getting-started.md) - Hybrid AI + formal reasoning
- [Legislative Ingestion](tutorials/llm-integration/legislative-ingestion.md) - LLM-assisted encoding

[View all tutorials →](tutorials/README.md)

---

## Reference

Look up specific features:

- **[Syntax Reference](reference/syntax/README.md)** - Complete syntax guide
- **[Types](reference/types/README.md)** - L4 Types
- **[Functions](reference/functions/README.md)** - Functions as rules
- **[Control Flow](reference/control-flow/README.md)** - IF and CONSIDER
- **[Regulative](reference/regulative/README.md)** - Regulative language
- **[Built-ins](reference/builtins/README.md)** - Built-in functions
- **[Libraries](reference/libraries/README.md)** - Standard library
- **[Operators](reference/operators/README.md)** - Operators and precedence
- **[Patterns](reference/patterns/README.md)** - Common and advanced encoding patterns
- **[Errors](reference/errors/README.md)** - Troubleshooting compiler diagnostics
- **[Cheat Sheet](reference/cheat-sheet.md)** - One-page syntax summary

[View full reference →](reference/README.md)

---

## Concepts

Understand the "why" behind L4:

- **[Design Principles](concepts/language-design/principles.md)** - Why L4 works this way
- **[Linguistic Syntax](concepts/language-design/linguistic-syntax.md)** - How L4 reads like legal English
- **[Regulative Rules](concepts/legal-modeling/regulative-rules.md)** - Obligations, permissions, prohibitions
- **[Constitutive vs Regulative Rules](concepts/legal-modeling/constitutive-vs-regulative.md)** - Defining vs directing
- **[Default Reasoning](concepts/legal-modeling/default-reasoning.md)** - Exceptions and defeasibility with UNLESS
- **[Algebraic Types](concepts/type-system/algebraic-types.md)** - L4's type system
- **[Exhaustiveness](concepts/type-system/exhaustiveness.md)** - Totality as a legal-safety property

[View all concepts →](concepts/README.md)

---

## Community & Support

- **[Discord](https://discord.gg/Q7a7NSEdNy)** - Chat with the community
- **[GitHub Issues](https://github.com/legalese/l4-ide/issues)** - Report bugs, request features
- **[Legalese Services](https://legalese.com)** - Professional implementation services

---

## Developer Resources

- **[Latest Stable Build](https://github.com/legalese/l4-ide/releases)** - [![L4-IDE](https://img.shields.io/github/v/release/legalese/l4-ide?color=brightgreen&logo=github&label=L4-IDE)](https://github.com/legalese/l4-ide/releases/latest)
- **[L4 IDE Repository](https://github.com/legalese/l4-ide)** - Open-Source code

---

L4 is published under the [Apache-2.0 License](https://github.com/legalese/l4-ide/blob/main/LICENSE).
