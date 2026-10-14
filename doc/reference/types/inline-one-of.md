# A field's options, listed inline

Some facts can only take one of a short, fixed list of answers.
How someone holds a plot of land is one of them: they own it, they rent it as a tenant, or they live there as a lodger.
L4 lets you write that list directly on the field it belongs to:

```l4
DECLARE Plot HAS
    `the occupier` IS A STRING
    `tenure`       IS ONE OF Owner, Tenant, Lodger
```

This reads exactly like the longer form you may already know, where the list is declared first as a type of its own and the field then names it:

```l4
DECLARE Tenure IS ONE OF Owner, Tenant, Lodger

DECLARE Plot HAS
    `the occupier` IS A STRING
    `tenure`       IS A Tenure
```

Both say the same thing about a plot.
The inline form keeps the options next to the field that uses them, so a reader sees the whole record in one place.

**Example file:** [inline-one-of-example.l4](inline-one-of-example.l4)

## Writing it

`ONE OF` comes straight after the field's `IS`, with no `A` or `AN` in between.
The options are written exactly as they are after `DECLARE … IS ONE OF`.

On one line, separate the options with commas:

```l4
DECLARE Plot HAS
    `tenure` IS ONE OF Owner, Tenant, Lodger
```

On several lines, put each option on a line of its own, indented under the field:

```l4
DECLARE Plot HAS
    `boundary` IS ONE OF
        Fenced
        Hedged
        Open
```

A comma that is followed by a field name and `IS` starts the next field rather than adding an option.
So this record has two fields, `tenure` and `area`, and `tenure` has three options:

```l4
DECLARE Plot HAS tenure IS ONE OF Owner, Tenant, Lodger, area IS A NUMBER
```

That works because an option is never followed by `IS`, and a field name always is.

**A default.**
`TYPICALLY` works as it does on any field.
On one line it goes after the last option; after a list on several lines, put it on a line of its own:

```l4
DECLARE Plot HAS
    `tenure`   IS ONE OF Owner, Tenant, Lodger TYPICALLY Owner
    `boundary` IS ONE OF
        Fenced
        Hedged
        Open
      TYPICALLY Fenced
```

**Options that carry facts of their own.**
An option may have fields, exactly as in a `DECLARE`:

```l4
DECLARE Title HAS
    `estate` IS ONE OF
        Absolute
        Leasehold HAS
            `remaining years` IS A NUMBER
        Possessory
```

**Wording for the natural-language output.**
An `@nlg` written on an option's line belongs to that option, and a `@desc` above the field describes the field, as anywhere else.

## The name L4 gives the list

Every type in L4 has a name, and the list of options is a type.
When you write the options inline, L4 names that type for you, after the place where you wrote it: the record's name, `'s`, and the field's name.
The options of `tenure` in a `Plot` are the type `` `Plot's tenure` ``.

For a field of an option, the name has three parts: the type, the option and the field.
In `DECLARE Holding IS ONE OF Freehold, Lease HAS term IS ONE OF Short, Long`, the options of `term` are `` `Holding's Lease's term` ``.
The type's name is included because two different types may both have an option called `Lease`.

The parts are used exactly as you wrote them.
L4 does not drop a leading "the", and does not make anything plural, so a field called `` `the kind` `` in a record called `Matter` gives `` `Matter's the kind` ``.
That is not pretty, but you can always work out the name from the field.

### Where you will meet the name

You will see the generated name wherever L4 has to name the type rather than show its options:

- **In error messages.** Writing `Plot WITH tenure IS "owner"` is refused with a message that the input `tenure` "is expected to be of type `` `Plot's tenure` `` but is here of type STRING".
- **In the REPL**, when you ask for the type of a plot's tenure with `:type`.
- **In what `l4 batch` and the REPL work from.** Both check your file and then work from a version of it that L4 writes back out, and in that version the list is a `DECLARE` of its own, named `` `Plot's tenure` ``, with the field naming it. It means exactly what you wrote.
- **In exports that need a name for every type.** The Decision Model and Notation (DMN) export calls it `Plot_s_tenure` (labelled "Plot's tenure"), the Catala export `PlotSTenure`, and the Blawx export `plot_s_tenure`. The docassemble export asks the question for the field and never shows the type's name.

You will not see it in two places, on purpose.
`l4 render` lists the options under the field ("tenure — one of Owner, Tenant, or Lodger") and does not show the generated name as a defined term.
And when a rule is published as a service, the list of facts the service asks for (its **schema**) gives the field its options directly and does not publish the generated name.

### Naming the type from a rule

A rule can take the options themselves as an input, by naming the generated type:

```l4
GIVEN t IS A `Plot's tenure`
GIVETH A STRING
`description of` t MEANS
  CONSIDER t
  WHEN Owner  THEN "the owner lives there"
  WHEN Tenant THEN "it is let to a tenant"
  WHEN Lodger THEN "a lodger lives there"
```

The backticks are needed, because the name has a space and an apostrophe in it.
If the record is declared in a section, the type is declared in the same section, and from another section you name it with the section's name in front, as for any type: `` `Plots`.`Plot's tenure` ``.

**Once a second place needs the type, give it a name of your own.**
If a rule names the options, or someone will read the type's name in an error message or an export, declare the list with `DECLARE` and a name you choose, and make the field `IS A` that name.
A name you chose reads better than one L4 made up, and it does not change if you rename the record or the field.
The inline form is best for a list that only its one field uses.

### When the name is already taken

If something else as close to the field already has the generated name, for example a `` DECLARE `Plot's tenure` `` that you wrote yourself, L4 reports it at the field, names the type it was going to make, and says where the other one is declared.
Rename one of them, or declare the options yourself under a name you choose.

## Limits

- **Only as the whole type of a field.** `ONE OF` can list the options of a record's field, or of a field of an option. It cannot be part of a field's type, so `IS A LIST OF ONE OF …` and `IS A MAYBE ONE OF …` are refused; declare the options first and write `LIST OF Tenure`.
- **Not for a rule's inputs or result.** `GIVEN tenure IS ONE OF …`, a `GIVETH`, and an `ASSUME` are refused; declare the options with `DECLARE` and write `IS A Tenure`.
- **One level deep.** A field of one of a field's inline options cannot list options of its own. Declare the inner options with `DECLARE`.
- **Not in a record that takes a type as an input**, such as `DECLARE Box a HAS …`. The type L4 makes for the options would need that input too.
- **On one line, an option with fields takes the rest of the line.** In `estate IS ONE OF Absolute, Leasehold HAS years IS A NUMBER, area IS A NUMBER`, `area` is a second field of `Leasehold`, not the next field of the record. Use several lines when an option has fields.

Each of these is refused with a message that says which rule was broken and what to write instead.

## See also

- [DECLARE](DECLARE.md) — declaring records and lists of options as types of their own
- [TYPICALLY](TYPICALLY.md) — defaults
- [Field opening](../syntax/field-opening.md) — reading a record's fields by name inside a rule
