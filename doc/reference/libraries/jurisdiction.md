# Jurisdiction Library

Jurisdiction definitions for multi-jurisdictional legal rules. Uses ISO 3166-1 country codes (alpha-2, alpha-3, and numeric) and ISO 3166-2 subdivision codes. Import with `IMPORT jurisdiction`.

**Status:** Prototype (version 1.0.0). API may change.

### Location

[jl4-core/libraries/jurisdiction.l4](https://github.com/legalese/l4-ide/blob/main/jl4-core/libraries/jurisdiction.l4)

### Constants

Twenty major countries are provided with three constants each, e.g. for the United States:

```l4
`United States alpha-2` MEANS "US"
`United States alpha-3` MEANS "USA"
`United States numeric` MEANS 840
```

Covered countries: United States, United Kingdom, Canada, Australia, Germany, France, China, Japan, Singapore, India, Brazil, Mexico, Switzerland, Netherlands, Sweden, New Zealand, South Korea, Italy, Spain, Hong Kong.

Additional constant groups (each providing `... code` and `... name` STRING constants):

| Group                     | Entries                                                                                           |
| ------------------------- | ------------------------------------------------------------------------------------------------- |
| Supranational regions     | `European Union`, `ASEAN`, `NAFTA` (code `"USMCA"`)                                               |
| US states (ISO 3166-2:US) | California, New York, Texas, Florida, Illinois, Pennsylvania, Massachusetts, Washington, Delaware |
| Canadian provinces        | Ontario, Quebec, British Columbia, Alberta                                                        |
| UK constituent countries  | England (`"GB-ENG"`), Scotland (`"GB-SCT"`), Wales (`"GB-WLS"`), Northern Ireland (`"GB-NIR"`)    |

### Validation Functions

| Function                           | Signature          | Description                                                    |
| ---------------------------------- | ------------------ | -------------------------------------------------------------- |
| `is valid ISO 3166-1 alpha-2` code | `STRING → BOOLEAN` | Exactly 2 characters, all uppercase                            |
| `is valid ISO 3166-1 alpha-3` code | `STRING → BOOLEAN` | Exactly 3 characters, all uppercase                            |
| `is valid ISO 3166-2` code         | `STRING → BOOLEAN` | At least 4 characters, uppercase country prefix, `-` separator |

These are format checks only — they do not verify that the code is an assigned ISO code.

### Country Name Lookup

Both lookups return `RIGHT name` for known codes and `LEFT errorMessage` for unknown ones.

| Function                         | Signature                       | Description                     |
| -------------------------------- | ------------------------------- | ------------------------------- |
| `country name from alpha-2` code | `STRING → EITHER STRING STRING` | English name from 2-letter code |
| `country name from alpha-3` code | `STRING → EITHER STRING STRING` | English name from 3-letter code |

### Code Conversion Functions

| Function                  | Signature                       | Description                               |
| ------------------------- | ------------------------------- | ----------------------------------------- |
| `alpha-2 to alpha-3` code | `STRING → EITHER STRING STRING` | Convert 2-letter to 3-letter country code |
| `alpha-3 to alpha-2` code | `STRING → EITHER STRING STRING` | Convert 3-letter to 2-letter country code |

Lookups and conversions cover the twenty countries listed above; other codes produce a `LEFT` error.

**See [jurisdiction.l4](https://github.com/legalese/l4-ide/blob/main/jl4-core/libraries/jurisdiction.l4) source for all definitions.**
