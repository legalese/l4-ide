# Module 0: Introduction to L4

This module introduces the language and gets you set up.

## Learning Objectives

By the end of this module, you will be able to:

- Explain what L4 is and what it is designed for
- Recognize the main building blocks of an L4 file
- Set up an L4 environment (VS Code, web editor, or command line)
- Create and run your first L4 file

---

## What is L4?

**L4 is a programming language designed specifically for law.** It lets you translate legal documents into precise, executable code that computers can understand, verify, and run.

### Why L4?

Traditional legal documents have problems:

| Problem           | Example                          | L4 Solution                     |
| ----------------- | -------------------------------- | ------------------------------- |
| **Ambiguity**     | "reasonable time"                | Explicit deadlines: `WITHIN 30` |
| **Inconsistency** | Same term defined differently    | Single source of truth          |
| **Complexity**    | Nested conditions hard to follow | Visual logic diagrams           |
| **Testing**       | Can't simulate scenarios         | `#TRACE` runs simulations       |
| **Maintenance**   | Changes ripple unpredictably     | Type system catches errors      |

### What L4 Is For

L4 excels at:

- **Regulatory compliance** - Encode legislation as executable rules
- **Contract automation** - Model obligations, deadlines, and consequences
- **Decision support** - Build systems that explain their reasoning
- **Legal analysis** - Find edge cases and contradictions

### What L4 Is Not

L4 is not:

- A replacement for lawyers (it's a tool for lawyers)
- Natural language processing (you write structured code)
- A document generator (though it can feed into one)

---

## How L4 Works

L4 code looks like a hybrid of legal text and programming. Here's a complete example of a charity's legal obligation:

**Example:** [charity-obligation.l4](charity-obligation.l4)

This may be a lot right now, but notice how it reads almost like English, but with precise meaning:

- **DECLARE** - Defines what things look like (types)
- **GIVEN** - Declares what entities are involved
- **IF** - States conditions that must be true
- **PARTY** - Identifies who has the obligation
- **MUST** - Creates a legal obligation
- **WITHIN** - Sets a deadline (in days)
- **HENCE** - What happens on compliance
- **LEST** - What happens on non-compliance
- **#TRACE** - Simulates how the contract plays out

---

## Key Concepts

### 1. Types Define Structure

L4 uses types to define what things look like:

**Example:** [type-declaration.l4](type-declaration.l4)

This prevents errors—you can't accidentally use a person where you need a charity.

### 2. Rules Define Logic

Rules capture legal reasoning using natural language:

**Example:** [eligibility-rule.l4](eligibility-rule.l4)

Notice how the rule reads like English: "the applicant is eligible if the applicant is at least 18 years old and the applicant has shown valid identification."

### 3. Contracts Define Obligations

Regulative rules capture who must do what, with deadlines and consequences:

**Example:** [sale-contract.l4](sale-contract.l4)

This models a simple sale: the seller must deliver within 14 days, then the buyer must pay within 30 days.

---

## Setting Up Your Environment

You can write L4 in three places:

- **VS Code** (recommended): install the [L4 extension](https://marketplace.visualstudio.com/items?itemName=Legalese.l4-vscode) and create a file ending in `.l4`. You get syntax highlighting, errors as you type, hover documentation and visualisations.
- **The web editor**: [play.legalese.com](https://play.legalese.com/) runs L4 in your browser, with nothing to install.
- **The command line**: `l4 run myfile.l4` checks a file and prints its results.

[Install L4 and write your first rule](../../tutorials/getting-started/first-l4-file.md) walks through each option step by step.

---

## Your First L4 File

Create a file called `hello.l4`:

[Example file hello.l4](hello.l4)

Save the file. If you're using VS Code with the L4 extension, you'll see:

- Syntax highlighting
- The `#EVAL` result shown inline

---

## L4 Design Philosophy

L4 is built so that code mirrors the structure of the legal text it encodes, can be read by lawyers, and has one precise, checkable meaning. [Design principles](../../concepts/language-design/principles.md) explains these choices and the trade-offs between them.

Next, [Module 1: Your first legal rule](module-1-first-rule.md) writes a complete legal obligation with a condition, a deadline and consequences.
