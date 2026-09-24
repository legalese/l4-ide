# IMPORT

Imports definitions from another L4 file or library.

## Syntax

```l4
IMPORT filename
IMPORT `hyphenated-name`
```

## Purpose

IMPORT brings type definitions, functions, and values from another L4 source file into the current file's scope.

## Examples

**Example file:** [import-example.l4](import-example.l4)

### Importing Core Libraries

```l4
IMPORT math
IMPORT daydate
IMPORT currency
```

### Importing Hyphenated Names

Use backticks for names containing hyphens:

```l4
IMPORT `legal-persons`
IMPORT `excel-date`
```

### Importing Names That Are Not Plain ASCII

Backticks also cover a basename with spaces or non-ASCII letters:

```l4
IMPORT `my helpers`
IMPORT `hvac-law-he`
```

On a build older than the fix for [smucclaw/l4-ide#971](https://github.com/smucclaw/l4-ide/issues/971) these resolved to nothing, and said nothing about it — see [Library Resolution](resolution.md#module-names-that-are-not-plain-ascii).

### Importing Local Files

```l4
IMPORT myhelpers
IMPORT utils
```

## Available Libraries

L4 includes several standard libraries:

| Library         | Description                    |
| --------------- | ------------------------------ |
| `prelude`       | Core functions (auto-imported) |
| `math`          | Mathematical functions         |
| `daydate`       | Date calculations              |
| `excel-date`    | Excel date compatibility       |
| `currency`      | Currency handling              |
| `legal-persons` | Legal entity types             |
| `coercion`      | Type conversions               |

## Import Resolution

1. Prelude is automatically imported in all files
2. Library names resolve to `jl4-core/libraries/`
3. Relative names resolve to the current directory

An `IMPORT` that resolves to nothing is an error, even if your file never uses anything from it: the
message names the module and every location that was searched. It fails `l4 check` and `l4 run`;
most other commands print it and still exit 0. See
[When nothing resolves](resolution.md#when-nothing-resolves).

## See Also

- **[Libraries Reference](../libraries/README.md)** - Available libraries
