# Deploy a project that has folders

> _Status (2026-10-26): **proposed, not landed.**
> This page describes what the `l4 deploy` command and the VS Code **Deploy** button do in draft pull request [legalese/l4-ide#749](https://github.com/legalese/l4-ide/pull/749).
> That pull request is open and not merged.
> It becomes true when #749 merges and a release carries it, and when the service you deploy to is a build that contains the service change in the same pull request (see [If the service is too old](#if-the-service-is-too-old)).
> Until then, `l4 deploy` and the **Deploy** button send every file under its plain file name and keep no folders.
> Every message from `l4` on this page was copied from a run of an `l4` whose code is the code of commit `8c6759479` of that pull request, on macOS.
> Nothing was run on Windows, and the VS Code extension was not opened.
> [How this page was checked](#how-this-page-was-checked) says what was run and what was only read.
> When the draft pull requests #748 or #751 (see [What does not work yet](#what-does-not-work-yet)) land, that list and cases 2 and 4 below need rewriting._

When you **deploy** a rule, you put a copy of it on a server, so that other programs and AI agents can ask it questions.
`l4 deploy` and the VS Code **Deploy** button do this the same way.
They pack files into one upload, a single file called a **zip file** (the kind you may have attached to an email), and send it.
The service on the server unpacks it, reads the rules, and starts answering.

The upload holds the file you deploy and the files it imports, directly or through other files.
It holds nothing else.
Your other rules and your notes are not sent, and neither are the standard libraries (`prelude`, `daydate` and the others), which the service already has built in.

This page is for the moment you split a project into folders.
It answers three questions: which files are sent, what they are called in the upload, and what stops `l4` from sending them.

In short:

- The upload keeps your folders.
  A file is named by its path below the folder that all the sent files share, with `/` between the parts, so files that all sit in one folder get plain names.
- The service looks for an imported file in two places only: beside the file that imports it, and at the top of the upload.
  Before it sends anything, `l4` checks that every imported file is in one of those two places, and refuses when one is not.
- So a file that two rules in different folders both need goes in the top folder of the project, and not in a folder of its own.
  A rule cannot import a file that sits in another rule's folder.
- When `l4` refuses, nothing has been sent, so nothing has changed on the service.
- `l4 deploy` takes one file.
  A project with two rules to publish is two commands and two deployments, each with its own address.
- The service has to be new enough.
  If it is not, a deploy can say it worked and every call can then fail.

---

## Before you start

Read this part before you build any folders.
It collects what a first-time reader of this page most often gets wrong.

### What this build cannot do

For each of these there is nothing to type: the feature is not in the build this page describes.

- **A file in one folder cannot import a file in another folder.**
  The way round is to move the shared file to the top folder of the project, which both can reach.
  [Step 2](#step-2-move-the-shared-figure-to-the-top) does that, and [When one rule needs a file from the other rule's folder](#when-one-rule-needs-a-file-from-the-other-rules-folder) shows what `l4` says if you try.
- **An `IMPORT` cannot take a path** such as `` `../terms` ``, and **cannot start from the top folder** with a name such as `` `/terms` ``.
  Two draft pull requests ([#748](https://github.com/legalese/l4-ide/pull/748) and [#751](https://github.com/legalese/l4-ide/pull/751)) propose them.
  This build reads a name with a slash in it, written between backticks, as its last part alone, and says nothing: see [What does not work yet](#what-does-not-work-yet).
- **There are no aliases.**
  In the draft pull request that proposes them (#751), an alias is a short name for a folder.
  `IMPORT rates AS r` is not an alias: this build stops at it with `unexpected AS`.

### Three rules for the folders

1. **A file that two rules share goes in the top folder**, the folder that holds the rule folders.
   Do not put it in a folder of its own, whatever you call that folder (`common`, `shared`, `lib`): the service does not look there, and [case 2](#2-a-shared-file-in-a-folder-where-the-service-does-not-look) is what `l4` says when you do.
2. **A file that only one rule uses goes beside that rule.**
   Giving each rule its own folder, as Alex does below, is a choice and not a requirement.
   The only requirement is where an imported file sits: beside the file that imports it, or in the top folder.
3. **Name the folders that hold imported files with only the letters A to Z (no accents), digits, `.`, `-` and `_`.**
   A folder called `late fees`, with a space, or `Fristen (2024)`, with brackets, is refused ([case 3](#3-a-folder-name-the-service-cannot-read)).
   The name of the top folder itself is not judged: a project kept in a folder called `Smith v Jones (2024)` deployed without complaint.

### Telling whether your tools have the change

This page is about a change that has not landed, so the first thing to know is whether the `l4` on your computer has it.
`l4 --version` cannot tell you: the build this page was checked with and an older build made from `unstable` both print `dev`.
The "Deploying" line can.
With the project of [Step 2](#step-2-move-the-shared-figure-to-the-top), an `l4` that has the change prints `fees/late-fee.l4, fees/rates.l4, terms.l4`, with the folder.
An `l4` made from `unstable` before this pull request printed `late-fee.l4, rates.l4, terms.l4`, with no folder, when it was run with `JL4_LIBRARY_PATH` set, as in Step 2; without the setting it stops at `terms`, as Step 2 shows.
The service you deploy to is a separate question, and [If the service is too old](#if-the-service-is-too-old) has a test that needs nobody's answer.

### Windows

Nothing on this page was run on Windows.
[Windows](#windows) says what was only read, and [Step 2](#step-2-move-the-shared-figure-to-the-top) gives the PowerShell and Command Prompt lines for setting the one setting this page needs, marked as not tried with `l4`.

---

## An example: two rules, two folders

Alex runs a small supply business and has written two rules.
One works out the fee for a late invoice.
The other works out the last day a customer can pay without a fee.
Each rule has its own folder, with a helper file beside it.
Both rules quote the same grace period, 14 days, so Alex also keeps a file at the top, `terms.l4`, for figures the rules share.
Nothing imports it yet; Step 2 below makes use of it.

```
folders-example/
  terms.l4
  fees/
    late-fee.l4
    rates.l4
  deadlines/
    payment-deadline.l4
    grace.l4
```

The five files are printed in full below.
To follow along, save each one under the name in its first line, in the folders shown above.
The same files are in the documentation source, in a folder called `folders-example` beside this page, one link each: [terms.l4](folders-example/terms.l4), [fees/late-fee.l4](folders-example/fees/late-fee.l4), [fees/rates.l4](folders-example/fees/rates.l4), [deadlines/payment-deadline.l4](folders-example/deadlines/payment-deadline.l4) and [deadlines/grace.l4](folders-example/deadlines/grace.l4).

Here are the two files of the `fees` rule.
`IMPORT rates` is how `late-fee.l4` says "also read `rates.l4`, which sits beside me"; you write the name without `.l4`.

```l4
-- late-fee.l4: the late fee on an overdue invoice (the file to deploy).
IMPORT rates

@export default What late fee does a customer owe on an overdue invoice?
GIVEN `invoice amount` IS A NUMBER @desc The amount of the invoice
      `days overdue`   IS A NUMBER @desc How many days the invoice has been unpaid after its due date
GIVETH A NUMBER
DECIDE `late fee` IS
    IF `days overdue` <= `the grace period in days`
    THEN 0
    ELSE `the flat fee` + `invoice amount` * `the monthly late rate`

#EVAL `late fee` 1000 20
```

```l4
-- rates.l4: what a late invoice costs, kept beside late-fee.l4.
`the grace period in days` MEANS 14
`the flat fee` MEANS 25
`the monthly late rate` MEANS 0.015
```

The `deadlines` folder has the same shape.
`payment-deadline.l4` is the file to deploy, and imports `grace.l4`:

```l4
-- payment-deadline.l4: the last day a customer can pay without a late fee (the file to deploy).
IMPORT grace

@export default How many days after the due date can a customer pay without a late fee?
GIVEN `asked for extra days` IS A BOOLEAN @desc Whether the customer asked for the courtesy days
GIVETH A NUMBER
DECIDE `last free day` IS
    IF `asked for extra days`
    THEN `the grace period in days` + `courtesy days`
    ELSE `the grace period in days`

#EVAL `last free day` TRUE
```

```l4
-- grace.l4: how long a customer has to pay, kept beside payment-deadline.l4.
`the grace period in days` MEANS 14
`courtesy days` MEANS 3
```

Last, the file at the top.
`terms.l4` holds one definition, the figure that `rates.l4` and `grace.l4` both write out for themselves:

```l4
-- terms.l4: the one figure that both rules in this project share.
`the grace period in days` MEANS 14
```

---

## Step 1: Deploy a rule whose files sit in one folder

Open a terminal in the `folders-example` folder and run:

```bash
l4 deploy fees/late-fee.l4
```

(Sign in first if you have not; [Using the l4 CLI](../getting-started/l4-cli.md#sign-in) shows how.)

Just before it sends the files, `l4` prints one line that names everything it is about to send.
This is that line, from a run against a stand-in server that only records what it is sent (see [How this page was checked](#how-this-page-was-checked)):

```
Deploying 'late-fee' to http://127.0.0.1:18765: late-fee.l4, rates.l4
```

On Legalese Cloud, the words between `to` and the colon name your organization instead, as in [Using the l4 CLI](../getting-started/l4-cli.md#deploy-update-list-remove).
The names after the colon are what matter here.

Three things to read in that line.

First, only two files were sent.
`late-fee.l4` imports `rates.l4`, so both go.
`terms.l4` and the whole `deadlines` folder stay behind, because nothing in this rule imports them.

Second, the names are plain: `late-fee.l4`, not `fees/late-fee.l4`.
A file is named by its path below the folder that all the sent files share.
Both files sit in `fees`, so `fees` is the shared folder and does not appear in the names.
This page calls that shared folder **the top of the upload**.
It is the folder the service looks in for a file that is not beside its importer.

Third, you did not have to tell `l4` where `rates.l4` is.
`l4` looks for an imported file beside the file that imports it, and here it is.

Deploying the other rule the same way, with `l4 deploy deadlines/payment-deadline.l4`, sends `payment-deadline.l4` and `grace.l4`.
That is a second command, and a second deployment with its own address: `l4 deploy` deploys one file, plus what it imports.
`l4 deploy deadlines`, with a folder in place of a file, is not accepted; `l4` says `No such file: deadlines`.

---

## Step 2: Move the shared figure to the top

Alex notices that `the grace period in days` is written out twice, once in each folder.
If it ever changes, it has to change in two places.
So Alex keeps it in `terms.l4` at the top, and makes both helper files import it.

Replace `fees/rates.l4` with:

```l4
-- rates.l4: what a late invoice costs, kept beside late-fee.l4.
IMPORT terms

`the flat fee` MEANS 25
`the monthly late rate` MEANS 0.015
```

Replace `deadlines/grace.l4` with:

```l4
-- grace.l4: how long a customer has to pay, kept beside payment-deadline.l4.
IMPORT terms

`courtesy days` MEANS 3
```

`late-fee.l4` and `payment-deadline.l4` do not change.
A name that `rates.l4` gets from `terms.l4` is also available in `late-fee.l4`, which imports `rates.l4`, so `late-fee.l4` does not need its own `IMPORT terms`.
It may have one: with both `IMPORT rates` and `IMPORT terms`, the upload is the same.

Now run the same command again:

```bash
l4 deploy fees/late-fee.l4
```

It fails, and the failure is worth seeing once.
Among the messages, `l4` prints:

```
I could not find a module with this name: terms
```

and it ends with:

```
fees/late-fee.l4 doesn't typecheck; fix it before deploying (see `l4 check`).
```

(The full message also lists every place `l4` looked.)
That last line means `l4` could not check your rules, so it stopped before sending them.

Step 1 worked without any help because `rates.l4` sat beside `late-fee.l4`.
Now `terms.l4` does not sit beside `rates.l4`: it sits in the top folder.
`l4` looks for an imported file beside the files it is reading, in its own built-in libraries, and in a per-user library folder.
It does not look in the top folder of your project unless you tell it to.
You tell it with an **environment variable**, a named setting that your terminal hands to the programs it starts.
This one is called `JL4_LIBRARY_PATH`; [Step 5 of the l4 guide](../getting-started/l4-cli.md#step-5-libraries-and-jl4_library_path) explains it.
Set it to the **full path** of the top folder, here `folders-example`: the whole address of the folder, starting from the top of the disk, such as `/Users/you/folders-example`.

On macOS and Linux you write it in front of the command, and it applies to that one command:

```bash
JL4_LIBRARY_PATH=$PWD l4 deploy fees/late-fee.l4
```

(`$PWD` is the full path of the folder you are in.)
A path that is not a full path, such as `JL4_LIBRARY_PATH=.`, stops with a message that names the file and not the setting; see [case 6](#6-a-setting-that-is-not-a-full-path).

On Windows, nothing here was run, so this is only how each terminal sets a setting for the window you are typing in, written for a project in `C:\Users\you\folders-example`.
These lines are not tried with `l4`.
In PowerShell:

```
$env:JL4_LIBRARY_PATH = "C:\Users\you\folders-example"
```

In Command Prompt (no quotation marks, even when the path has spaces):

```
set JL4_LIBRARY_PATH=C:\Users\you\folders-example
```

Either setting lasts until you close that window.
**Do not set it in Windows' system settings, or in a startup file on macOS or Linux, so that it applies to everything.**
While it is set, `l4` stops reading the standard libraries from the copy built into it, so `l4 check` and `l4 run` of any file that says `IMPORT prelude` fail with `I could not find a module with this name: prelude`.
A setting made for the whole account would do that to every project you work on.
`l4 deploy` has no option that does the same job: its options are `--name`, `--description`, `--no-wait`, `--json`, `--server` and `--api-key-file`.
How to type the file name after it on Windows (`fees/late-fee.l4` or `fees\late-fee.l4`) was not tried either.

Now the line that `l4` prints is:

```
Deploying 'late-fee' to http://127.0.0.1:18765: fees/late-fee.l4, fees/rates.l4, terms.l4
```

The files are now in two places: `fees`, and the top folder.
So the folder they all share, the top of the upload, is the top folder `folders-example`, and `fees` appears in the names.
The folder is kept.

The other rule, `JL4_LIBRARY_PATH=$PWD l4 deploy deadlines/payment-deadline.l4`, prints:

```
Deploying 'payment-deadline' to http://127.0.0.1:18765: deadlines/payment-deadline.l4, deadlines/grace.l4, terms.l4
```

The two uploads share `terms.l4` and nothing else.
The `deadlines` folder is not in the first upload, and the `fees` folder is not in the second.
That is two deployments: you ran the command twice, so the service has two rules, `late-fee` and `payment-deadline`, with two addresses.

Run these commands from the top folder, `folders-example`.
You can also run them from the folder above it, writing `folders-example/fees/late-fee.l4`.
The setting must then still name `folders-example`: `JL4_LIBRARY_PATH=$PWD/folders-example`.
With `JL4_LIBRARY_PATH=$PWD` there, `$PWD` is the folder above, which does not hold `terms.l4`, and `l4` stops with `I could not find a module with this name: terms`.
The other projects in the folder above are not sent, unless a file you deploy imports them.
Running them from inside `fees` is refused (see [below](#1-a-file-outside-the-project-folder)).

---

## Step 3: Call each rule once

Whatever the "Deployed" line says, call each rule once and read the answer.
[Why that matters](#if-the-service-is-too-old) is further down: a deploy can say it worked and every call can then fail.

A call is a request sent to the rule's address.
`curl` is a program that sends a request to a web address and prints the answer.
The part after `-d` is the rule's inputs, written in JavaScript Object Notation (JSON), a plain-text way of writing a list of named values.
This is the call for the `fees` rule, in the form [Deploy your rules](exporting-rules-for-deployment.md#step-5-call-a-rule) shows for Legalese Cloud, where `{orgSlug}` is your organization and `sk_...` is your key:

```bash
curl -X POST https://api.legalese.cloud/{orgSlug}/late-fee/functions/late-fee/evaluation \
  -H "Authorization: Bearer sk_..." \
  -H "Content-Type: application/json" \
  -d '{"arguments": {"invoice-amount": 1000, "days-overdue": 20}}'
```

In the address and the inputs, the spaces in a name become hyphens: the rule `late fee` is `late-fee`, and the input `invoice amount` is `invoice-amount`.
The answer is the same as the `#EVAL` in `late-fee.l4` gives, 40:

```
{"contents":{"presumed":[],"result":{"value":40}},"report":"default","tag":"SimpleResponse"}
```

The call for the `deadlines` rule has the address ending `/payment-deadline/functions/last-free-day/evaluation` and the inputs `{"arguments": {"asked-for-extra-days": true}}`.
Its answer has the value 17, as its `#EVAL` gives.

Both answers above came from a service run on the same computer, which asked for no key.
For a service like that, the address is the `API:` line that `l4` printed with `/functions/late-fee/evaluation` added: `http://127.0.0.1:18880/deployments/late-fee/functions/late-fee/evaluation`, where `18880` is the port that service listened on.
How to send such a call from a Windows terminal was not tried.

---

## Check without sending

You may not want to touch a real service while you are still arranging folders.
You can ask `l4` whether it would accept your files, without sending anything, by giving `--server` an address where nothing listens.
`http://127.0.0.1:9` is such an address on most computers: it is your own machine, on a port that nothing normally uses.

```bash
JL4_LIBRARY_PATH=$PWD l4 deploy fees/late-fee.l4 --server http://127.0.0.1:9
```

If `l4` would accept the files, it goes on to try that address and says it cannot reach it:

```
Could not reach http://127.0.0.1:9: ConnectionFailure Network.Socket.connect: <socket: 3>: does not exist (Connection refused)
```

That message means no file was refused.
(Those are the words after the address on macOS; they may differ on your computer.)
If something is wrong with the files, you get one of the messages in the next section instead.
The exit status is 1 either way.

This check does not list the names.
`l4` prints that list only when it is about to send, and it has no "dry run" switch yet.
The check also cannot tell you whether the service will in fact find your files; the next sections explain what `l4` checks on that.
And it can pass while `l4 check` on the same files is red: see [What does not work yet](#what-does-not-work-yet).

---

## Splitting a file of your own into folders

This page cannot tell you which parts of your own file belong where, but it can tell you what is allowed to move.
Each point below was tried in a small test project made for the purpose and not shipped here (see [How this page was checked](#how-this-page-was-checked)).

- **A named figure, a kind of thing and a rule with inputs can all live in an imported file.**
  A name defined with `MEANS`, a `DECLARE` (a new kind of thing, such as an `Invoice` with its fields) and a rule with a `GIVEN` input and a `DECIDE` were all usable from the file that imported `terms.l4`, with `l4 run`, and after a deploy, in a call.
- **A `#EVAL` line in an imported file does not run.**
  Running the file that imports it printed one result, the importer's own.
  Keep the `#EVAL` lines that check a rule in the file you run.
- **An `@export` in an imported file is published too.**
  When `terms.l4` had an `@export` on a rule, the deployment of the file that imported it said "with 2 functions", and the second rule answered a call.
  Put `@export` only on rules you mean to publish, and think of an imported file with an `@export` as part of what you publish.
- **Move one thing at a time.**
  After each move, run `l4 check` on the file you will deploy.
  A figure that two rules use goes to the top folder; a figure that one rule uses goes beside it.
- **Two files with the same name in different folders stay apart.**
  When a second `rates.l4`, with a flat fee of 99, also sat in the `deadlines` folder, `l4 deploy fees/late-fee.l4` used `fees/rates.l4`, left the other out of the upload, and the rule answered 40.
  A file with that name at the top is another matter: see [case 4](#4-two-files-with-one-name).
- **Write the name in `IMPORT` with the capitals of the file's name.**
  `IMPORT Rates` also worked here, and the upload then held the file as `fees/Rates.l4`, because the disk of this Mac ignores capitals.
  On a system that tells capitals apart, `l4` may report that it cannot find the module `Rates` and stop before sending; that was not tried.

---

## When one rule needs a file from the other rule's folder

Suppose `deadlines/payment-deadline.l4` needs `the flat fee` from `fees/rates.l4`, and says `IMPORT rates`.
It cannot be done by importing across the folders.
This was run in a small project of `fees/rates.l4`, `fees/late-fee.l4` and `deadlines/payment-deadline.l4`.

With no setting, `l4` looks beside `payment-deadline.l4`, finds no `rates.l4`, and stops with:

```
I could not find a module with this name: rates
```

With `JL4_LIBRARY_PATH` set to the `fees` folder, `l4` does find it, and then stops before sending, because the service would not:

```
The deployed service would not find a library this file imports:
  deadlines/payment-deadline.l4 imports rates, which would be uploaded as fees/rates.l4 (from …/fees/rates.l4), in the folder fees
```

That is [case 2](#2-a-shared-file-in-a-folder-where-the-service-does-not-look) below, and so is the fix: move `rates.l4` to the top folder, point `JL4_LIBRARY_PATH` at the top folder, and let both rules say `IMPORT rates`, as Step 2 does for `terms.l4`.

Writing the path does not help.
A slash in an `IMPORT` name without quotation marks is an error, `unexpected /`.
With quotation marks it is not an error, and is not a folder either; see [What does not work yet](#what-does-not-work-yet).

---

## How the service finds a file by name

When a file says `IMPORT rates`, the service looks for `rates.l4` in two places, and only these two:

1. beside the file that says it, which means the same folder in the upload;
2. at the top of the upload.

It does not look in any other folder, even one that is in the upload.
It has the files you sent and the standard libraries built into it, and nothing from the machine it runs on.

`l4` reads imports more widely.
It also looks in `JL4_LIBRARY_PATH` and in the per-user library folder.
A library found there is not on the service.
That is why `l4` checks, before it sends, that every imported file will end up in one of the two places the service looks, and refuses when one will not.

With imports written by name, as on this page, this has a consequence.
An upload can hold the folder of the file you deploy and the top of the upload, and no other folder.

---

## What stops a deploy

Each of these stops `l4 deploy` before it sends anything.
They were all run with `--server http://127.0.0.1:9`, as in the last section, so nothing could be sent.
In the messages, the long name of the folder where the project lived during the check is shortened to `…`; `l4` prints the whole path.
A `…` at the end of a line, or on a line of its own, marks a part of a long message that is left out here.

To find your message, look at its first line:

- `This file lies outside the project folder …` is [case 1](#1-a-file-outside-the-project-folder).
- `The deployed service would not find a library this file imports:` is [case 2](#2-a-shared-file-in-a-folder-where-the-service-does-not-look).
- `The deployed service may not find a file that is imported, because of the name of the folder it is in:` is [case 3](#3-a-folder-name-the-service-cannot-read).
- `Cannot upload file://…: its file path … is not absolute.` is [case 6](#6-a-setting-that-is-not-a-full-path).
- A file that cannot be read, with `permission denied` in a long message that ends `doesn't typecheck`, is [case 5](#5-a-file-that-cannot-be-read).
- `I could not find a module with this name: …`, and a last line that ends `doesn't typecheck; fix it before deploying`, is not one of these refusals.
  `l4` could not check your rules, usually because `JL4_LIBRARY_PATH` is not set to the top folder or does not name it in full; Step 2 shows one.
  Read the first message in the long text above that last line.
- `Could not reach …` means no file was refused; see [Check without sending](#check-without-sending).
- No message at all, and the wrong file in the upload, is [case 4](#4-two-files-with-one-name).

### 1. A file outside the project folder

The **project folder** is `l4`'s word for the folder you run it from, as long as the file you are deploying is inside it (otherwise it is that file's own folder, and it is never the very top of a drive).
In the examples on this page that is the top folder.
Any file that would be sent from outside the project folder stops the deploy.

The most common cause is running `l4` from inside a subfolder:

```bash
cd fees
JL4_LIBRARY_PATH=/path/to/folders-example l4 deploy late-fee.l4 --server http://127.0.0.1:9
```

```
This file lies outside the project folder …/folders-example/fees, so it cannot be uploaded:
  …/folders-example/terms.l4
The project folder is the folder l4 was run from when the file being deployed is inside it and that folder is not the top of a drive; otherwise it is the file's own folder.
To deploy a library that lives elsewhere, put it inside the project folder, beside the file that imports it.
A deployed service reads only the files that are uploaded.
It does not read JL4_LIBRARY_PATH or the per-user library folder (jl4/libraries in $XDG_DATA_HOME, or in ~/.local/share), where l4 may have found a library.
l4 reads a library from JL4_LIBRARY_PATH before it reads one beside the importing file, so with that variable set a copy in the project is not used: unset the variable, or move the file instead of copying it.
A library from the per-user library folder is read after the one beside the importing file, so a copy there is enough.
JL4_LIBRARY_PATH is set, so l4 reads the standard library from files on disk instead of the copy built into l4.
A standard library file that is exactly the copy built into l4 is left out of the upload and stops nothing, so a file listed above is not a standard library file, or differs from the built-in copy.
If one of those files is a standard library file, unset JL4_LIBRARY_PATH and try again: the deployed service has the standard library built in and does not need it uploaded.
```

**The fix** for this cause: go back up to the top folder (`cd ..`) and run the command from there.
The advice in the message, "put it inside the project folder", fits the other cause.

The other cause is that the shared file really is kept outside the project, for example in a `common` folder beside `folders-example`, with `JL4_LIBRARY_PATH` naming `common`.
The message is the same and names that file (`…/common/terms.l4`).
**The fix** is to move the file into the project, to the top folder, and to point `JL4_LIBRARY_PATH` at the top folder.
Move it; do not copy it.
`l4` reads `JL4_LIBRARY_PATH` first, so while the variable names the old folder, a copy inside the project is ignored.

### 2. A shared file in a folder where the service does not look

Suppose Alex tidies `terms.l4` into a folder called `shared`, and points `JL4_LIBRARY_PATH` at `shared`:

```bash
JL4_LIBRARY_PATH=$PWD/shared l4 deploy fees/late-fee.l4 --server http://127.0.0.1:9
```

```
The deployed service would not find a library this file imports:
  fees/rates.l4 imports terms, which would be uploaded as shared/terms.l4 (from …/folders-example/shared/terms.l4), in the folder shared
The deployed service looks an IMPORT up only beside the file that imports it and at the top of the upload (the folder that holds all the uploaded files).
It looks nowhere else, so the deploy would say it is ready and every call would then fail.
Put each library beside the file that imports it, and deploy again.
…
```

`shared` is neither the folder of `fees/rates.l4` nor the top, so the service would not find the file.
**The fix:** move `terms.l4` to the top of the project and point `JL4_LIBRARY_PATH` at the top folder, as in Step 2.
The message says "beside the file that imports it".
For a file that two rules share, the top of the project is the place that works for both, and the service looks there too.

### 3. A folder name the service cannot read

Suppose Alex names the folder `late fees`, with a space:

```bash
JL4_LIBRARY_PATH=$PWD l4 deploy "late fees/late-fee.l4" --server http://127.0.0.1:9
```

```
The deployed service may not find a file that is imported, because of the name of the folder it is in:
  late fees/rates.l4 (from …/folders-example/late fees/rates.l4), in the folder late fees
The deployed service does not find a file beside the file that imports it when the first folder of the file's path in the upload has a space, a letter outside A to Z, or one of # ' + ( ) % , = @ & ! $ ; [ ] in its name.
The deploy would say it is ready, and every call would then fail.
l4 stops at any character other than a letter from A to Z, a digit, '.', '-' or '_' in any folder of the path, not only the first, so it also stops a few names the service would find, for example ok/my dir and a~b.
Rename the folder to use only letters, digits, '.', '-' and '_', and deploy again.
```

**The fix** is the last line of the message: rename the folder.
A folder called `frais é`, with an accented letter, is refused in the same way.
Safe folder names use only the letters A to Z (no accents), digits, `.`, `-` and `_`.

Three things to know about this refusal:

- It judges only the folders of files that are imported.
  The folder of the file you deploy is not judged, and neither is a file at the top.
  The name of the top folder itself does not appear in the upload and is not judged either.
- It does not apply when every file sits in one folder.
  If `late fees` held the whole `fees` rule from Step 1 (no `terms.l4`), the upload would be `late-fee.l4, rates.l4`, with no folder in the names, and nothing is refused.
- The reason is a limit of the service, not a rule of L4.
  The message says "may not find" because `l4` stops a few names the service would find.
  The refusal can go when the service is fixed.

### 4. Two files with one name

There is no message for this, because you cannot make it happen by writing `IMPORT` by name.
A name picks one file.
When two files have the same name, `l4` reads the one named by `JL4_LIBRARY_PATH` first, and the other is quietly left out.

Here is what that looks like.
Suppose Alex puts a second `rates.l4`, with other figures, at the top of the project, next to `terms.l4`:

```l4
-- rates.l4: a second file with this name, at the top, with other figures.
IMPORT terms

`the flat fee` MEANS 50
`the monthly late rate` MEANS 0.069
```

and deploys with the variable set:

```bash
JL4_LIBRARY_PATH=$PWD l4 deploy fees/late-fee.l4
```

```
Deploying 'late-fee' to http://127.0.0.1:18765: fees/late-fee.l4, rates.l4, terms.l4
```

The upload holds the top `rates.l4`, not `fees/rates.l4`.
Nothing says so.
`JL4_LIBRARY_PATH=$PWD l4 run fees/late-fee.l4` agrees with the upload: the `#EVAL` in `late-fee.l4` answers 119 with the second file in place (50 plus 1000 times 0.069), and 40 without it.
(Without the setting, `l4 run` of the file stops at `terms`, as in Step 2.)
**The fix:** give each file its own name, or remove the copy you did not mean.

The tool is ready for two files of one name in different folders: it names files by folder, so they would stay apart, and the tool's own tests check that with made-up paths.
Nothing you can write today puts two such files into one upload.

### 5. A file that cannot be read

`l4` reads every file to check it before it packs anything, so a file it cannot read stops the check first.
Here `fees/rates.l4` has been made unreadable (on macOS, `chmod 000 fees/rates.l4`):

```bash
JL4_LIBRARY_PATH=$PWD l4 deploy fees/late-fee.l4 --server http://127.0.0.1:9
```

```
  Message:
    …/folders-example/fees/rates.l4: openFile: permission denied (Permission denied)
…
fees/late-fee.l4 doesn't typecheck; fix it before deploying (see `l4 check`).
```

The last line is the same one you see for any error in your rules.
Further messages between the two lines above complain that names from `rates.l4` are missing, because the file could not be read.
**The fix:** make sure you can open the file, and run the command again.

### 6. A setting that is not a full path

Suppose Alex sets `JL4_LIBRARY_PATH` to `.`, meaning "this folder", in Step 2:

```bash
JL4_LIBRARY_PATH=. l4 deploy fees/late-fee.l4 --server http://127.0.0.1:9
```

```
Cannot upload file://terms.l4: its file path terms.l4 is not absolute.
```

The exit status is 1.
The message names the file `terms.l4`, which is fine; what is wrong is the setting.
**The fix:** write the full path, such as `$PWD`.
A path that ends in `/`, or that goes through a symbolic link (a shortcut to a folder), was not refused.

---

## The VS Code Deploy button

The **Deploy** tab in the VS Code sidebar packs the same upload with the same names, and refuses in some of the same cases.
It checks less.

The checks below come from the compiled code behind the button, run from the command line, not from the extension inside VS Code.
It was given the list of imported files by hand, as the language server would give it.
With the example project's top folder as the workspace folder, it collects:

```
Collected: fees/late-fee.l4
Collected: fees/rates.l4
Collected: terms.l4
```

The project folder here is the workspace folder that holds the file.
The button stops, with an error that names the file, in these cases, among others:

- A file outside the workspace folder.
  With only `fees` as the workspace folder, the message begins: `Deploy stopped: …/folders-example/terms.l4 lies outside the project root …/folders-example/fees.`
- A folder name the service cannot read.
  With the folder `late fees`, the message begins: `Deploy stopped: the deployed service may not find a file that is imported, because of the name of the folder it is in: late fees/rates.l4 (…/folders-example/late fees/rates.l4) is in the folder "late fees".`
  It then gives reasons and a fix like those of the `l4` message above, in slightly different words.
- A file it cannot read.
  The message begins: `Deploy stopped: could not read …/folders-example/fees/rates.l4: EACCES: permission denied, open '…/folders-example/fees/rates.l4'`

It also stops when two files would be stored under one name in the upload, and on a file address it cannot turn into a name.
Those were read in the code and not run.

What the button cannot do is check where a shared file sits.
The editor's language server hands the extension the list of imported files, not the `IMPORT` lines, so the extension cannot tell whether a file is beside its importer or at the top.
A shared file in a third folder, such as `shared` in case 2 above, is sent anyway.
The service then says "ready", and a call that needs the file fails.
Until that is fixed, check the folders by hand, or run `l4 deploy` with `--server http://127.0.0.1:9` first.

Not tested: how the tab displays these messages, and whether the editor's language server finds a `terms.l4` at the top of your workspace folder without help.
The code returns the message to the tab as the reason the deploy failed, and writes it to the L4 Output channel as `[sidebar] Deploy failed: …`.

---

## If the service is too old

The change to the service is part of the same pull request.
A service built before it looks for an imported file from the folder of the first file in the upload (in alphabetical order), not from the top of the upload, so it can miss a file that sits at the top.
A deploy to such a service can go two ways, and `l4` and the **Deploy** button cannot tell you which service you are talking to: neither checks its version.

Both ways turned up with the example project from Step 2, on two services run on the machine where this page was checked.
One was built before the service change (the "old" one) and one with it (the "new" one).

**The old service rejected the `fees` rule at once.**
It could not find `terms.l4`, and the rule then did not make sense without it:

```
Deploying 'late-fee' to http://127.0.0.1:18771: fees/late-fee.l4, fees/rates.l4, terms.l4
Compiling…
Update rejected: compilation failed: I found a problem while checking the definition of `late fee`:   There are multiple definitions for the identifier        `__LEQ__`      and I do not have sufficient information to make a choice between them.   …
```

That is the lucky outcome, because it is loud.

**The old service accepted the `deadlines` rule, and every call to it failed.**

```
Deploying 'payment-deadline' to http://127.0.0.1:18771: deadlines/payment-deadline.l4, deadlines/grace.l4, terms.l4
Compiling…
Deployed 'payment-deadline' (version 0.0.0) with 1 function:
  last free day
API: http://127.0.0.1:18771/deployments/payment-deadline
```

Calling the rule answered with a failure, the status code 422, and this body.
(HTTP, the protocol that programs use to talk to web services, puts a number like this on every answer; 200 means it worked.)

```
{"contents":{"contents":"Internal error:\n  `the grace period in days`\nis not in scope.\nPlease report this as a bug.\n","tag":"InterpreterError"},"report":"default","tag":"Error"}
```

The new service accepted both rules, and the calls answered 40 for the `fees` rule (1000 owed, 20 days overdue) and 17 for the `deadlines` rule (the customer asked for the extra days), with HTTP status 200.

Which of the two outcomes you get depends on how the rule uses what it imports.
Do not count on the loud one.

**A test you can run yourself.**
The `deadlines` rule is the useful one, because the old service accepted it and then failed.
Deploy it from the Step 2 project under a name you will delete, and call it as in [Step 3](#step-3-call-each-rule-once):

```bash
JL4_LIBRARY_PATH=$PWD l4 deploy deadlines/payment-deadline.l4 --name canary-test
```

An answer with the value 17 means the service finds a file at the top of the upload, which is the change.
The status 422 with `is not in scope` means it does not.
Then remove the test deployment with `l4 undeploy canary-test`, which asks you to type the name to confirm.
This page cannot tell you whether Legalese Cloud, or the service your organization runs, is a build that has the change; the test above can.
Whoever runs the service can also tell you: for Legalese Cloud that is Legalese, the company that runs it.

---

## What does not work yet

- **Path imports and the root-relative form do not deploy through these tools.**
  Two other draft pull requests teach `IMPORT` to take a name with a slash ([#748](https://github.com/legalese/l4-ide/pull/748), a path such as `` `../terms` ``) and to start from the project's top folder ([#751](https://github.com/legalese/l4-ide/pull/751), a name starting with `/`, and aliases, which are short names for folders).
  Neither is in the build this page describes, so there is nothing to type for them.
  Here, a slash in an `IMPORT` name is not a folder: `l4` reads the name as its last part only, and says nothing.
  `` IMPORT `/rates` ``, `` IMPORT `@common/rates` `` and `` IMPORT `../fees/rates` `` in `fees/late-fee.l4` were each uploaded exactly as `IMPORT rates` is: `fees/late-fee.l4, fees/rates.l4, terms.l4`.
  Without quotation marks, a slash is an error: `IMPORT fees/rates` gives `unexpected /`.
  A backslash inside quotation marks, as in `` IMPORT `fees\rates` ``, is not a folder separator either: `l4` looked for a module whose whole name was `fees\rates` and did not find one (run on macOS).
  With `` IMPORT `../terms` `` in `fees/rates.l4` and no variable, `l4` says:

  ```
  I could not find a module with this name: terms
  ```

  and with `JL4_LIBRARY_PATH` set to the top folder it deploys exactly as `IMPORT terms` does: `fees/late-fee.l4, fees/rates.l4, terms.l4`.
  So write the name without a slash for now.
  When those pull requests land, this page and the refusals above will need revisiting.

- **A rule you deploy that imports a standard library cannot be checked while `JL4_LIBRARY_PATH` is set.**
  With the variable set, `l4` stops reading the standard libraries from the copy built into it.
  A rule that says `IMPORT prelude` and uses `sum` then fails, and `l4` stops:

  ```
  I could not find a module with this name: prelude
  …
  the stdlib embedded in this binary (skipped: JL4_LIBRARY_PATH is set),
  …
  fees/late-fee.l4 doesn't typecheck; fix it before deploying (see `l4 check`).
  ```

  So a project whose deployed file imports a standard library and also shares a file at the top could not be deployed in the runs for this page.
  The one way round that was tried needs a copy of the standard library file that is exactly the copy built into your `l4`.
  Put that copy at the top of the project.
  `l4` then prints `Not uploaded, the deployed service has it built in: prelude` and leaves it out of the upload.
  The copy used here came from a checkout of the L4 source at the same commit as the `l4`; a copy from another version will differ, and `l4` treats it as one of your own files.
  None of the commands that `l4 --help` lists writes the built-in copy out, so without a checkout of the source this page has no way to give you that copy.
  What does work without a checkout is to keep a rule's files together in one folder, as in Step 1, which needs no variable; the shared figure is then written once in each folder that needs it.

- **`l4 deploy` can send files while `l4 check` on the same files is red.**
  This was measured twice, one run each, and this page has not worked out where the line lies.
  First, a rule said `IMPORT rates` and used no name from it, and no `rates.l4` was where `l4` looks: `l4 check` printed `I could not find a module with this name: rates`, and `l4 deploy` sent the files, and the service accepted them.
  Second, the helper `fees/rates.l4` said `IMPORT prelude` and used `sum`, with `JL4_LIBRARY_PATH` set to the top folder: `l4 check` and `l4 run` of `fees/late-fee.l4` failed with `I could not find a module with this name: prelude`, `l4 deploy` sent the files, and the deployed rule answered 40, the answer it should give.
  Why the service coped in the second run was not looked into.
  Do not rely on it: when `l4 check` is red, treat what `l4 deploy` sent as unchecked.
- **There is no list of names without sending.**
  The "Deploying" line appears only when `l4` is about to send.
  See [Check without sending](#check-without-sending) for what you can do instead.
- **A shared file at the top whose own name has a space or an accented letter is not found by the service, and `l4` does not stop it.**
  The code comments of this build say so, and the pull request says its author measured it.
  That was not measured again for this page.
  Give shared files plain names too.
- **Neither tool checks the version of the service.**
  See [If the service is too old](#if-the-service-is-too-old).
- **The Deploy button cannot check where a shared file sits.**
  See [above](#the-vs-code-deploy-button).

---

## Windows

Nothing on this page was run on Windows.
This is what was read in the code and in other pages.

- **Names in the upload use `/`, on every system.**
  The code that makes them joins the parts with `/` (`jl4/app/L4/Cli/DeployPlan.hs` for `l4`, `ts-apps/vscode/src/deploy-bundle.ts` for the button).
  So the upload holds `fees/late-fee.l4`, never `fees\late-fee.l4`.
  The names were looked at only on macOS.
- **Drive letters.**
  `l4` compares a drive letter without regard to case (`C:` and `c:` are the same), because the checker and the operating system do not always agree on its case.
  The test for this is written but marked as pending anywhere but Windows, so it has not been seen to run.
- **Typing the file name.**
  The commands on this page write the file name with `/`, as they were run on macOS.
  How a Windows terminal passes such a name on to `l4` was not tried, and neither was the same name with `\`.
- **Folder names.**
  The safe set (letters A to Z without accents, digits, `.`, `-`, `_`) is about what the service can read, so it is the same on every system.
- **`IMPORT` names.**
  Write them without a path, as on this page.
  The draft rules for path imports say a path is written with `/` only, and that a backslash is not a separator on any platform.
  That is a proposal, in `specs/proposals/RELATIVE-IMPORTS-SPEC.md` (section 4.2).
  What was run, on macOS, is that a backslash inside quotation marks is read as part of the name (see [What does not work yet](#what-does-not-work-yet)).
- **The per-user library folder.**
  On Windows it is `%APPDATA%\jl4\libraries\`, according to [How IMPORT finds libraries](../../reference/libraries/resolution.md), which says it was taken from the source and not run on Windows.
  A library `l4` finds there is not on the service.
- **Setting `JL4_LIBRARY_PATH`.**
  Step 2 needs it, and gives the PowerShell line (`$env:JL4_LIBRARY_PATH = "C:\Users\you\folders-example"`) and the Command Prompt line (`set JL4_LIBRARY_PATH=C:\Users\you\folders-example`).
  Those are the ways those two terminals set any setting for the window you are typing in.
  They were not tried with `l4`.
  In the code, `l4` reads the setting with `lookupEnv "JL4_LIBRARY_PATH"` (`jl4-lsp/src/LSP/L4/Rules.hs`), the same call on every system.
  Set it to the full path of the project's top folder, and do not set it for the whole account.
- **Spaces in the path.**
  A top folder with spaces and brackets in its name, `Smith v Jones (2024)`, deployed on macOS with the setting given in quotation marks (`JL4_LIBRARY_PATH="$PWD"`).
  Whether that works on Windows was not tried.

---

## How this page was checked

- **The build.**
  The `l4` and the VS Code module were built from a tree whose code is the code of commit `8c6759479`, which `gh pr view 749` showed as the head of #749 on 2026-10-26.
  That commit was made by a rebase at 10:04, after the `l4` file was written at 09:52:55, which is why the commit is newer than the file.
  The branch tip when the `l4` was built was `2a453483e` (09:52:19), and `git diff --stat 2a453483e 8c6759479` over the `.hs`, `.cabal`, `.ts`, `.js` and `.json` files shows no difference.
  The pull request is a draft and open.
  The #748 and #751 pull requests are also open drafts.
- **Where the commands ran.**
  Every `l4` message quoted above was copied from a run of that `l4` on macOS (Apple silicon) on 2026-10-26, with `HOME` and `XDG_DATA_HOME` pointed at empty folders, so that no library of the person who ran them could be found.
  The commands that needed no service ran with `--server http://127.0.0.1:9`.
- **The "Deploying" lines.**
  The lines with port 18765 were printed while `l4` sent to a stand-in server on the same machine: a small script that answers "not found" to lookups and "accepted" to uploads, and prints the names of the files inside the zip it receives.
  Those names agreed with the names on the "Deploying" line every time.
  Nothing was deployed to Legalese Cloud, and the "Accepted" lines the stand-in caused are not shown because they mean nothing.
  When this page was revised, the same deploys were run again against the `jl4-service` built in the worktree of #749, started on the same machine with an empty store; it printed the same names, and the calls in Step 3 and the 40, 17 and 119 in this page's text came from it.
- **The two services.**
  The old service was a `jl4-service` built on 2026-10-26 in the main checkout of `unstable` (at `63254397f` when the check began), which does not contain the service change.
  The new service was the `jl4-service` built in the worktree of #749.
  The date on that file is earlier than the commit time git shows, so it was confirmed by behaviour that it has the change: it found `terms.l4` at the top of the upload, and the old service did not.
- **The older `l4`.**
  The line "An `l4` made from `unstable` before this pull request printed `late-fee.l4, rates.l4, terms.l4`" is from a run of an `l4` built in the main checkout of `unstable` on 2026-10-26, deploying the Step 2 project with the setting made, to the new service.
- **The VS Code messages** came from the compiled module `ts-apps/vscode/out/deploy-bundle.js`, run with `node`.
  VS Code was not opened.
- **The example files.**
  Each of the five files, as shipped, passes `l4 run` on its own, which is what `doc/test-docs.sh` does with every `.l4` file under `doc/`.
  The project after Step 2 does not pass that way, because `terms.l4` is found only through `JL4_LIBRARY_PATH`, and the documentation check does not set it.
  That is why the shipped files do not contain the change that Step 2 asks you to make, nor the second `rates.l4` of case 4: a `rates.l4` at the top would change what Step 2 answers.
  After Step 2, `JL4_LIBRARY_PATH=$PWD l4 run fees/late-fee.l4` answers 40, and the same for `deadlines/payment-deadline.l4` answers 17.
- **The section on splitting a file** was run in small projects made for the purpose and not shipped: one with a `DECLARE`, a rule, a figure, an `#EVAL` and an `@export` in the imported `terms.l4`; one with a second `rates.l4` in the `deadlines` folder; one with `IMPORT Rates`; and one with `IMPORT prelude` in the helper.
- **The sentence about aliases** is from the draft pull request #751 and its own page on that branch; it was not run here, except that this `l4` stops at `IMPORT rates AS r`.
- **Only read, not run:** anything on Windows; the message `Could not read …`, which the code has as a second line of defence after the check in case 5 and which `l4` could not be made to print; the other stops of the Deploy button listed in its section; and how the VS Code tab shows an error.

---

## See also

- [What gets uploaded](../getting-started/l4-cli.md#what-gets-uploaded): the same rules in the reference style of the `l4` guide.
- [Deploy your rules](exporting-rules-for-deployment.md): marking rules with `@export`, deploying, and calling them.
- [Libraries and `JL4_LIBRARY_PATH`](../getting-started/l4-cli.md#step-5-libraries-and-jl4_library_path): where `l4` looks for an imported file.
- [How IMPORT finds libraries](../../reference/libraries/resolution.md): the full order, for people who run the tooling.
