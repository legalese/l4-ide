# Currency Library

Currency handling with ISO 4217 currency codes. Stores amounts as integer minor units (cents) to avoid floating-point errors. Import with `IMPORT currency` (also imports jurisdiction).

**Status:** Prototype (version 1.0.0). API may change.

### Location

[jl4-core/libraries/currency.l4](https://github.com/legalese/l4-ide/blob/main/jl4-core/libraries/currency.l4)

### Supported Currencies

USD, EUR, GBP, JPY, CHF, CAD, AUD, CNY, HKD, SGD, INR, BRL, MXN, SEK, NZD, KRW

Each currency provides constants, e.g. `` `US Dollar code` `` (`"USD"`), `` `US Dollar numeric` `` (840), `` `US Dollar decimals` `` (2), and `` `US Dollar country` ``. JPY and KRW have 0 decimal places; all others 2.

### Construction and Formatting

| Function                                   | Signature                                | Description                                                                                                                                      |
| ------------------------------------------ | ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `Money` minorUnits currencyCode            | `NUMBER → STRING → EITHER STRING STRING` | Format minor units as an amount string, e.g. `Money 12345 "USD"` → `RIGHT "123.45 USD"`. LEFT for unknown currencies or non-integer minor units. |
| `decimal places for currency` currencyCode | `STRING → EITHER STRING NUMBER`          | Minor-unit decimal places for a currency code                                                                                                    |
| `power of 10` exponent                     | `NUMBER → NUMBER`                        | 10^n for n in 0-3 (defaults to 100 otherwise)                                                                                                    |

The zero-padding and decimal-point formatting are performed by helpers (`formatAmount`, `formatNumber`, `padLeft`) local to `Money`'s WHERE clause — they are not separately importable.

### Amount Conversion

| Function                                       | Signature                                | Description                             |
| ---------------------------------------------- | ---------------------------------------- | --------------------------------------- |
| `major to minor units` majorUnits currencyCode | `NUMBER → STRING → EITHER STRING NUMBER` | Dollars to cents (floors to an integer) |
| `minor to major units` minorUnits currencyCode | `NUMBER → STRING → EITHER STRING NUMBER` | Cents to dollars                        |

### Arithmetic Operations

All arithmetic works on minor-unit amounts and validates the currency code first (LEFT for unknown currencies).

| Function                                      | Signature                                         | Description                                         |
| --------------------------------------------- | ------------------------------------------------- | --------------------------------------------------- |
| `add money` amount1 amount2 currencyCode      | `NUMBER → NUMBER → STRING → EITHER STRING NUMBER` | Sum of two amounts                                  |
| `subtract money` amount1 amount2 currencyCode | `NUMBER → NUMBER → STRING → EITHER STRING NUMBER` | Difference of two amounts                           |
| `multiply money` amount factor currencyCode   | `NUMBER → NUMBER → STRING → EITHER STRING NUMBER` | Amount × factor, floored to whole minor units       |
| `divide money` amount divisor currencyCode    | `NUMBER → NUMBER → STRING → EITHER STRING NUMBER` | Amount ÷ divisor, floored; LEFT on division by zero |

### Comparison Operations

Plain minor-unit comparisons (both amounts assumed to be in the same currency):

| Function                             | Signature                   | Description        |
| ------------------------------------ | --------------------------- | ------------------ |
| `money equal` amount1 amount2        | `NUMBER → NUMBER → BOOLEAN` | amount1 = amount2  |
| `money greater than` amount1 amount2 | `NUMBER → NUMBER → BOOLEAN` | amount1 > amount2  |
| `money less than` amount1 amount2    | `NUMBER → NUMBER → BOOLEAN` | amount1 < amount2  |
| `money at least` amount1 amount2     | `NUMBER → NUMBER → BOOLEAN` | amount1 >= amount2 |
| `money at most` amount1 amount2      | `NUMBER → NUMBER → BOOLEAN` | amount1 <= amount2 |

### Validation Functions

| Function                      | Signature          | Description                                       |
| ----------------------------- | ------------------ | ------------------------------------------------- |
| `is valid currency code` code | `STRING → BOOLEAN` | Exactly 3 characters, all uppercase (format only) |
| `is non-negative` amount      | `NUMBER → BOOLEAN` | amount >= 0                                       |
| `is positive` amount          | `NUMBER → BOOLEAN` | amount > 0                                        |

### Example: Currency Operations

[currency-example.l4](currency-example.l4)

**See [currency.l4](https://github.com/legalese/l4-ide/blob/main/jl4-core/libraries/currency.l4) source for all functions.**
