# Source locators on `@ref`

This page is for an encoding that keeps its source as a plain-text file and quotes that file in the L4.
It says how to write the quotation, how to tie an `@ref` citation to the lines it rests on, and what a script can and cannot check.
An encoding with no such file still cites with `@ref`; it has no locators to write.

## Why a locator

L4 gives a `--` comment no meaning, so a quotation written as a comment is invisible to the language server and the exporters.
An `@ref` is different.
L4 keeps it on the syntax-tree node that follows it, and the language server and several exporters read it.
A **locator** inside the `@ref` says which lines of the raw source the citation rests on, in a form a script can check against the quotation beneath it; that script is the gate, described below.

## The convention

### Quote lines

A quote line is a comment that copies one or more lines of the raw file:

```
-- src:N | text
-- src:N-M | text
-- src:ID:N | text
-- src:ID:N-M | text
```

`src:N` is line N of the raw file, counting from 1, and lines end at `\n` only.
`src:N-M` is lines N to M.
`ID` is the stem of another raw file in the same directory, so `src:law139-2025-qh15:26` is line 26 of `law139-2025-qh15.txt`, beside the raw file.
A quote line is a verbatim slice of the raw lines it names.
`srcrefs.py quote` prints quote lines ready to paste, so the text is copied and never retyped.
It squeezes each line's whitespace to single spaces, writes it in Unicode NFC, and leaves out raw lines that are blank; the numbers it prints are still the raw file's own.

### Locators

A locator is `src:N`, `src:N-M`, `src:ID:N` or `src:ID:N-M`.
N is at most M.
ID matches `[A-Za-z][\w.-]*`.
Write a range with an ASCII hyphen and nothing else.
`src:1–5` (en dash), `src:1—5`, `src:1..5`, `src:1 - 5` and `src:1,5` would be read as the single line `src:1` if the gate took them as locators, so it reports each as malformed.

### The `@ref` line

An `@ref` line may contain any number of locators anywhere in its text.
The text outside the locators is the human citation.

```
@ref Điều 35 (src:760-769)
```

An `@ref` with no locator is legal L4, and the gate ignores it.

The gate reads an `@ref` the way L4's lexer does.
That is `@ref` followed by anything but `-src` or `-map`, or `<<...>>`, outside a comment, a string and a backtick name.
So `@ref(src:1)` and `@reference src:1` are `@ref`s to L4 and to the gate, because the lexer matches the herald as a prefix.
`@ref-map` and `@ref-src` are other annotations, and an `@ref` inside `{- -}` or `/* */` is no annotation at all.
A locator anywhere else, such as in a `--` comment or an `@desc`, is ignored.
A `<<...>>` is read only up to the end of its first line, so write it on one line.
Measured with `l4 ast`: `@ref(src:1)` and an own-line `<<Article 1 (src:1)>>` attach to the next declaration, and an `@ref` inside a block comment attaches to nothing.

The text of an `@ref` is also what `@ref-map` matches.
`@ref-map NAME URL` gives an `@ref` a link only when the whole text of the `@ref` equals NAME, compared in lower case and stripped (`jl4-core/src/L4/Citations.hs`).
An `@ref Điều 35 (src:760-769)` is therefore not linked by `@ref-map Điều 35 https://example.com/d35`, and nothing reports it.
To keep the links, repeat the whole text, locator included, as the NAME.

### Placement

- The quote lines stay where they are.
- The `@ref` goes immediately after the last line of the quote run.
  Blank lines and plain `--` comments may sit between.
- The `@ref` sits directly above the first declaration that the run supports.
  A declaration is a `DECLARE`, a `GIVEN`-led rule, a `DECIDE`, or an `@desc` / `@export` block that precedes one of those; the `@ref` goes above that block.
  An `ASSUME` takes an `@ref` too, but `l4` warns that `ASSUME` is being retired, so prefer a `GIVEN`.
- An `@ref` is never placed before a `§` or `§§` heading, before a `#ASSERT`, `#EVAL` or `#CHECK` directive, or at the end of a file.
- If one quote run supports several declarations, the first `@ref` sits under the run.
  Every rule is cited, so each later declaration carries its own `@ref`, with the same or a narrower locator; the gate asks only for the first.

The `@ref` goes above its declaration because L4 binds an `@ref` to the next syntax node, of whatever kind.
Measured with `l4 ast`: an `@ref` above a `GIVEN`-led `DECIDE` lands on that `Decide`; one above a `§` heading lands on the `Section`; one above a `#ASSERT` lands on the `Directive`.
Nothing in L4 checks that the node it landed on is the one you meant.

## Worked example: Law 08/2022/QH15, Điều 35

`law08-2022-qh15.txt` is the plain-text rendering of the gazette text of Law 08/2022/QH15, and its lines 760 to 769 are Điều 35.
`python3 -I srcrefs.py quote law08-2022-qh15.txt 760 765` printed the first six quote lines below.
The module is saved as `dieu-35.l4`, and its two rules are deliberately small: they show the placement and are not the whole of Điều 35.

```l4
@lang en
IMPORT prelude

§§ `Dieu 35: the period for thinking it over`

-- src:760 | Điều 35. Thời gian cân nhắc tham gia bảo hiểm
-- src:761 | Đối với các hợp đồng bảo hiểm có thời hạn trên 01 năm, trong thời hạn 21
-- src:762 | ngày kể từ ngày nhận được hợp đồng bảo hiểm, bên mua bảo hiểm có quyền từ
-- src:763 | chối tiếp tục tham gia bảo hiểm. Trường hợp bên mua bảo hiểm từ chối tiếp tục
-- src:764 | tham gia bảo hiểm thì hợp đồng bảo hiểm sẽ bị hủy bỏ, bên mua bảo hiểm được
-- src:765 | hoàn lại phí bảo hiểm đã đóng sau khi trừ đi chi phí hợp lý (nếu có) theo thỏa
-- src:768 | thuận trong hợp đồng bảo hiểm; doanh nghiệp bảo hiểm không phải bồi thường, trả
-- src:769 | tiền bảo hiểm khi xảy ra sự kiện bảo hiểm.
@ref Điều 35 (src:760-769)
GIVEN days IS A NUMBER
GIVETH A BOOLEAN
`Dieu 35: the policyholder may still refuse to go on` days MEANS
    days AT MOST 21

@ref Điều 35 (src:768-769)
GIVEN refused IS A BOOLEAN
GIVETH A BOOLEAN
`Dieu 35: the insurer need not pay for an insured event` refused MEANS
    refused
```

Raw line 766 is the gazette's page footer and line 767 is blank.
The quote leaves both out, and the locator `src:760-769` still passes, because a gap inside a range is allowed.
The eight quote lines are one run, so the first `@ref` goes under the last of them and above the first rule.
The second rule rests on the tail of the same run, so it carries its own `@ref` with the narrower locator `src:768-769`.
The `§§` heading comes before the quote lines, and no `@ref` sits above it.

A quotation from another raw file in the same directory carries that file's ID.
Law 139/2025/QH15 adds a clause 3 to Điều 3 of Law 08/2022/QH15, and `python3 -I srcrefs.py quoteid law139-2025-qh15.txt 26 30` printed the quote lines below:

```l4
§§ `Dieu 3(3): who may put capital into an insurance enterprise`

-- src:law139-2025-qh15:26 | “3. Tổ chức, cá nhân có quyền tham gia góp vốn thành lập, quản lý, kiểm
-- src:law139-2025-qh15:27 | soát doanh nghiệp bảo hiểm, doanh nghiệp tái bảo hiểm, doanh nghiệp môi giới
-- src:law139-2025-qh15:28 | bảo hiểm, tổ chức tương hỗ cung cấp bảo hiểm vi mô, chi nhánh nước ngoài tại
-- src:law139-2025-qh15:29 | Việt Nam, trừ trường hợp tổ chức, cá nhân không có quyền thành lập và quản lý
-- src:law139-2025-qh15:30 | doanh nghiệp tại Việt Nam theo quy định của Luật Doanh nghiệp.”.
@ref Điều 3 khoản 3, added by Law 139/2025/QH15 (src:law139-2025-qh15:26-30)
GIVEN `barred under the Law on Enterprises` IS A BOOLEAN
GIVETH A BOOLEAN
`Dieu 3(3): may contribute capital` `barred under the Law on Enterprises` MEANS
    NOT `barred under the Law on Enterprises`
```

The ID must agree between a quote line and a locator: `src:26` and `src:law139-2025-qh15:26` name different lines of different files.

## The gate

```
python3 -I srcrefs.py check [--refs | --strict] RAW FILE...
```

`srcrefs.py` ships in this skill's `assets/`; copy it into the encoding directory, as you do `check.sh`.
It uses only the Python standard library, and `-I` keeps the current directory out of Python's import path.
It is language-neutral: it compares text and has no rules for any one language.
`quoteid RAW N [M]` is `quote` with `src:ID:N`, ID being the stem of RAW.

There are three levels.
Without a flag, `check` enforces R1 only.
With `--refs`, it also enforces R2 and R3.
With `--strict`, which implies `--refs`, it enforces the local forms of R2 and R3 and one more rule, described after them.

Two words are used below.
A **line of code** is any line that is not blank, not a comment and not an `@ref`: a declaration, an `@desc`, a `§` heading, a directive.
A **block** is the stretch of a file between two lines of code.
It holds only quote lines, comments, blank lines and `@ref`s, and it ends at the next line of code or at the end of the file.

- **R1.** Every quote line is a verbatim slice of the raw lines it names, about lines that exist, and it has some text.
  The numbers must satisfy 1 <= N <= M <= the number of lines of the raw file.
  The comparison is on NFC, case-folded text with punctuation and whitespace collapsed, and the quotation must start and end at a word boundary of the raw lines, so `1 ngày` is not a slice of `21 ngày`.
  A trailing ellipsis (`…` or `...`) means "prefix of": the quotation may then stop inside a word.
  An `ID` with no `ID.txt` beside RAW is a problem.
- **R2.** Every locator lies inside the quoted ranges of the same file: both N and M must be covered by some quote line in that file with the same ID.
  Gaps inside the range are allowed, because raw lines such as page footers are often left out of a quote run.
- **R3.** Every maximal run of quote lines is overlapped by at least one locator in the same file with the same ID, otherwise it is an "orphan quotation".
  A run is consecutive quote lines; blank lines do not break a run, and any other line does.
  A run whose block ends at a `§` or `§§` heading, at a `#` directive (`#ASSERT`, `#EVAL`, `#CHECK`) or at the end of the file is exempt, because the convention puts no `@ref` before those.

With `--strict`, R2 and R3 look only at the block.

- **R2, strictly.** A locator must be covered by the runs above it in its own block.
  An `@ref` that has none above it in its block, such as a later declaration citing the same run, is checked against the nearest run above it in the file.
- **R3, strictly.** A run needs an overlapping locator, with the same ID, on an `@ref` in its own block below it.
  An `@ref` above the run, in another block, or after code on the same line does not count.
- **Exactness.** In every block that is not exempt, and for every ID the block quotes, the locators on the block's `@ref`s must reach exactly the lowest and the highest raw line that its runs quote.
  A locator that is narrowed or shifted by one line is then a problem, and so is a first `@ref` that is deliberately narrower than its run.
  Later declarations are in other blocks and may still be narrower.

Use `--strict` on a row whose `@ref`s are generated, or kept to the convention by hand.
Use `--refs` on a row that cites broadly, such as an `@ref` that names a range quoted in several places further up the file.

Each problem prints as `file:line: reason`, and the summary line prints the counts of quote lines, runs, locators and problems.
The exit status is 1 if there is any problem.
On the example above, with the Law 08/2022/QH15 text as `law08-2022-qh15.txt` in the same directory, both `--refs` and `--strict` print:

```
$ python3 -I srcrefs.py check --strict law08-2022-qh15.txt dieu-35.l4
srcrefs check: 8 src: lines, 1 runs, 2 locators, 0 problems
```

Without `--refs`, a file that carries no locators is checked for R1 alone.

## Failures, sorted into loud and silent

A **loud** failure exits non-zero.
A **silent** failure exits 0 and leaves a wrong answer standing, so these are the ones worth the attention.

### Loud: `srcrefs.py check` exits 1

| Failure                                                                                        | Rule   | Runs                 |
| ---------------------------------------------------------------------------------------------- | ------ | -------------------- |
| A quote line that is not a slice of the raw lines it names (the words differ or a word is cut) | R1     | always               |
| A quote line with lines that do not exist (N < 1, N > M, past the end) or with no text         | R1     | always               |
| A quote line that names an ID with no `ID.txt` beside RAW                                      | R1     | always               |
| The raw file is regenerated and its lines move, so numbered quotations no longer match         | R1     | always               |
| A locator that is malformed, or written with a dash that is not `-`, with `..` or with `,`     | R2     | only with `--refs`   |
| A locator that reaches a line that no quote line covers                                        | R2     | only with `--refs`   |
| A run of quote lines that no locator overlaps ("orphan quotation"), unless its block is exempt | R3     | only with `--refs`   |
| A locator that is narrowed or shifted by a line, or reaches into the next run                  | strict | only with `--strict` |
| A run covered only by a locator elsewhere in the file, or by an `@ref` above it                | strict | only with `--strict` |

### Silent: exit 0, and the answer may be wrong

| Failure                                                                                                              | Why nothing says so                                                                                                                                                                                                                                                                                                                |
| -------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `check` run without `--refs`                                                                                         | R2 and R3 are not run, so a locator outside the quotation and an orphan quotation both pass.                                                                                                                                                                                                                                       |
| A locator that names the wrong provision but lies inside the quoted lines, such as `@ref Điều 36 (src:760-769)`      | The gate never reads the citation text outside the locators, and it does not know what the lines mean.                                                                                                                                                                                                                             |
| A locator wider or narrower than the provision, but still inside the quoted lines                                    | R2 asks only that the ends be covered. `--strict` compares the lowest and the highest line the `@ref`s of a block reach with the lines its runs quote, so it catches a first `@ref` that is wider or narrower at either end. It does not catch a change to a locator in the middle of several, or to a later declaration's `@ref`. |
| A locator far from the run it covers, with `--refs` only                                                             | R3 asks for some overlapping locator in the same file. One wide `@ref` at the end of a file covers every run, and a deleted `@ref` goes unnoticed if another still overlaps its run.                                                                                                                                               |
| A run that skips lines inside its own locator's range, whether a footer or a line deleted by mistake                 | R2 allows gaps, because footers are left out. Nothing checks that every raw line in the range is quoted.                                                                                                                                                                                                                           |
| A quote that differs from the source only in punctuation, case or spacing                                            | R1 compares normalised text, and a semicolon or a bracket can carry legal meaning.                                                                                                                                                                                                                                                 |
| A run followed by a `§` heading, a directive or the end of a file, where an `@ref` was meant                         | R3 exempts it, because the convention puts no `@ref` there. The quotation is still checked by R1.                                                                                                                                                                                                                                  |
| A comment that looks like a quote line but is not one, such as `-- src:1–5 \| text` (en dash) or a line with no `\|` | The marker is not recognised, so the line is an ordinary comment and R1 never sees it.                                                                                                                                                                                                                                             |
| An `@ref-map` name that does not repeat the `@ref` text, locator included                                            | L4 matches the whole text, and the link is simply missing. Nothing reports it.                                                                                                                                                                                                                                                     |
| An `@ref` above the wrong declaration, including one declaration too late                                            | L4 binds an `@ref` to the next syntax node. Measured: an `@ref` written under its rule attached to the rule below it, with no message.                                                                                                                                                                                             |
| An `@ref` before a `§` or `§§` heading, or before a `#ASSERT`                                                        | It attaches to the heading or the directive. Measured: `l4 check` printed `Check succeeded`.                                                                                                                                                                                                                                       |
| Two `@ref` lines above one declaration                                                                               | L4 keeps the nearer one and reports the other as unattached. It prints a warning, but `l4 check` still exits 0.                                                                                                                                                                                                                    |
| An `@ref` at the end of a file                                                                                       | L4 prints "could not be attached to any following syntax node", but `l4 check` still exits 0.                                                                                                                                                                                                                                      |
| An encoding that does not mean what the quoted text says                                                             | The gate compares text with text.                                                                                                                                                                                                                                                                                                  |

The last two L4 rows are printed, not hidden, but `check.sh` does not show them: it counts errors and assertion outcomes only.
List them with `l4`, run on each module:

```
for f in *.l4; do l4 check "$f"; done 2>&1 | grep 'could not be attached'
```

Measured: on a file that ended in an `@ref`, and on one with two `@ref` lines above a rule, `check.sh` printed a table of zeros and exited 0, and the command above printed one line for each.

## What the gate does not check

It does not check that a locator names the right provision, so a wrong but covered range passes.
It does not check that the `@ref` is above the right declaration.
It does not check that the quotation is complete inside its locator.
It does not check that the encoding is right.
Those are the silent rows above, and they are reviewed by a person holding the source beside the module.
