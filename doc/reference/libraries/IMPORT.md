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

### Importing Local Files

```l4
IMPORT myhelpers
IMPORT utils
```

## Available Libraries

L4 includes several standard libraries:

| Library         | Description              |
| --------------- | ------------------------ |
| `prelude`       | Core functions           |
| `math`          | Mathematical functions   |
| `daydate`       | Date calculations        |
| `excel-date`    | Excel date compatibility |
| `currency`      | Currency handling        |
| `legal-persons` | Legal entity types       |

## Import Resolution

1. Every library, `prelude` included, has to be asked for by name. Nothing is in scope until
   you write its `IMPORT` line
2. A file of that name in your own project is used before the standard library: one in the project
   root, or one beside the file that writes the `IMPORT`
3. Failing that, the standard library built into the `l4` you are running is used. It matches that
   `l4` exactly and needs no files on disk

L4 also looks in a few places that an operator or an installer controls (the `JL4_LIBRARY_PATH`
environment variable, a per-user library folder, the editor extension's own copy), and in a fixed
order — a copy sitting beside your file outranks the copy built into the compiler, for instance.
[Library Resolution](resolution.md) sets out the whole order and when each step matters.

## See Also

- **[Libraries Reference](../libraries/README.md)** - Available libraries
