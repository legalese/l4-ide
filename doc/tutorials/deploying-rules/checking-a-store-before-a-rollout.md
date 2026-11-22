# Checking a Store Before You Switch Versions

When you run your own `jl4-service`, the rules you deployed are kept in a folder on disk, called the **store**. Each time the service starts, it reads every deployment in the store and compiles it again. This page shows how to find out, before you switch to a new version of the service, whether the new version will accept everything the old one was serving.

**Prerequisites:** a running `jl4-service` with deployments in its store ([Exporting Rules for Deployment](exporting-rules-for-deployment.md) shows how rules get there), and the new version of `jl4-service` installed beside the old one.

---

## Why check

A new version of the service can be stricter than the one before it. It may check a rule differently, a library your rules use may have changed, or a deployment may be too big for the time and memory the new version allows. You would not find out when you install it. You would find out when the service starts, when each deployment it refuses is marked `failed` and stops answering.

`--check-store` lets you find out first. It runs the same compile that starting the service would run, with the new version and on your real store, and tells you what it found. It does not start a server, and it does not change anything in the store.

---

## Step 1: Run the Check

Point the new `jl4-service` at the store. Use the same limits the service will run with, because the check compiles under them:

```
jl4-service --check-store /var/lib/jl4-service/store --compile-timeout 120
```

The check prints one line for each deployment, then a summary. Each line has the deployment's name, `ok` or `failed`, and then how many functions it publishes or why it failed, separated by tabs:

```
sales-rules	ok	3 functions
claims-pilot	failed	Compilation timed out or exceeded memory limit
travel-policy	failed	I found a problem while checking the definition of `is big`: There are multiple definitions for the identifier `__GT__` and I do not have sufficient information to make a choice between them. The options are: ...
3 deployments: 1 ok, 2 failed
```

The first deployment is fine. The other two were refused, and each line says why: `claims-pilot` took longer to compile than the time limit allows, and `travel-policy` has a mistake in one of its rules. (The names are yours; the `...` marks where the real line goes on.) An error that runs over several lines is joined onto one line here. If you want the error exactly as the compiler wrote it, ask for JSON (Step 3).

---

## Step 2: Read the Exit Status

The command also tells a script whether to go on:

| Exit status | Meaning                                                                                                                      |
| ----------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `0`         | Every deployment compiles. A store with no deployments also gives `0`, and prints `0 deployments`.                           |
| `1`         | At least one deployment does not compile. Read the lines marked `failed`.                                                    |
| `2`         | The check could not be made: the folder does not exist or cannot be read, or the command line is wrong. Nothing was checked. |

Stop the rollout on anything but `0`. A `2` is not a verdict on your rules, only on the command, so fix the command and run it again.

---

## Step 3: Get the Report as JSON (Optional)

Add `--json` and the report is one JSON document, with each error exactly as it is:

```
jl4-service --check-store /var/lib/jl4-service/store --json
```

Each deployment has an `id`, a `status` of `ok` or `failed`, a `functions` count (or `null`), an `error` (or `null`), and a `bundleCbor` entry (see below). The `summary` has the totals.

---

## What the Check Does Not Do

- **It does not change the store.** It does not create the folder, remove the leftovers of an interrupted deploy, or write the version numbers and caches that starting the service writes. You can run it on the live store while the old version is serving.
- **It compiles; it does not run your rules.** A deployment that compiles can still answer a call differently under a new version. Compare a few answers from both versions before you rely on it.
- **It uses the same limits as starting the service.** The compile time and memory limits are the ones you pass (`--compile-timeout`, `--max-compile-memory-mb`; the defaults are 60 seconds and 256 MB). A deployment that is slow enough to fail the check would fail when the service starts. The memory limit rarely stops a compile in practice, so a deployment is more likely to fail the time limit than the memory limit.
- **It does not read an old `bundle.cbor`.** Earlier versions of the service left a file called `bundle.cbor` beside the sources of each deployment. The service no longer reads it, and the check does not touch it. If the folder is there, the line says `bundle.cbor present, written by an unknown build`, because nothing in the file says which version wrote it. In the JSON, `bundleCbor.present` is `true` and `bundleCbor.writtenBy` is `null`.

---

## Where to Go Next

- [jl4-service](../../../jl4-service/README.md#checking-a-store-before-a-rollout) has the reference for every option, including the limits.
