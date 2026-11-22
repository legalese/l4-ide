# Search Query Syntax

**Status:** Done (l4-ide; `search_l4_docs` in ai-proxy, the account-wide `search_rules` in jl4-auth-proxy).

Agents sent grep-style queries to tools that didn't read them that way. `fs__read_file` split `search_keywords` on every space, so a query such as

```
^(GIVEN|DECIDE|@export)?.*(sum|max|min|map|`greater of`|maximum|minimum|fold)
```

became two invalid regexes, each silently matched as plain text: `matches=0` and no hint why. `search_text` took the whole query as one substring, the rule searches split on spaces only, and the doc search split on some punctuation but not `|`, `^` or `*`. Every search now either reads such a query or says exactly what it takes, and an empty result says how to search instead.

## Pattern search

`fs__read_file` with `search_keywords` (Legalese AI, `ts-shared/legalese-agent/src/search-patterns.ts`) and jl4-service's `search_text` (MCP, WebMCP, and the REST `?search=`; `jl4-service/src/SearchPattern.hs`):

- Spaces separate patterns, and a line matches when any pattern does. Spaces inside `()`, `[]`, `{}`, backticks or double quotes don't separate, so the query above is one pattern. A backslash escapes the next character.
- Double quotes around a pattern are dropped: `"net income"` is a phrase.
- Each pattern is a case-insensitive regular expression: `^ $ . * + ? | ( ) [ ] {n,m}` and `\s \d \w \b`.
- A pattern that isn't a valid regular expression is matched as plain text, and the result says so with the reason: `Note: "f(x" is not a valid regular expression (Unterminated group), so it was matched as plain text.`
- No match: the result explains the syntax and what to try (fewer or shorter patterns, alternatives, `\s` for a space) and where else to look (drop `startLine`/`endLine`, search `.`; drop `file` or `deployment`).

jl4-service runs patterns with regex-tdfa, which takes linear time, so no pattern can stall the server. Its POSIX syntax lacks some of JavaScript's, so `\s \d \w` (and `\S \D \W` outside brackets) become POSIX classes, `(?:` a plain group, and a lazy quantifier the greedy one, which finds the same lines. Lookarounds and backreferences aren't supported there and fall back to plain text with the note.

`search_text` keeps its JSON array of matches as the first content item; the note and the hint come as a second item. Clients that read only the first item see what they did before. The hint never repeats the query: a scoped endpoint's answer must not show text from elsewhere.

## Word search

`search_rules` (Legalese AI's own, jl4-auth-proxy's account-wide one and the WebMCP one), the skills search and `search_l4_docs` rank names, descriptions or docs by keyword, where a regex doesn't fit. They take the query's words: runs of letters and digits, everything else separating them, so the query above searches `given`, `decide`, `export`, `sum` and so on, rather than nothing. `search_l4_docs` keeps a leading `@` or `#` (`@export`, `#EVAL`).

- A rule or deployment matches if any word does; more matching words rank higher. The WebMCP `search_rules` used to need every word; it now ranks by how many match, like the others.
- Each tool's description says the query is plain words and regex syntax is ignored, with an example.
- No match: the result says the same and what to try (synonyms, a shorter form); Legalese AI's own lists the words it searched for. Responses that are JSON (`search_rules` on the account-wide server, the skills search) carry it in a `hint` field.

## Identifier search

`search_identifier` takes one whole L4 name, case-sensitive, with or without backticks (`` `the greater of` `` now finds what `the greater of` finds). Its description says so and points to `search_text` for anything else; an empty result says the same.
