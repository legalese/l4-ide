# L4 Concepts

Understanding-oriented explanations of the principles, theories, and design decisions behind L4.

## Purpose

Concepts documentation helps you understand:

- **Why** L4 works the way it does
- **How** different features relate to each other
- **When** to use particular patterns or approaches
- **What** theoretical foundations support L4's design

Unlike reference docs (which tell you **what** things are) or tutorials (which show you **how** to do things), concepts explain the **why** and provide deeper understanding.

---

## Topics

### 🎨 Language Design

The philosophy and principles behind L4's design

- **[Principles](language-design/principles.md)** - Core design principles of L4
- **[Flowcharts, Decision Tables, and Real Logic](language-design/logic-not-flowcharts.md)** - Why L4 is a language with derived diagrams, not a flowchart or decision-table builder
- **[Linguistic Syntax](language-design/linguistic-syntax.md)** - How L4 borrows from natural language linguistics

**Key Ideas:** Human-readable code, legal text fidelity, accessibility for non-programmers, diagrams as views not substrate

_More topics planned: Layout Sensitivity, Scope_

---

### ⚖️ Legal Modeling

Representing legal concepts in code

- **[Regulative Rules](legal-modeling/regulative-rules.md)** - Obligations, permissions, prohibitions
- **[Constitutive vs Regulative Rules](legal-modeling/constitutive-vs-regulative.md)** - Definitions vs duties, and why L4 separates them at the type level
- **[Default Reasoning and Exceptions](legal-modeling/default-reasoning.md)** - Defeasibility, UNLESS, and encoding general-rule-plus-exception structure

**Key Ideas:** Deontic modalities, legal rules as code, contract patterns, defeasibility

_More topics planned: Deontic Logic, Contract Composition_

---

### 🏗️ Type System

How L4's type system works

- **[Algebraic Types](type-system/algebraic-types.md)** - Sum types and product types
- **[Exhaustiveness](type-system/exhaustiveness.md)** - Totality as a legal-safety property: every case of a determination handled

**Key Ideas:** Type safety, algebraic data types, functional programming influence

_More topics planned: Maybe and Nothing, Type Inference_

---

## How to Use Concepts

### During Learning

- Read concept docs **after** you've tried the feature in practice
- Concepts build on knowledge from [courses](../courses/README.md) and [tutorials](../tutorials/README.md)

### For Deeper Understanding

- Concepts explain the "why" behind language features
- Use concepts to inform design decisions in your L4 programs

### For Discussion

- Concepts provide vocabulary for discussing L4 design
- Reference concepts when proposing changes or new features
