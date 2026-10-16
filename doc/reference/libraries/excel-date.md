# excel-date

Excel-compatible date helpers: serial conversion (including Excel's 1900 leap-year bug), date differences (`DATEDIF`, `DAYS360`, `YEARFRAC`), month arithmetic (`EDATE`/`EOMONTH` equivalents), and workday calculations. Import it with `` IMPORT `excel-date` `` (the backticks are needed because of the hyphen). Import `daydate` too if you build dates with `Date`.

## Constants

| Constant                   | Value                                     |
| -------------------------- | ----------------------------------------- |
| `Excel 1900 epoch`         | 31 Dec 1899 (serial 0 in the 1900 system) |
| `Excel 1900 bug threshold` | 1 Mar 1900                                |
| `Excel 1900 bug serial`    | 60 (the nonexistent 29 Feb 1900)          |
| `Excel 1904 epoch`         | 1 Jan 1904                                |
| `Excel 1900 epoch days`    | The day number of `Excel 1900 epoch`      |
| `Excel 1904 epoch days`    | The day number of `Excel 1904 epoch`      |

## Serial numbers

| Function                         | Signature                     | Description                                                                    |
| -------------------------------- | ----------------------------- | ------------------------------------------------------------------------------ |
| `day` date                       | `DATE → NUMBER`               | Day of month                                                                   |
| `month` date                     | `DATE → NUMBER`               | Month number                                                                   |
| `year` date                      | `DATE → NUMBER`               | Year number                                                                    |
| `excelSerial1900` date           | `DATE → NUMBER`               | Excel serial (1900 system), reproducing the +1 leap-bug offset from 1 Mar 1900 |
| `excelSerial1904` date           | `DATE → NUMBER`               | Excel serial (1904 system)                                                     |
| `dateFromExcelSerial` serial     | `NUMBER → EITHER STRING DATE` | DATE from a 1900-system serial; serial 60 (the phantom 29 Feb 1900) is a LEFT  |
| `dateFromExcelSerial1904` serial | `NUMBER → EITHER STRING DATE` | DATE from a 1904-system serial                                                 |

## Clock and parsing

| Function                  | Signature                       | Description                                                   |
| ------------------------- | ------------------------------- | ------------------------------------------------------------- |
| `Today serial`            | `NUMBER`                        | `DATE_SERIAL TODAY` (requires `TIMEZONE IS`)                  |
| `Now serial`              | `NUMBER`                        | `DATETIME_SERIAL NOW`                                         |
| `excelToday`              | `DATE`                          | Alias for `TODAY`                                             |
| `excelNow`                | `NUMBER`                        | Excel-style now: 1900-system serial plus time-of-day fraction |
| `ExcelDateValue` text     | `STRING → EITHER STRING DATE`   | Parse date text to a DATE (like Excel `DATEVALUE`)            |
| `ExcelTimeValue` text     | `STRING → EITHER STRING NUMBER` | Parse time text to a day fraction (like Excel `TIMEVALUE`)    |
| `DateValue serial` text   | `STRING → EITHER STRING NUMBER` | Parse date text to a date serial                              |
| `TimeValue fraction` text | `STRING → EITHER STRING NUMBER` | Same as `ExcelTimeValue`                                      |

## DAYS and DATEDIF

| Function                         | Signature                                     | Description                                                                                                 |
| -------------------------------- | --------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `ExcelDays` endDate startDate    | `DATE → DATE → NUMBER`                        | Days between (end − start); also has a `NUMBER → NUMBER → NUMBER` overload for serials                      |
| `DATEDIF` startDate endDate unit | `DATE → DATE → STRING → EITHER STRING NUMBER` | Excel `DATEDIF` with units `"Y"`, `"M"`, `"D"`, `"MD"`, `"YM"`, `"YD"`; LEFT if start > end or unit unknown |

`DATEDIF` also accepts Excel serials in place of either or both DATE arguments (overloads for `NUMBER`/`DATE` combinations).

## DAYS360 and YEARFRAC

| Function                                  | Signature                                      | Description                                                                  |
| ----------------------------------------- | ---------------------------------------------- | ---------------------------------------------------------------------------- |
| `ExcelDays360` startDate endDate          | `DATE → DATE → EITHER STRING NUMBER`           | 30/360 day count, US (NASD) method                                           |
| `ExcelDays360` startDate endDate european | `DATE → DATE → BOOLEAN → EITHER STRING NUMBER` | 30/360 day count; TRUE selects the European method                           |
| `ExcelYearFrac` startDate endDate         | `DATE → DATE → EITHER STRING NUMBER`           | Year fraction with basis 0 (US 30/360)                                       |
| `ExcelYearFrac` startDate endDate basis   | `DATE → DATE → NUMBER → EITHER STRING NUMBER`  | Basis 0-4: US 30/360, actual/actual, actual/360, actual/365, European 30/360 |

## Month arithmetic

| Function                        | Signature                            | Description                                                                           |
| ------------------------------- | ------------------------------------ | ------------------------------------------------------------------------------------- |
| `ExcelEDate` startDate months   | `DATE → NUMBER → EITHER STRING DATE` | Same day N months later/earlier, clamped to the target month's length (Excel `EDATE`) |
| `ExcelEOMonth` startDate months | `DATE → NUMBER → EITHER STRING DATE` | Last day of the month N months away (Excel `EOMONTH`)                                 |

## Working days

| Function                                      | Signature                                           | Description                                                     |
| --------------------------------------------- | --------------------------------------------------- | --------------------------------------------------------------- |
| `ExcelWorkday` startDate days                 | `DATE → NUMBER → EITHER STRING DATE`                | Date N working days away, skipping weekends (Excel `WORKDAY`)   |
| `ExcelWorkday` startDate days holidays        | `DATE → NUMBER → LIST OF DATE → EITHER STRING DATE` | Same, also skipping the listed holidays                         |
| `ExcelNetworkDays` startDate endDate          | `DATE → DATE → EITHER STRING NUMBER`                | Working days between two dates, inclusive (Excel `NETWORKDAYS`) |
| `ExcelNetworkDays` startDate endDate holidays | `DATE → DATE → LIST OF DATE → EITHER STRING NUMBER` | Same, also excluding the listed holidays                        |

## Utilities

| Function                  | Signature                                | Description                                      |
| ------------------------- | ---------------------------------------- | ------------------------------------------------ |
| `ensureWhole` label value | `STRING → NUMBER → EITHER STRING NUMBER` | RIGHT if the value is an integer, LEFT otherwise |
| `absoluteValue` value     | `NUMBER → NUMBER`                        | Absolute value                                   |
| `containsDay` day days    | `NUMBER → LIST OF NUMBER → BOOLEAN`      | Membership test on day serials                   |
| `dayOfYear` date          | `DATE → NUMBER`                          | 1-based day of the year                          |
