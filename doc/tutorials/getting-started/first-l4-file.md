# Install L4 and write your first rule

Set up L4, write a short eligibility rule, and run it.

---

## Install L4

### VS Code extension

This is the main way to work with L4.

1. Install [VS Code](https://code.visualstudio.com/).
2. Install the [L4 extension](https://marketplace.visualstudio.com/items?itemName=Legalese.l4-vscode) from the Marketplace.
3. Open or create a file ending in `.l4`. The extension checks it as you type, shows errors and results, draws decision diagrams, and adds the L4 sidebar (Legalese AI, Render, Deploy).

The extension also ships the `l4` command-line tool. The first time it starts, it asks "Install the L4 CLI?". Accept, or run **L4: Install L4 CLI** from the Command Palette later. On macOS and Linux it links `l4` into `~/.local/bin`; on Windows it copies `l4.exe` to `%LOCALAPPDATA%\Programs\l4`. Both are added to your PATH. Open a new terminal and check:

```bash
l4 --help
```

### Web editor

To try L4 without installing anything, open the web editor at [play.legalese.com](https://play.legalese.com/).

Developers can also build `l4` from source; see [Using the l4 CLI](l4-cli.md).

---

## Write the rule

The rule: _a person is eligible if they are at least 18 years old and have valid ID._

Create a file called `eligibility.l4` with this content:

[eligibility-example.l4](eligibility-example.l4)

What each part does:

| Part                                  | Meaning                                                                                                                   |
| ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| `-- ...`                              | A comment. L4 ignores it.                                                                                                 |
| `` § `Eligibility` ``                 | A section heading. `§§` starts a subsection.                                                                              |
| `DECLARE Person HAS ...`              | A record type with three fields: a name (text), an age (number) and whether the person has valid ID (`TRUE` or `FALSE`).  |
| ``GIVEN `the applicant` IS A Person`` | The rule's input.                                                                                                         |
| `GIVETH A BOOLEAN`                    | The rule's answer is `TRUE` or `FALSE`.                                                                                   |
| ``DECIDE `is eligible` IF ...``       | The rule itself: the answer is `TRUE` when the conditions hold. `` `the applicant`'s `age` `` reads a field of the input. |
| `` `Alice` MEANS Person WITH ... ``   | Example data: a person to test the rule on.                                                                               |
| `` #EVAL `is eligible` `Alice` ``     | Evaluate the rule for Alice and show the result.                                                                          |

Names in backticks, such as `` `is eligible` ``, can contain spaces, so rules read like the text they encode. Indentation matters: the lines under `HAS` and `IF` are indented to show they belong there.

---

## Run it

**In VS Code or the web editor**, results appear as you type. Hover over an `#EVAL` line to see its result; errors are underlined in red with an explanation.

**On the command line:**

```bash
l4 run eligibility.l4
```

```
Evaluation[1] @ eligibility.l4:34:1-28

Result:
  TRUE
...
```

There is one `Evaluation` block per `#EVAL`, in file order:

| Expression                    | Result  | Why                       |
| ----------------------------- | ------- | ------------------------- |
| `` `is eligible` `Alice` ``   | `TRUE`  | 25 is at least 18; has ID |
| `` `is eligible` `Bob` ``     | `FALSE` | 16 is under 18            |
| `` `is eligible` `Charlie` `` | `FALSE` | No valid ID               |

`l4 check eligibility.l4` only type-checks the file, without evaluating anything. It prints `Check succeeded.` when the file is valid.

Try a change: add a field `` `is banned` IS A BOOLEAN `` to `Person`, add `` AND NOT `the applicant`'s `is banned` `` to the rule, and give each example person a value for it.

---

## Common mistakes

**Missing indentation.** Fields and conditions must be indented under the line that introduces them.

```l4
-- Wrong: the fields start in column 1
-- DECLARE Person
-- HAS `name` IS A STRING

-- Right
DECLARE Person
    HAS `name` IS A STRING
```

**Missing `'s` in field access.** Write `` `the applicant`'s `age` ``, not `` `the applicant` `age` ``.

**Missing backticks around a name with spaces.** Write ``DECIDE `is eligible` IF``. Without backticks, `is eligible` is two separate words.

---

## Next steps

- [Foundation course](../../courses/foundation/README.md): learn the language step by step.
- [Test your rules](testing-your-rules.md): check that rules give the answers you expect.
- [Using the l4 CLI](l4-cli.md): check, run, batch-evaluate and deploy rules from the command line.
