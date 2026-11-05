# Deploy a project that has folders

> _Status (2026-11-05): **proposed, not landed.**
> This page describes what the `l4 deploy` command and the VS Code **Deploy** button do in draft pull request [legalese/l4-ide#749](https://github.com/legalese/l4-ide/pull/749), which also carries draft pull request [#748](https://github.com/legalese/l4-ide/pull/748), the one that lets an `IMPORT` name a file by its path.
> A pull request is a proposed change to the program that people review before it is merged into the program; a draft one is not yet ready.
> Neither is merged, and no release of `l4` or of the VS Code extension carries them.
> This page calls an `l4` made from #749 **this build**.
> Until a release carries the change, `l4 deploy` and the **Deploy** button send every file under its plain file name and keep no folders.
> The page becomes true when #749 merges and a release carries it, and when the service you deploy to is a build that has path imports and the service change that #749 used to carry (see [If the service is too old](#if-the-service-is-too-old)).
> The messages from `l4` below were first copied on 2026-10-26 from a run, on macOS, of an `l4` whose code is the code of commit `8c6759479` of #749.
> On 2026-11-05 every message quoted in Steps 0 to 2 and in cases 1 to 7 was run again, on macOS, with an `l4` built from commit `72ab98fb0`, which has #748 merged, and is copied from that run; the text says where an older build was used.
> Nothing was run on Windows, and the VS Code extension was not opened.
> [How this page was checked](#how-this-page-was-checked) says what was run and what was only read.
> When the draft pull request #751 (see [What does not work yet](#what-does-not-work-yet)) lands, that list needs rewriting._

When you **deploy** a rule, you put a copy of it on a server, so that other programs and AI agents can ask it questions.
`l4 deploy` and the VS Code **Deploy** button do this the same way.
They pack the file you deploy and the files it imports, directly or through other files, into one upload, a single file called a **zip file** (the kind you may have attached to an email), and send it.
The service on the server unpacks it, reads the rules, and starts answering.
Nothing else is sent: not your other rules, not your notes, and not the standard libraries (`prelude`, `daydate` and the others), which the service already has built in.

This page is for the moment you split a project into folders.
It answers three questions: which files are sent, what they are called in the upload, and what stops `l4` from sending them.

---

## Read this first

In this build the upload keeps your folders: a file is named in it by its path below the folder that all the sent files share, with `/` between the parts.
An `IMPORT` can name a file by its path, such as `` IMPORT `../terms` ``, and the service then looks for the file exactly where the path names.
An `IMPORT` without a path, such as `IMPORT terms`, is looked for in two places only, beside the file that imports it and at the top of the upload.
`l4` refuses before it sends when a file would be somewhere the service does not look.
`l4 deploy` takes one file, so two rules to publish are two commands and two deployments, each with its own address.
The service has to be new enough too, or a deploy can say it worked and every call can then fail.

### What this build cannot do

For each of these there is nothing to type: the feature is not in this build.

- **An `IMPORT` cannot start from the top folder**, with a name such as `` `/rates` ``, and has no alias, which would be a short name for a folder.
  `l4` stops at `` IMPORT `/rates` `` with `This import leaves the root of this deployment: /rates`, and at `IMPORT rates AS r` with `unexpected AS`.
  The draft pull request [#751](https://github.com/legalese/l4-ide/pull/751) proposes both, and the page "Split a project into folders" in #751 (not in this documentation) teaches how they are written.
- **If the file you deploy says `IMPORT prelude`, do not reach a shared file through the setting `JL4_LIBRARY_PATH`.**
  While that setting is on, `l4` stops reading its built-in standard libraries, so `l4 deploy` stops at the `IMPORT prelude`.
  Reach the shared file by its path instead, as Step 2 does: that needs no setting, and a deployed file that said `IMPORT prelude` and used `sum` was sent and answered 40.
  [What does not work yet](#what-does-not-work-yet) says more.
- **There is no list of the names without sending.**
  `l4` prints the list only when it is about to send; [Step 0](#step-0-practise-without-sending-anything) says what you can do instead.

### Do you have the change?

`l4 --version` cannot tell you: this build and an older build made from `unstable` both print `dev`.
Two things can, both in Step 2: the "Deploying" line, which shows the folders only on this build, and a one-command test that sends nothing.
If the answer is no, keep each rule's files in one folder, as Step 1 does: an older build deployed that shape to an older service, and the rule answered 40 (run on 2026-10-26).
No release carries the change, so an `l4` from a release, including the one the VS Code extension offers to put on your computer, does not have it.
To get this build you build `l4` from the branch of pull request #749; [Using the l4 CLI](../getting-started/l4-cli.md#option-b-build-from-source) explains building from source, and this page can say no more.

### Four rules for the folders

1. **A file that two rules share is imported by its path.**
   From `fees/rates.l4`, `` IMPORT `../terms` `` reaches `terms.l4` in the top folder, the folder that holds the rule folders, and `` IMPORT `../precedents/terms` `` reaches it in a folder called `precedents`: the service looks exactly where the path names ([Step 2](#step-2-move-the-shared-figure-to-the-top)).
   Without a path, `IMPORT terms` is looked for only beside the importing file and at the top of the upload, so a shared file in a folder of its own (`common`, `precedents`, `lib`) needs a path; [case 2](#2-a-file-kept-in-a-folder-where-the-service-does-not-look) is what `l4` says when it has none.
2. **A file that only one rule uses goes beside that rule.**
   Giving each rule its own folder, as Alex does below, is a choice and not a requirement.
   A file beside the file that imports it needs no path: `IMPORT rates` finds `rates.l4` there.
3. **Name the folders that hold imported files with only the letters A to Z (no accents), digits, `.`, `-` and `_`.**
   A folder called `late fees`, with a space, or `Fristen (2024)`, with brackets, is refused ([case 3](#3-a-folder-name-the-service-cannot-read)).
   The name of the top folder itself is not judged: a project kept in a folder called `Smith v Jones (2024)` deployed without complaint.
4. **Give every file a name of its own.**
   In particular, do not put a second `rates.l4` at the top when another sits in `fees`: `l4` takes the one at the top and says nothing ([case 4](#4-two-files-with-one-name)).

### Words this page uses for folders

- **The top folder** is the folder that holds the rule folders, here `folders-example`, and the folder you run `l4` from.
  `l4`'s own messages call it "the project folder" ([case 1](#1-a-file-outside-the-project-folder) gives its exact meaning), and the VS Code messages call it "the project root", which there is the workspace folder that holds the file.
- **The top of the upload** is the folder that all the sent files share, where the service looks for a file imported without a path that is not beside its importer.
  A path never climbs above it ([case 7](#7-a-path-that-the-upload-would-not-keep)).
  It is not always the top folder: in Step 1 it is `fees`, and from Step 2 on it is the top folder.
- **A rule folder** is a folder with a rule in it and the files beside that rule, such as `fees`.

---

## An example: two rules, two folders

Alex runs a small supply business and has written two rules.
One works out the fee for a late invoice.
The other works out the last day a customer can pay without a fee.
Each rule has its own folder, with a helper file beside it.
Both rules quote the same grace period, 14 days, so Alex also keeps a file at the top, `terms.l4`, for figures the rules share.

```
folders-example/          the top folder
  terms.l4                a figure both rules use
  fees/                   a rule folder
    late-fee.l4           the file to deploy
    rates.l4              its helper
  deadlines/              a rule folder
    payment-deadline.l4   the file to deploy
    grace.l4              its helper
```

The five files are printed in full below.
To follow along, save each one under the name in its first line, in the folders shown above; a file name must end in `.l4`.
The first line of each listing is a comment, a line that starts with `--`, which L4 skips; save it with the rest of the file.
The same files are in the documentation source, in a folder called `folders-example` beside this page, one link each: [terms.l4](folders-example/terms.l4), [fees/late-fee.l4](folders-example/fees/late-fee.l4), [fees/rates.l4](folders-example/fees/rates.l4), [deadlines/payment-deadline.l4](folders-example/deadlines/payment-deadline.l4) and [deadlines/grace.l4](folders-example/deadlines/grace.l4).

The figure `the grace period in days` is written in three files on purpose: `terms.l4`, `fees/rates.l4` and `deadlines/grace.l4`.
Step 1 deploys with a copy in each folder, and nothing imports `terms.l4` yet.
Step 2 replaces the two copies in the folders with an import of the one at the top.

Here are the two files of the `fees` rule.
`IMPORT rates` is how `late-fee.l4` says "also read `rates.l4`, which sits beside me"; you write the name without `.l4`.
`@export` marks a rule to be published, and the sentence after `default` describes it for the people and programs that call it; [Deploy your rules](exporting-rules-for-deployment.md#step-1-mark-rules-with-export) explains both.

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

## Step 0: Practise without sending anything

Steps 1 and 2 send your files to a real service, which keeps them under the name `late-fee`.
You can practise first in two ways.

**Ask `l4` whether it would accept your files, without sending anything.**
Open a terminal in the `folders-example` folder and give `--server` an address where nothing listens.
`http://127.0.0.1:9` is one on most computers: your own machine, on a port that nothing normally uses.

```bash
l4 deploy fees/late-fee.l4 --server http://127.0.0.1:9
```

If `l4` would accept the files, it goes on to try that address and says it cannot reach it (the words after the address are those of macOS and may differ on your computer):

```
Could not reach http://127.0.0.1:9: ConnectionFailure Network.Socket.connect: <socket: 3>: does not exist (Connection refused)
```

That means no file was refused.
If something is wrong with the files, you get one of the messages in [What stops a deploy](#what-stops-a-deploy) instead; the exit status is 1 either way.
This check does not list the names, cannot tell you whether the service will find your files, and can pass while `l4 check` on the same files is red (see [What does not work yet](#what-does-not-work-yet)).

**Send under a throwaway name, then remove it.**
Give each rule its own throwaway name: add `--name late-fee-test` to each `l4 deploy` and `l4 redeploy` of the `fees` rule, and `--name payment-deadline-test` to those of the `deadlines` rule.
At the end, run `l4 undeploy late-fee-test` and `l4 undeploy payment-deadline-test`; `l4` asks you to type the name to confirm.
In the address of [Step 3](#step-3-call-each-rule-once), use the throwaway name in place of the first `late-fee` or `payment-deadline`; the second stays, because it is the name of the rule.

---

## Step 1: Deploy a rule whose files sit in one folder

In the `folders-example` folder, run:

```bash
l4 deploy fees/late-fee.l4
```

By default `l4 deploy` sends to Legalese Cloud; `--server` names a service you run yourself.
Sign in first if you have not: [Using the l4 CLI](../getting-started/l4-cli.md#sign-in) shows how, with `l4 install legalese` and then `legalese login`.
That guide says `l4 install legalese` runs on macOS and Linux, and neither page says how to sign in from Windows.

Just before it sends the files, `l4` prints one line that names everything it is about to send.
This is what it printed, from a run against a `jl4-service` on the same computer (see [How this page was checked](#how-this-page-was-checked)):

```
Deploying 'late-fee' to http://127.0.0.1:18880: late-fee.l4, rates.l4
Compiling…
Deployed 'late-fee' (version 0.0.0) with 1 function:
  late fee
API: http://127.0.0.1:18880/deployments/late-fee
```

The words between `to` and the colon name the service; on Legalese Cloud they name your organization instead, as in [Using the l4 CLI](../getting-started/l4-cli.md#deploy-update-list-remove) (not run for this page).
The names after the colon are what matter here, and there are three things to read in them.

First, only two files were sent.
`late-fee.l4` imports `rates.l4`, so both go; `terms.l4` and the whole `deadlines` folder stay behind, because nothing in this rule imports them.

Second, the names are plain: `late-fee.l4`, not `fees/late-fee.l4`.
Both files sit in `fees`, so `fees` is the top of the upload and does not appear in the names.

Third, you did not have to tell `l4` where `rates.l4` is: it looks for an imported file beside the file that imports it, and here it is.

Deploying the other rule the same way, with `l4 deploy deadlines/payment-deadline.l4`, sends `payment-deadline.l4` and `grace.l4`, as a second deployment with its own address.
`l4 deploy deadlines`, with a folder in place of a file, is not accepted; `l4` says `No such file: deadlines`.

---

## Step 2: Move the shared figure to the top

Alex notices that `the grace period in days` is written out twice, once in each folder.
If it ever changes, it has to change in two places.
So Alex keeps it in `terms.l4` at the top, and makes both helper files import it.

Replace the whole of `fees/rates.l4` with:

```l4
-- rates.l4: what a late invoice costs, kept beside late-fee.l4.
IMPORT `../terms`

`the flat fee` MEANS 25
`the monthly late rate` MEANS 0.015
```

Replace the whole of `deadlines/grace.l4` with:

```l4
-- grace.l4: how long a customer has to pay, kept beside payment-deadline.l4.
IMPORT `../terms`

`courtesy days` MEANS 3
```

`` `../terms` `` is a **path**: it says where the imported file is, counted from the folder of the file that imports it.
`..` means the folder above, so from `fees/rates.l4` it names `terms.l4` in the top folder.
Write a path between backticks (the `` ` `` key, not a quotation mark), with `/` between its parts on every system, and without the `.l4`.

`late-fee.l4` and `payment-deadline.l4` do not change.
A name that `rates.l4` gets from `terms.l4` is also available in `late-fee.l4`, which imports `rates.l4`, so `late-fee.l4` does not need its own import of `terms.l4`.

Now run the same command again:

```bash
l4 deploy fees/late-fee.l4
```

The line that `l4` prints is now:

```
Deploying 'late-fee' to http://127.0.0.1:18880: fees/late-fee.l4, fees/rates.l4, terms.l4
```

The files are now in two places, `fees` and the top folder, so the top of the upload is the top folder `folders-example`, and `fees` appears in the names: the folder is kept.
The service looks for `` `../terms` `` exactly where the path names, counted from `fees/rates.l4` in the upload, which is `terms.l4`.
That line means `l4` is sending; the lines after it say whether the service accepted the files.

The other rule, `l4 deploy deadlines/payment-deadline.l4`, prints:

```
Deploying 'payment-deadline' to http://127.0.0.1:18880: deadlines/payment-deadline.l4, deadlines/grace.l4, terms.l4
```

The two uploads share `terms.l4` and nothing else.
That is two deployments: you ran the command twice, so the service has two rules, `late-fee` and `payment-deadline`, with two addresses.

**If you sent Step 1 for real, the service already has `late-fee`**, and `l4 deploy` will not create it a second time.
It prints this, exits with status 1, and sends nothing:

```
'late-fee' already exists in http://127.0.0.1:18880.
Update it with `l4 redeploy fees/late-fee.l4`.
```

Do what it says: `l4 redeploy fees/late-fee.l4`, and the same for `payment-deadline` if you deployed that one too.
The line it prints then begins `Redeploying` and names the same three files, and on the service used here the version goes from 0.0.0 to 0.0.1.
`l4 redeploy` refuses an update that would break callers, such as a removed rule or a changed input, unless you add `--force`; this update changes none.

Run these commands from the top folder, or from the folder above it with `folders-example/fees/late-fee.l4`.
From inside `fees` it is refused, because `terms.l4` is then outside the folder you ran `l4` from (see [below](#1-a-file-outside-the-project-folder)).

### Without a path: `IMPORT terms`, and the setting it needs

You may have seen `IMPORT terms`, without a path, in other projects.
Write that in the two helpers instead, run `l4 deploy fees/late-fee.l4` again, and it fails; the failure is worth seeing once.
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
It does not mean you wrote something wrong in them: read the first message, not the last line.

A name without a path is searched for, in a few places.
Step 1 worked because `rates.l4` sat beside `late-fee.l4`.
Now `terms.l4` does not sit beside `rates.l4`: it sits in the top folder.
`l4` looks for a name without a path beside the files it is reading, in its own built-in libraries, and in a per-user library folder.
It does not look in the top folder of your project unless you tell it to, and a path is one way to tell it.
The other way to tell it is an **environment variable**, a named setting that your terminal hands to the programs it starts.
This one is called `JL4_LIBRARY_PATH`; [Step 5 of the l4 guide](../getting-started/l4-cli.md#step-5-libraries-and-jl4_library_path) explains it.
Set it to the **full path** of the top folder, here `folders-example`: the whole address of the folder, starting from the top of the disk, such as `/Users/you/folders-example`.

On macOS and Linux you write it in front of the command, and it applies to that one command:

```bash
JL4_LIBRARY_PATH=$PWD l4 deploy fees/late-fee.l4
```

(`$PWD` is the full path of the folder you are in.)
A setting that is not a full path, such as `JL4_LIBRARY_PATH=.`, stops with a message that names the file and not the setting; see [case 6](#6-a-setting-that-is-not-a-full-path).

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

Where this page writes `JL4_LIBRARY_PATH=$PWD` in front of an `l4` command, on Windows type one of the setting lines above first, and then the `l4` command without the `JL4_LIBRARY_PATH=$PWD` in front of it (not tried).
Each setting stays until you close that window (how those terminals work in general; not checked with `l4`), so close the window and open a new one before you work on other files.
How to type the file name on Windows (`fees/late-fee.l4` or `fees\late-fee.l4`) was not tried either.

**Do not set it in Windows' system settings, or in a startup file on macOS or Linux, so that it applies to everything.**
While it is set, `l4` stops reading the standard libraries from the copy built into it, so `l4 check` and `l4 run` of any file that says `IMPORT prelude` fail with `I could not find a module with this name: prelude`.
A setting made for the whole account would do that to every project you work on.
`l4 deploy` has no option that does the same job: its options are `--name`, `--description`, `--no-wait`, `--json`, `--server` and `--api-key-file`.

With the setting on and `IMPORT terms` in the helpers, the "Deploying" lines are the ones above, and the rules answer as in Step 3.
From the folder above the top folder, write `folders-example/fees/late-fee.l4` and keep the setting on `folders-example` (`JL4_LIBRARY_PATH=$PWD/folders-example`): with `JL4_LIBRARY_PATH=$PWD` there, `$PWD` is the folder above, which does not hold `terms.l4`, and `l4` stops with `I could not find a module with this name: terms`.
A path needs none of this, which is why this page uses one.

**A test that sends nothing: does your `l4` have the change?**
With the Step 2 files in place, run this from the top folder:

```bash
l4 deploy fees/late-fee.l4 --server http://127.0.0.1:9
```

This build gets as far as the `Could not reach` message of Step 0.
An older build, made from `unstable` without path imports, stops with `I could not find a module with this name: terms`: it reads `` `../terms` `` as the name `terms` and looks for it beside `rates.l4`.
That tells you whether your `l4` reads paths, not whether it keeps folders.
For that, put `IMPORT terms` back in the helpers, and set the setting to `.`, which is wrong on purpose ([case 6](#6-a-setting-that-is-not-a-full-path)):

```bash
JL4_LIBRARY_PATH=. l4 deploy fees/late-fee.l4 --server http://127.0.0.1:9
```

This build stops with:

```
Cannot upload file://terms.l4: its file path terms.l4 is not absolute.
```

An older build, made from `unstable` before the pull request, printed `Skipping terms.l4: not found` and then the `Could not reach` message of Step 0; if you see that, your `l4` does not have the change.
A later build may word these lines differently.
On Windows the same test would set the setting to `.` with the lines above; that was not tried.

---

## Step 3: Call each rule once

Whatever the "Deployed" line says, call each rule once and read the answer.
A service that is too old can say "Deployed" and then fail every call; [If the service is too old](#if-the-service-is-too-old) shows it.

A call is a request sent to the rule's address.
`curl` is a program that sends a request to a web address and prints the answer.
The part after `-d` is the rule's inputs, written in JavaScript Object Notation (JSON), a plain-text way of writing a list of named values.
This is the call for the `fees` rule, in the form [Deploy your rules](exporting-rules-for-deployment.md#step-5-call-a-rule) shows for Legalese Cloud:

```bash
curl -X POST https://api.legalese.cloud/{orgSlug}/late-fee/functions/late-fee/evaluation \
  -H "Authorization: Bearer sk_..." \
  -H "Content-Type: application/json" \
  -d '{"arguments": {"invoice-amount": 1000, "days-overdue": 20}}'
```

Replace `{orgSlug}`, braces included, with your organization's name, as `acme` is in `https://api.legalese.cloud/acme/late-fee` in the l4 guide, and `sk_...` with your key.
Deploy your rules says you create the key in the Legalese Cloud console; neither page says whether a colleague should share your key or make one of their own.
The backslashes at the ends of lines only tell a macOS or Linux terminal that the command goes on; type the command on one line if you are not sure.

In the address, the first `late-fee` is the name of the deployment, which is the file name unless you gave `--name`, and the second is the name of the rule.
In the address and the inputs, the spaces in a name become hyphens: the rule `late fee` is `late-fee`, and the input `invoice amount` is `invoice-amount`.
The answer is the same as the `#EVAL` in `late-fee.l4` gives, 40:

```
{"contents":{"presumed":[],"result":{"value":40}},"report":"default","tag":"SimpleResponse"}
```

The call for the `deadlines` rule has the address ending `/payment-deadline/functions/last-free-day/evaluation` and the inputs `{"arguments": {"asked-for-extra-days": true}}`.
Its answer has the value 17, as its `#EVAL` gives.

Both answers above came from a service run on the same computer, which asked for no key.
For a service like that, the address is the `API:` line that `l4` printed with `/functions/late-fee/evaluation` added: `http://127.0.0.1:18880/deployments/late-fee/functions/late-fee/evaluation`.

A colleague who is to call the rule needs its address and, on Legalese Cloud, a key.
The call has four parts, the method `POST`, the address, the two headers, and the inputs after `-d`, and any program that can send a web request with those four parts will do.
Sending the call with `curl` from a Windows terminal, or with another program, was not tried.

---

## If the service is too old

This build needs a service that has two changes: path imports (#748, which this build carries too) and the change to where the service looks for a file imported without a path, which #749 used to carry and which is now proposed on its own.
On 2026-11-05 it was ruled that the service ships first, and that #749 stays a draft until Legalese Cloud runs a build that has both changes.
A service built before the second change looks up an imported file from the folder of the first file in the upload (in alphabetical order) when it compiles the deployment and answers an ordinary call, and, for a call with a `{}` in an input, from the folder of the rule's own file.
Neither is the top of the upload, so such a service can miss a file that sits at the top (the code comments of this build say so; the outcomes below are what was run).
`l4` and the **Deploy** button cannot tell you which service you are talking to: neither checks its version.
A service built without the setting `JL4_SERVICE_VERSION` reports its version as `0.0.0-dev` whichever changes it has (both services used here did), so its version could not tell you either.

Both outcomes turned up with the example project from Step 2, on two services run on the machine where this page was checked: one built before the service change (the "old" one) and one with it (the "new" one).

**The old service rejected the `fees` rule at once.**
It could not find `terms.l4`, and the rule then did not make sense without it:

```
Deploying 'late-fee' to http://127.0.0.1:18771: fees/late-fee.l4, fees/rates.l4, terms.l4
Compiling…
Update rejected: compilation failed: I found a problem while checking the definition of `late fee`:   There are multiple definitions for the identifier        `__LEQ__`      and I do not have sufficient information to make a choice between them.   The options are:        `__LEQ__` (predefined) of type FUNCTION FROM NUMBER AND NUMBER TO BOOLEAN     `__LEQ__` (predefined) of type FUNCTION FROM STRING AND STRING TO BOOLEAN     `__LEQ__` (predefined) of type FUNCTION FROM BOOLEAN AND BOOLEAN TO BOOLEAN
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
Why the old service coped with one rule and not the other was not worked out here.
Do not count on the loud outcome.

**A test you can run yourself.**
The `deadlines` rule is the useful one, because the old service accepted it and then failed.
Deploy it from the Step 2 project under a name you will delete, and call it as in [Step 3](#step-3-call-each-rule-once):

```bash
JL4_LIBRARY_PATH=$PWD l4 deploy deadlines/payment-deadline.l4 --name canary-test
```

Read the "Deploying" line first, because the answer means something only for an `l4` that has the change.
Four combinations were run, each called with the inputs `{"asked-for-extra-days": true}`:

| `l4`              | service | names on the "Deploying" line                                 | the call                    |
| ----------------- | ------- | ------------------------------------------------------------- | --------------------------- |
| this build        | new     | `deadlines/payment-deadline.l4, deadlines/grace.l4, terms.l4` | 17, status 200              |
| this build        | old     | `deadlines/payment-deadline.l4, deadlines/grace.l4, terms.l4` | 422, `is not in scope`      |
| older, no folders | old     | `payment-deadline.l4, grace.l4, terms.l4`                     | 17, status 200 (misleading) |
| older, no folders | new     | `payment-deadline.l4, grace.l4, terms.l4`                     | 17, status 200 (misleading) |

So when the line shows the folder `deadlines/`, an answer of 17 means the service finds a file at the top of the upload, which is the change, and 422 with `is not in scope` means it does not.
When the line shows plain names, your `l4` lacks the change and the test tells you nothing about the service: an older `l4` sends a flat upload, in which `terms.l4` sits beside every file, and even the old service passes.
The table was run with the setting and `IMPORT terms`.
With the paths of Step 2 and no setting, run on 2026-11-05, this build gave the same answers: 17 from the new service, and from the old one a `payment-deadline` that said "Deployed" and answered 422 with `is not in scope`, while it rejected `late-fee` at once, as above.
The old service had no path imports either, and read `` `../terms` `` as the name `terms`.
An older `l4` stops before it sends, with `I could not find a module with this name: terms`.
Then remove the test deployment with `l4 undeploy canary-test`, which asks you to type the name to confirm.
This page cannot tell you whether Legalese Cloud, or the service your organization runs, is a build that has the change; the test above can.
Whoever runs the service can also tell you: for Legalese Cloud that is Legalese, the company that runs it.

---

## Splitting a file of your own into folders

This page cannot tell you which parts of your own file belong where, because that depends on your rules.
It can tell you what is allowed to move, and a way to sort:

1. Keep your original file as it is, and work on a copy, running `l4 check` on the file you will deploy after each move (importing a file in another folder by its path, as in Step 2).
2. A figure or a kind of thing that two rules use goes to the top folder, in a file such as `terms.l4`, which each rule's files import by its path.
3. A figure that only one rule uses goes in a file beside that rule.
4. The rule you publish stays in the file you deploy, with its `@export`, and the `#EVAL` lines that check it stay there too.

Each point below was tried in a small test project made for the purpose and not shipped here (see [How this page was checked](#how-this-page-was-checked)).

- **A named figure, a kind of thing and a rule with inputs can all live in an imported file.**
  A name defined with `MEANS`, a `DECLARE` (a new kind of thing, such as an `Invoice` with its fields) and a rule with a `GIVEN` input and a `DECIDE` were all usable from the file that imported `terms.l4`, with `l4 run`, and after a deploy, in a call.
- **A `#EVAL` line in an imported file does not run.**
  Running the file that imports it printed one result, the importer's own.
- **An imported file needs no `@export`; the helpers on this page have none.**
  An `@export` in an imported file is published too: when `terms.l4` had an `@export` on a rule, the deployment of the file that imported it said "with 2 functions", and the second rule answered a call.
  Put `@export` only on rules you mean to publish.
- **Two files with the same name in different folders stay apart.**
  When a second `rates.l4`, with a flat fee of 99, also sat in the `deadlines` folder, `l4 deploy fees/late-fee.l4` used `fees/rates.l4`, left the other out of the upload, and the rule answered 40.
  A file with that name at the top is another matter: see [case 4](#4-two-files-with-one-name).
- **Write the name in `IMPORT` with the capitals of the file's name.**
  `IMPORT Rates` also worked here, and the upload then held the file as `fees/Rates.l4`, because the disk of this Mac ignores capitals.
  On a system that tells capitals apart, or on Windows, that was not tried.

---

## What stops a deploy

**How the service finds a file.**
When a file says `IMPORT rates`, the service looks for `rates.l4` beside the file that says it (the same folder in the upload) and at the top of the upload, and nowhere else: it has the files you sent and the standard libraries built into it, and nothing from the machine it runs on.
When a file says `` IMPORT `../terms` ``, the service looks for `terms.l4` only where the path names, counted from the folder of that file in the upload.
`l4` reads imports more widely, also in `JL4_LIBRARY_PATH` and in the per-user library folder, and a library found there is not on the service.
That is why `l4` checks, before it sends, that every imported file will end up where the service looks for it, and refuses when one will not ([What gets uploaded](../getting-started/l4-cli.md#what-gets-uploaded) in the l4 guide says the same in reference style).

Cases 1, 2, 3, 5, 6 and 7 below each stop `l4 deploy` before it sends anything.
They were all run with `--server http://127.0.0.1:9`, as in Step 0, so nothing could be sent.
Case 4 does not stop it: it sends the wrong file and says nothing.
In the messages, the long name of the folder where the project lived during the check is shortened to `…`; `l4` prints the whole path.
A `…` at the end of a line, or on a line of its own, marks a part of a long message that is left out here.
Spaces at the ends of lines are not kept in the quoted messages.

To find your message, look at its first line:

- `This file lies outside the project folder …` is [case 1](#1-a-file-outside-the-project-folder).
- `The deployed service would not find a library this file imports:` is [case 2](#2-a-file-kept-in-a-folder-where-the-service-does-not-look).
- `The deployed service may not find a file that is imported, because of the name of the folder it is in:` is [case 3](#3-a-folder-name-the-service-cannot-read).
- `Cannot upload file://…: its file path … is not absolute.` is [case 6](#6-a-setting-that-is-not-a-full-path).
- `The deployed service would not find a file this file imports by its path:` is [case 7](#7-a-path-that-the-upload-would-not-keep).
- A file that cannot be read, with `permission denied` in a long message that ends `doesn't typecheck`, is [case 5](#5-a-file-that-cannot-be-read).
- `I could not find a module with this name: …`, and a last line that ends `doesn't typecheck; fix it before deploying`, is not one of these refusals.
  `l4` could not check your rules, usually because `JL4_LIBRARY_PATH` is not set to the top folder or does not name it in full; Step 2 shows one.
  Read the first message in the long text above that last line.
- `Could not reach …` means no file was refused; see [Step 0](#step-0-practise-without-sending-anything).
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

With the paths of Step 2 and no setting, the message is the same without its lines about `JL4_LIBRARY_PATH`.
**The fix** for this cause: go back up to the top folder (`cd ..`) and run the command from there.
The advice in the message, "put it inside the project folder", fits the other cause.

The other cause is that the shared file really is kept outside the project, for example in a `common` folder beside `folders-example`, with `JL4_LIBRARY_PATH` naming `common`.
The message is the same and names that file (`…/common/terms.l4`).
**The fix** is to move the file into the project, to the top folder, and to import it by its path, as in Step 2; with `IMPORT terms`, point `JL4_LIBRARY_PATH` at the top folder instead.
Move it; do not copy it.
`l4` reads `JL4_LIBRARY_PATH` first, so while the variable names the old folder, a copy inside the project is ignored.

### 2. A file kept in a folder where the service does not look

Suppose Alex tidies `terms.l4` into a folder called `precedents`, as a firm keeps a folder of precedents, keeps `IMPORT terms` without a path in the helpers, and points `JL4_LIBRARY_PATH` at `precedents`:

```bash
JL4_LIBRARY_PATH=$PWD/precedents l4 deploy fees/late-fee.l4 --server http://127.0.0.1:9
```

```
The deployed service would not find a library this file imports:
  fees/rates.l4 imports terms, which would be uploaded as precedents/terms.l4 (from …/folders-example/precedents/terms.l4), in the folder precedents
The deployed service looks an IMPORT of a bare name (one with no /) up only beside the file that imports it and at the top of the upload (the folder that holds all the uploaded files).
It looks nowhere else, so the deploy would say it is ready and every call would then fail.
Put each library beside the file that imports it, and deploy again.
…
```

A **bare name** is a name in an `IMPORT` with no `/` in it, such as `terms`.
`precedents` is neither the folder of `fees/rates.l4` nor the top, so the service would not find the file by its bare name.
**The fix:** write the path.
With `` IMPORT `../precedents/terms` `` in both helpers and no setting, `l4` sent `fees/late-fee.l4, fees/rates.l4, precedents/terms.l4`, and the rule answered 40.
Moving `terms.l4` to the top folder and writing `` IMPORT `../terms` ``, as in Step 2, works too.
The message says "beside the file that imports it", which is the fix for a file that only one rule uses.

The same refusal is what you get when one rule needs a file from another rule's folder by a bare name.
Suppose `deadlines/payment-deadline.l4` needs `the grace period in days` from `fees/rates.l4` and says `IMPORT rates` (run in a small project of `fees/rates.l4`, `fees/late-fee.l4` and `deadlines/payment-deadline.l4`).
With no setting, `l4` looks beside `payment-deadline.l4`, finds no `rates.l4`, and stops with `I could not find a module with this name: rates`.
With `JL4_LIBRARY_PATH` set to `fees`, `l4` finds it and then stops before sending, because the service would not:

```
The deployed service would not find a library this file imports:
  deadlines/payment-deadline.l4 imports rates, which would be uploaded as fees/rates.l4 (from …/folders-example/fees/rates.l4), in the folder fees
```

**The fix** is a path again: with `` IMPORT `../fees/rates` `` in `payment-deadline.l4` and no setting, `l4` sent `deadlines/payment-deadline.l4, fees/rates.l4`, and the rule answered 17.

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
Deploying 'late-fee' to http://127.0.0.1:18880: fees/late-fee.l4, rates.l4, terms.l4
```

The upload holds the top `rates.l4`, not `fees/rates.l4`.
Nothing says so.
The deployed rule answered 119, and `JL4_LIBRARY_PATH=$PWD l4 run fees/late-fee.l4` agrees: the `#EVAL` in `late-fee.l4` answers 119 with the second file in place (50 plus 1000 times 0.069), and 40 without it.
(Without the setting, `l4 run` of the file stops at `terms`, as in Step 2.)
**The fix:** give each file its own name, remove the copy you did not mean, or import the one you mean by its path, which names one file.

Two files of one name in different folders stay apart in the upload, because the tool names files by folder, and a path can put two such files into one upload.
For a second `rates.l4` in `deadlines`, holding a reminder fee of 9, with `` IMPORT `../deadlines/rates` `` beside `IMPORT rates` in `fees/late-fee.l4` and the fee added in, `l4` sent `fees/late-fee.l4, fees/rates.l4, terms.l4, deadlines/rates.l4`, and the deployed rule answered 49, as `l4 run` did.

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

### 7. A path that the upload would not keep

A path names a file counted from the folder of the file that imports it, and the service reads it the same way in the upload.
`l4` names each file in the upload by its folder as the disk spells it, so a path that the upload would not keep stops the deploy.
Three ways to get there were run, each with `--server http://127.0.0.1:9`.

**A path that leaves the folder of a one-folder upload and comes back.**
With the files of Step 1, all in `fees`, `` IMPORT `../fees/rates` `` in `late-fee.l4` names the right file on the disk, but the upload holds plain names, so from `late-fee.l4` the path climbs out of it:

```
The deployed service would not find a file this file imports by its path:
  late-fee.l4 imports `../fees/rates`, which climbs above the top of the upload, but the file l4 found for it would be uploaded as rates.l4 (from …/folders-example/fees/rates.l4)
The deployed service looks an IMPORT written as a path up only where the path names, counted from the folder of the file that imports it, and never above the top of the upload (the folder that holds all the uploaded files).
The deploy would say it is ready and every call would then fail.
A path climbs above the top of the upload when it leaves the folder that holds all the uploaded files, even if it then comes back into it.
Write each path as the place of the file in the upload, counted from the folder of the file that imports it, and deploy again:
  in late-fee.l4, `../fees/rates` as `./rates`
```

**A folder written with other capitals than the disk has.**
On this Mac, whose disk ignores capitals, `` IMPORT `../Deadlines/grace` `` in `fees/late-fee.l4` finds `deadlines/grace.l4`, but the service tells capitals apart.
`l4` stops with the same first line, a second line that says the path names `Deadlines/grace.l4` and the file would be uploaded as `deadlines/grace.l4`, and this explanation and advice:

```
l4 names each uploaded file by its folder as the disk spells it, with links followed, so a folder on the path that is a link, or that is written with other capitals than the disk has, puts the file somewhere the path does not name.
Write each path as the place of the file in the upload, counted from the folder of the file that imports it, and deploy again:
  in fees/late-fee.l4, `../Deadlines/grace` as `../deadlines/grace`
```

Only folders are judged this way: `` IMPORT `../Terms` `` for the file `terms.l4` was sent as `Terms.l4`, the name the path wrote, and the rule answered 40.

**A folder reached through a symbolic link** (a shortcut to a folder).
With `common` a link to a folder `shared` that holds `terms.l4`, `` IMPORT `../common/terms` `` in the helpers stops with the advice `` in fees/rates.l4, `../common/terms` as `../shared/terms` ``.

**The fix** is the last line of the message: write the path it gives.
For the capitals and the link, refusing rather than sending the file under the name the path wrote is a choice made for this build, not yet ruled on.

---

## The VS Code Deploy button

In this build, the **Deploy** tab in the VS Code sidebar packs the same upload with the same names, and refuses in some of the same cases.
It checks less, and it needs the same service ([If the service is too old](#if-the-service-is-too-old)).
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

What the button cannot do is check where a file imported by a bare name sits.
The editor's language server hands the extension the list of imported files, not the `IMPORT` lines, so the extension cannot tell whether a file is beside its importer or at the top.
A shared file in a third folder, such as `precedents` in case 2 above, imported as `IMPORT terms`, is sent anyway.
The service then says "ready", and a call that needs the file fails.
Until that is fixed, check the folders by hand, or run `l4 deploy` with `--server http://127.0.0.1:9` first.

A file imported by its path mostly needs no check: the language server finds it where the path names, and the button sends it there.
For `rows/a/main.l4` saying `` IMPORT `../b/mod` ``, the button's code names the files `a/main.l4` and `b/mod.l4` (a test of that code, in `ts-apps/vscode/src/unit-tests/deploy-bundle.test.ts`).
The exception is the first kind in case 7, a path that leaves the folder of a one-folder upload and comes back.
For `` IMPORT `../fees/rates` `` in `fees/late-fee.l4`, with both files in `fees`, the button's code names them `late-fee.l4` and `rates.l4`; given that upload, the service said "ready", and a call answered 422 with `is not in scope`, because from `late-fee.l4` the path leaves the upload.
Write such a path without leaving the folder: `` `./rates` ``, or `IMPORT rates`.
Unlike `l4`, the button does not stop at a folder reached through a link: read in its code and not run, it sends the file under the name the path wrote, which is where the service looks.

Not tested: how the tab displays these messages, whether the editor's language server finds a `terms.l4` at the top of your workspace folder without help, and what the tab does with a name that already exists ([Deploy your rules](exporting-rules-for-deployment.md#update-a-deployment) says it updates that deployment).
The code returns the message to the tab as the reason the deploy failed, and writes it to the L4 Output channel as `[sidebar] Deploy failed: …`.

---

## What does not work yet

- **The root-relative form and aliases.**
  The draft pull request [#751](https://github.com/legalese/l4-ide/pull/751) proposes a name starting with `/`, counted from the top folder, and aliases; the page that teaches them, "Split a project into folders", is in the branch of #751 and so has no link here.
  Neither is in this build: `` IMPORT `/rates` `` stops with `This import leaves the root of this deployment: /rates`, and `IMPORT rates AS r` with `unexpected AS`.
  Any other name with a `/` in it is a path, and a path that names no file stops the check: `` IMPORT `@common/rates` `` in `fees/late-fee.l4` gave `I could not find a module at this path: @common/rates`.
  Without backticks, a slash is an error: `IMPORT fees/rates` gave `unexpected /` (run on 2026-10-26 with the older build).
  A backslash inside backticks, as in `` IMPORT `fees\rates` ``, is not a folder separator either: `l4` looked for a module whose whole name was `fees\rates` and did not find one (run on macOS).

- **A file you deploy that imports a standard library cannot be checked while `JL4_LIBRARY_PATH` is set.**
  A path needs no setting, so with the paths of Step 2 this does not arise: with `IMPORT prelude` in `fees/late-fee.l4` and `sum` used, `l4 run` answered 40, and the deployed rule answered 40 (run on 2026-11-05).
  The rest of this point is about the setting, and was run on 2026-10-26 with the older build.
  With the variable set, `l4` stops reading the standard libraries from the copy built into it.
  When the file you deploy says `IMPORT prelude` and uses `sum` (from the prelude), `l4` stops:

  ```
  I could not find a module with this name: prelude
  …
  the stdlib embedded in this binary (skipped: JL4_LIBRARY_PATH is set),
  …
  fees/late-fee.l4 doesn't typecheck; fix it before deploying (see `l4 check`).
  ```

  When only a helper does, `fees/rates.l4` saying `IMPORT prelude` and using `sum`, `l4 check` of `fees/late-fee.l4` reports the same first message, yet `l4 deploy` sent the files, and the deployed rule answered 40, the answer it should give.
  So the error stopped the deploy when it sat in the file you deploy, and did not when it sat in a helper, although `l4 check` of the deployed file reported it in both cases.
  Why the service coped with the helper was not looked into.
  Only `prelude` was tried; the other standard libraries were not.
  So with the setting, a project whose deployed file imports a standard library and also shares a file at the top could not be deployed in those runs; use a path.

- **`l4 deploy` can send files while `l4 check` on the same files is red.**
  In the helper case above, nobody has worked out where the line lies, so when `l4 check` is red, treat what `l4 deploy` sent as unchecked.
  The other case run was a rule that said `IMPORT rates`, used no name from it, and had no `rates.l4` where `l4` looks: `l4 check` printed `I could not find a module with this name: rates`, `l4 deploy` sent `late-fee.l4` alone, the service said "Deployed", and a call answered 2000, the answer the file gives.
  That one is a decision recorded in the service: it accepts a deployment whose `IMPORT` finds nothing and writes one warning to its own log, "a WARN now, a refusal only by a later ruling" (ruling R5, 2026-10-12; the comment above `logUnresolvedImports` in `jl4-service/src/Compiler.hs`).
- **A file at the top whose own name has a space or an accented letter is not found by the service, and `l4` does not stop it.**
  The code comments of this build say so (`jl4/app/L4/Cli/DeployPlan.hs`).
  Re-run for this page, with `terms.l4` renamed `my terms.l4` and `` IMPORT `my terms` `` in the helpers: `l4` did not stop, it sent `fees/late-fee.l4, fees/rates.l4, my terms.l4`, and the new service rejected the rule at once with `Update rejected: compilation failed`, the loud message of [If the service is too old](#if-the-service-is-too-old).
  Give shared files plain names too.
- **Neither tool checks the version of the service**, and **the Deploy button cannot check where a file imported by a bare name sits, nor a path that leaves the folder of a one-folder upload.**
  See [If the service is too old](#if-the-service-is-too-old) and [The VS Code Deploy button](#the-vs-code-deploy-button).

---

## Windows

Nothing on this page was run on Windows.
This is what was read in the code and in other pages; [Step 2](#step-2-move-the-shared-figure-to-the-top) has the lines for setting `JL4_LIBRARY_PATH`, [Step 1](#step-1-deploy-a-rule-whose-files-sit-in-one-folder) says what is missing for signing in, and [Step 3](#step-3-call-each-rule-once) for sending the call.

- **Names in the upload use `/`, on every system.**
  The code that makes them joins the parts with `/` (`jl4/app/L4/Cli/DeployPlan.hs` for `l4`, `ts-apps/vscode/src/deploy-bundle.ts` for the button), so the upload holds `fees/late-fee.l4`, never `fees\late-fee.l4`.
  The names were looked at only on macOS.
- **Drive letters.**
  `l4` compares a drive letter without regard to case (`C:` and `c:` are the same), because the checker and the operating system do not always agree on its case.
  The test for this is written but marked as pending anywhere but Windows, so it has not been seen to run.
- **`IMPORT` paths.**
  A path is written with `/` between its parts, on every system, and a backslash is not a separator on any platform: that is the rule in `specs/proposals/RELATIVE-IMPORTS-SPEC.md` (section 4.2), which #748 implements.
  What was run, on macOS, is that a backslash inside backticks is read as part of the name (see [What does not work yet](#what-does-not-work-yet)).
- **The per-user library folder.**
  [How IMPORT finds libraries](../../reference/libraries/resolution.md) gives it on Windows as `%APPDATA%\jl4\libraries\`, usually `C:\Users\<you>\AppData\Roaming\jl4\libraries\`.
  Nothing on that page says it was run on Windows, and nobody checked it on Windows for this page.
  A library `l4` finds there is not on the service.
- **The setting.**
  In the code, `l4` reads `JL4_LIBRARY_PATH` with `lookupEnv "JL4_LIBRARY_PATH"` (`jl4-lsp/src/LSP/L4/Rules.hs`), the same call on every system.
  A top folder called `Smith v Jones (2024)` deployed on macOS with the setting in quotation marks (`JL4_LIBRARY_PATH="$PWD"`); whether that works on Windows was not tried.

---

## How this page was checked

- **The build.**
  On 2026-10-26, the `l4` and the VS Code module were built from a tree whose code is the code of commit `8c6759479`, which `gh pr view 749` showed as the head of #749 on 2026-10-26.
  The branch tip when the `l4` was built was `2a453483e` (09:52), and `git diff --stat 2a453483e 8c6759479` over the `.hs`, `.cabal`, `.ts`, `.js` and `.json` files shows no difference.
  On 2026-11-05, `l4` and `jl4-service` were built again from commit `72ab98fb0` of the branch of #749, after #748 and the service change, which now has a branch of its own, had been merged into it.
  Every message quoted in Steps 0 to 2 and in cases 1 to 7 was run again with them, in the same way as below, against that service on port 18880 and an old one on port 18771; where a message had changed (the third line of case 2), the page now quotes the new one.
  That old service and an older `l4` were built on 2026-11-04 in the main checkout of `unstable`, which had neither path imports nor the service change; the commit they were built at was not recorded, and the old service was confirmed by behaviour to lack both.
  The pull requests #749, #748 and #751 are open drafts.
- **Where the commands ran.**
  Every `l4` message quoted above was copied from a run of that `l4` on macOS (Apple silicon) on 2026-10-26, with `HOME` and `XDG_DATA_HOME` pointed at empty folders, so that no library of the person who ran them could be found.
  The commands that needed no service ran with `--server http://127.0.0.1:9`.
- **The "Deploying" lines and the calls** were printed while `l4` sent to a `jl4-service` on the same machine, built in the worktree of #749 and started on port 18880 with an empty store.
  The calls in Step 3 and the 40, 17 and 119 in this page's text came from it.
  Nothing was deployed to Legalese Cloud.
  An earlier version of this page used a stand-in script that answered "not found" to every lookup, and that hid the "already exists" refusal of Step 2.
- **The two services.**
  The old service was a `jl4-service` built on 2026-10-26 in the main checkout of `unstable`, which does not contain the service change (port 18771); the older `l4` was built there too.
  The new service was the one in the worktree of #749.
  The date on the new service's file is earlier than the commit time git shows, so it was confirmed by behaviour that it has the change: it found `terms.l4` at the top of the upload, and the old service did not.
  The table in [If the service is too old](#if-the-service-is-too-old) and the test at the end of Step 2 come from runs of the older `l4` and of this build, against both services.
- **The VS Code messages** came from the compiled module `ts-apps/vscode/out/deploy-bundle.js`, run with `node`; on 2026-11-05 the same module gave the names for `` IMPORT `../fees/rates` `` in the VS Code section, and the 422 was a call to the new service given a zip of those two names.
- **The example files.**
  Each of the five files, as shipped, passes `l4 run` on its own, which is what `doc/test-docs.sh` does with every `.l4` file under `doc/`.
  They are the project as Step 1 deploys it, so they do not contain the change that Step 2 asks you to make, nor the second `rates.l4` of case 4: a `rates.l4` at the top would change what Step 2 answers when the setting is on.
  After Step 2, `l4 check fees/late-fee.l4` succeeds and `l4 run fees/late-fee.l4` answers 40, with no setting (run on 2026-11-05).
- **The section on splitting a file** was run in small projects made for the purpose and not shipped: one with a `DECLARE`, a rule, a figure, an `#EVAL` and an `@export` in the imported `terms.l4`; one with a second `rates.l4` in the `deadlines` folder; one with `IMPORT Rates`; and one with `IMPORT prelude` in the helper.
- **The sentences about aliases and the page "Split a project into folders"** are from the draft pull request #751 and that page on its branch; they were not run here, except that this `l4` stops at `IMPORT rates AS r`.
- **Only read, not run:** anything on Windows; the message `Could not read …`, which the code has as a second line of defence after the check in case 5 and which `l4` could not be made to print; the other stops of the Deploy button listed in its section; how the VS Code tab shows an error; and signing in to Legalese Cloud.

---

## See also

- [What gets uploaded](../getting-started/l4-cli.md#what-gets-uploaded): the same rules in the reference style of the `l4` guide.
- [Deploy your rules](exporting-rules-for-deployment.md): marking rules with `@export`, deploying, and calling them.
- [Libraries and `JL4_LIBRARY_PATH`](../getting-started/l4-cli.md#step-5-libraries-and-jl4_library_path): where `l4` looks for an imported file.
- [How IMPORT finds libraries](../../reference/libraries/resolution.md): the full order, for people who run the tooling.
