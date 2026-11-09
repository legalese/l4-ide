# timezone

Constants that give the IANA name of common time zones, for `TIMEZONE IS` lines and the [datetime](datetime.md) constructors. Import it with `IMPORT timezone`.

**Example:** [timezone-example.l4](timezone-example.l4)

## Setting the document time zone

```l4
IMPORT timezone

TIMEZONE IS SGT
```

sets the document's time zone to `"Asia/Singapore"`. Without the library, write the IANA name itself:

```l4
TIMEZONE IS "Asia/Singapore"
```

## Constants

Each constant is a STRING.

| Constant   | IANA name           |
| ---------- | ------------------- |
| EST, EDT   | America/New_York    |
| CST, CDT   | America/Chicago     |
| MST, MDT   | America/Denver      |
| PST, PDT   | America/Los_Angeles |
| GMT, BST   | Europe/London       |
| CET, CEST  | Europe/Berlin       |
| EET, EEST  | Europe/Helsinki     |
| IST        | Asia/Kolkata        |
| SGT        | Asia/Singapore      |
| HKT        | Asia/Hong_Kong      |
| JST        | Asia/Tokyo          |
| KST        | Asia/Seoul          |
| AEST, AEDT | Australia/Sydney    |
| NZST, NZDT | Pacific/Auckland    |
| UTC        | Etc/UTC             |

## Daylight saving time

The standard and the daylight-saving abbreviation of a zone give the same IANA name, so `EST` and `EDT` are both `"America/New_York"`. Whether daylight saving applies is worked out from the date, not from the abbreviation you chose.

```l4
IMPORT timezone

#ASSERT EST EQUALS EDT
```
