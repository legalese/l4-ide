# holdings

Debt and equity ownership library for financial structures: cap table representation, vesting, conversion (notes/SAFEs), liquidation preferences, and valuation. Inspired by the ACTUS Financial Research Foundation. Import with `IMPORT holdings` (also imports prelude, daydate, currency, and legal-persons).

## Constants

Security and debt type codes (all `STRING`):

| Constant                                                                                        | Values                                                                                                        |
| ----------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| `Common Stock`, `Preferred Stock`, `Convertible Note`, `SAFE`, `Warrant`, `Stock Option`, `RSU` | `"COMMON_STOCK"`, `"PREFERRED_STOCK"`, `"CONVERTIBLE_NOTE"`, `"SAFE"`, `"WARRANT"`, `"STOCK_OPTION"`, `"RSU"` |
| `Senior Debt`, `Subordinated Debt`, `Convertible Debt`, `Bridge Loan`                           | `"SENIOR_DEBT"`, `"SUBORDINATED_DEBT"`, `"CONVERTIBLE_DEBT"`, `"BRIDGE_LOAN"`                                 |

## Ownership calculations

| Function                                       | Signature                  | Description                                               |
| ---------------------------------------------- | -------------------------- | --------------------------------------------------------- |
| `ownership percentage` sharesOwned totalShares | `NUMBER → NUMBER → NUMBER` | Percentage owned (0 when totalShares is 0)                |
| `is dilutive` securityType                     | `STRING → BOOLEAN`         | TRUE for convertibles, SAFEs, warrants, and stock options |

## Preference calculations

| Function                                                                          | Signature                                     | Description                                                               |
| --------------------------------------------------------------------------------- | --------------------------------------------- | ------------------------------------------------------------------------- |
| `liquidation preference` investmentAmount preferenceMultiple                      | `NUMBER → NUMBER → NUMBER`                    | Preference amount = investment × multiple                                 |
| `preferred payout` isParticipating liquidationValue preferenceAmount ownershipPct | `BOOLEAN → NUMBER → NUMBER → NUMBER → NUMBER` | Participating: preference + pro-rata; otherwise max(preference, pro-rata) |

## Vesting calculations

| Function                                                                           | Signature                                         | Description                                                           |
| ---------------------------------------------------------------------------------- | ------------------------------------------------- | --------------------------------------------------------------------- |
| `vested shares` totalShares vestingStartDate cliffMonths vestingMonths currentDate | `NUMBER → DATE → NUMBER → NUMBER → DATE → NUMBER` | Linear monthly vesting: 0 before cliff, all after full vesting period |
| `approximate months since` startDate endDate                                       | `DATE → DATE → NUMBER`                            | Calendar-month difference (year/month fields only)                    |

## Conversion calculations

| Function                                                                                                    | Signature                                                  | Description                                                                     |
| ----------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------- | ------------------------------------------------------------------------------- |
| `shares from convertible` principalAmount interestRate issueDate conversionDate conversionPrice discountPct | `NUMBER → NUMBER → DATE → DATE → NUMBER → NUMBER → NUMBER` | Shares from a convertible note: principal + simple interest at discounted price |
| `shares from SAFE` investmentAmount valuationCap discountPct pricePerShare                                  | `NUMBER → NUMBER → NUMBER → NUMBER → NUMBER`               | Shares from a SAFE: lower of cap price and discounted price                     |

## Debt service calculations

| Function                                                            | Signature                                | Description                                      |
| ------------------------------------------------------------------- | ---------------------------------------- | ------------------------------------------------ |
| `accrued interest` principalAmount annualRate issueDate currentDate | `NUMBER → NUMBER → DATE → DATE → NUMBER` | Simple interest over elapsed days (365-day year) |
| `debt service coverage` operatingIncome debtPayment                 | `NUMBER → NUMBER → NUMBER`               | DSCR = income / payment (0 when payment is 0)    |

## Cap table aggregations

| Function                                                                               | Signature                                    | Description              |
| -------------------------------------------------------------------------------------- | -------------------------------------------- | ------------------------ |
| `total shares` sharesList                                                              | `LIST OF NUMBER → NUMBER`                    | Sum of share counts      |
| `fully diluted shares` commonShares preferredShares optionPoolShares convertibleShares | `NUMBER → NUMBER → NUMBER → NUMBER → NUMBER` | Sum of all share classes |

## Valuation calculations

| Function                                                  | Signature                  | Description                  |
| --------------------------------------------------------- | -------------------------- | ---------------------------- |
| `post-money valuation` pricePerShare fullyDilutedShares   | `NUMBER → NUMBER → NUMBER` | Price × fully diluted shares |
| `pre-money valuation` postMoneyValuation investmentAmount | `NUMBER → NUMBER → NUMBER` | Post-money minus investment  |

## Temporal tracking helpers

| Function                                           | Signature                      | Description                                        |
| -------------------------------------------------- | ------------------------------ | -------------------------------------------------- |
| `is active at` issuanceDate maturityDate checkDate | `DATE → DATE → DATE → BOOLEAN` | Check date within [issuance, maturity] (inclusive) |
| `has matured` maturityDate checkDate               | `DATE → DATE → BOOLEAN`        | Check date strictly after maturity                 |
