# Legal-persons Library

Legal entity definitions for natural persons and corporate entities: name/address formatting, identity document validation, age and legal capacity checks, citizenship helpers, and beneficial ownership. Import with `` IMPORT `legal-persons` `` (backticks are required because of the hyphen in the name). Also imports prelude, daydate, and jurisdiction.

**Status:** Prototype (version 1.0.0). API may change.

### Location

[jl4-core/libraries/legal-persons.l4](https://github.com/legalese/l4-ide/blob/main/jl4-core/libraries/legal-persons.l4)

### Name Formatting

| Function                                              | Signature                           | Description         |
| ----------------------------------------------------- | ----------------------------------- | ------------------- |
| `full name` firstName lastName                        | `STRING → STRING → STRING`          | "First Last"        |
| `full name with middle` firstName middleName lastName | `STRING → STRING → STRING → STRING` | "First Middle Last" |
| `formal name` prefix firstName lastName               | `STRING → STRING → STRING → STRING` | "Prefix First Last" |

### Address Components

| Function                                                  | Signature                                             | Description                |
| --------------------------------------------------------- | ----------------------------------------------------- | -------------------------- |
| `format address` street city state postalCode countryCode | `STRING → STRING → STRING → STRING → STRING → STRING` | Single-line address string |
| `is valid US zip code` postalCode                         | `STRING → BOOLEAN`                                    | Format check               |
| `is valid UK postcode` postalCode                         | `STRING → BOOLEAN`                                    | Format check               |
| `is valid Canadian postal code` postalCode                | `STRING → BOOLEAN`                                    | Format check               |

### Identity Document Validation

Constants for document type codes (`Passport type`, `National ID type`, `Drivers License type`, `Social Security type`, `Tax ID type`, `Residence Permit type`), plus format validators (length/separator checks only):

| Function                           | Signature          | Expected format       |
| ---------------------------------- | ------------------ | --------------------- |
| `is valid US SSN format` ssn       | `STRING → BOOLEAN` | `XXX-XX-XXXX`         |
| `is valid Canadian SIN format` sin | `STRING → BOOLEAN` | `XXX-XXX-XXX`         |
| `is valid UK NINO format` nino     | `STRING → BOOLEAN` | `AB123456C` (9 chars) |

### Age Calculations

| Function                                             | Signature                        | Description                              |
| ---------------------------------------------------- | -------------------------------- | ---------------------------------------- |
| `age in years` birthDate referenceDate               | `DATE → DATE → NUMBER`           | Completed years at the reference date    |
| `current age` birthDate                              | `DATE → NUMBER`                  | Age as of TODAY (requires `TIMEZONE IS`) |
| `is at least age` birthDate minimumAge referenceDate | `DATE → NUMBER → DATE → BOOLEAN` | Age check at a reference date            |
| `is currently at least age` birthDate minimumAge     | `DATE → NUMBER → BOOLEAN`        | Age check as of TODAY                    |

### Legal Capacity Checks

Jurisdiction-aware (ISO alpha-2 codes; majority age defaults to 18, with e.g. Japan 20 and South Korea 19):

| Function                                        | Signature                 | Description                       |
| ----------------------------------------------- | ------------------------- | --------------------------------- |
| `is adult` birthDate jurisdictionCode           | `DATE → STRING → BOOLEAN` | Has reached the age of majority   |
| `is minor` birthDate jurisdictionCode           | `DATE → STRING → BOOLEAN` | Negation of `is adult`            |
| `can enter contract` birthDate jurisdictionCode | `DATE → STRING → BOOLEAN` | Currently same as `is adult`      |
| `can vote` birthDate jurisdictionCode           | `DATE → STRING → BOOLEAN` | Voting age check (e.g. Brazil 16) |

### Citizenship Status

| Function                                      | Signature                           | Description                      |
| --------------------------------------------- | ----------------------------------- | -------------------------------- |
| `is citizen of` citizenshipCode countryCode   | `STRING → STRING → BOOLEAN`         | Code equality                    |
| `has citizenship in` citizenships countryCode | `LIST OF STRING → STRING → BOOLEAN` | Membership in a citizenship list |
| `has multiple citizenships` citizenships      | `LIST OF STRING → BOOLEAN`          | At least two citizenships        |
| `citizenship count` citizenships              | `LIST OF STRING → NUMBER`           | Number of citizenships           |

### Corporate Entities

Entity type constants: `Corporation type`, `LLC type`, `LLP type`, `Partnership type`, `Sole Proprietorship type`, `Non-Profit type`, `Cooperative type`, `Trust type`, `Foundation type`. Relationship constants: `Wholly-owned subsidiary relationship`, `Majority-owned subsidiary relationship`, `Minority stake relationship`, `Joint venture relationship`, `Parent company relationship`, `Sister company relationship`, `Affiliated entity relationship`.

**Identifier validation (format checks):**

| Function                         | Signature          | Expected format |
| -------------------------------- | ------------------ | --------------- |
| `is valid US EIN format` ein     | `STRING → BOOLEAN` | `XX-XXXXXXX`    |
| `is valid UK CRN format` crn     | `STRING → BOOLEAN` | 8 characters    |
| `is valid Canadian BN format` bn | `STRING → BOOLEAN` | 9 characters    |

**Status checks (relative to TODAY):**

| Function                                                  | Signature                 | Description                       |
| --------------------------------------------------------- | ------------------------- | --------------------------------- |
| `years since incorporation` incorporationDate             | `DATE → NUMBER`           | Calendar-year difference          |
| `established for at least` incorporationDate minimumYears | `DATE → NUMBER → BOOLEAN` | Age-of-entity check               |
| `is dissolved` incorporationDate dissolutionDate          | `DATE → DATE → BOOLEAN`   | Dissolution date is in the past   |
| `is active corporation` incorporationDate                 | `DATE → BOOLEAN`          | Incorporation date is in the past |

### Beneficial Ownership

| Function                                      | Signature          | Threshold |
| --------------------------------------------- | ------------------ | --------- |
| `is beneficial owner` ownershipPercentage     | `NUMBER → BOOLEAN` | >= 25%    |
| `is majority owner` ownershipPercentage       | `NUMBER → BOOLEAN` | > 50%     |
| `is controlling owner` ownershipPercentage    | `NUMBER → BOOLEAN` | > 50%     |
| `has significant control` ownershipPercentage | `NUMBER → BOOLEAN` | >= 25%    |

### Corporate Jurisdiction

| Function                                                                       | Signature                   | Description                                           |
| ------------------------------------------------------------------------------ | --------------------------- | ----------------------------------------------------- |
| `is Delaware corporation` jurisdictionCode                                     | `STRING → BOOLEAN`          | Code equals `"US-DE"`                                 |
| `is US corporation` / `is UK corporation` / `is Canadian corporation`          | `STRING → BOOLEAN`          | Country prefix / constituent-country checks           |
| `requires registered agent` jurisdictionCode                                   | `STRING → BOOLEAN`          | US, UK, or Canadian corporation                       |
| `is foreign qualification required` businessJurisdiction operatingJurisdiction | `STRING → STRING → BOOLEAN` | Different US jurisdictions for business vs operations |

### Example: Legal Persons

[legal-persons-example.l4](legal-persons-example.l4)

**See [legal-persons.l4](https://github.com/legalese/l4-ide/blob/main/jl4-core/libraries/legal-persons.l4) source for all functions.**
