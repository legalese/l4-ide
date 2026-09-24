#!/usr/bin/env node
// Emit a new subject sidecar. Driven entirely by env from go.sh's
// cmd_new_subject, which has already validated the id, refused an existing
// directory and refused an encoding path that already exists.
//
// Everything written here is either (a) a value the caller supplied, or (b) a
// statement that something has NOT been done. Nothing is invented. The two
// measurement files -- pins.json and known-defects.json -- are emitted empty
// with a comment saying so: a scaffolder that guessed a CLI enumeration or a
// defect would be manufacturing the evidence the pipeline exists to demand,
// and it would be believed, because a file that looks measured is not
// distinguishable from one that is.
import { writeFileSync } from "node:fs";
import { resolve } from "node:path";

const env = (k) => {
  const v = process.env[k];
  if (!v) {
    process.stderr.write(`new-subject.mjs: ${k} is required\n`);
    process.exit(2);
  }
  return v;
};

const id = env("NEW_ID");
const dir = env("NEW_DIR");
const write = (name, content) =>
  writeFileSync(resolve(dir, name), content, "utf8");
const json = (o) => JSON.stringify(o, null, 2) + "\n";

write(
  "subject.json",
  json({
    _comment: [
      `The ${id} subject sidecar, scaffolded by \`etc/go/go.sh new-subject\`.`,
      "Everything the pipeline needs to know about THIS body of law lives here;",
      "everything about the pipeline itself lives in etc/go/. Validated by",
      "etc/go/lib/subject.mjs, which refuses unknown keys and missing files.",
      "All paths are repo-root-relative.",
      "",
      'encoding.state is "unwritten": the encoding does not exist yet, and',
      "encoding.main is where it WILL live. Every stage that reads a module will",
      "report SKIPPED naming the file to deposit, which is an honest account of a",
      "subject that has been registered but not yet encoded. The gate digest is",
      "already taken over that absent path (digestSet records a missing file as",
      "ABSENT rather than skipping it), so depositing the first module MOVES the",
      "digest and re-opens HG1 -- a human gate granted before the encoding existed",
      "cannot survive the encoding arriving.",
      "",
      "subject.mjs checks the declaration in both directions: once the file exists,",
      'it refuses the sidecar until state is flipped to "written". So this key',
      "cannot rot into a false statement about the tree.",
      "",
      "'legs' is deliberately EMPTY. The driver declares a projection stage IFF the",
      "leg is declared here, so an omitted leg is a stage that never runs and never",
      "reports -- an honest silence. Add a leg only when this subject genuinely",
      "supports it AND its committed golden paths exist; see etc/go/subjects/regcf",
      "for every leg's key schema.",
      "",
      "'checks' floors are 0/0, which makes the corresponding sub-checks report NOT",
      "CHECKED rather than vacuously green. Raise them to MEASURED figures once the",
      "encoding exists -- min_assertions is assertions_total from `l4 run --json`,",
      "not a count of '#ASSERT' strings in the source.",
    ],
    id,
    display_name: env("NEW_NAME"),
    citation: env("NEW_CITATION"),
    source_url: env("NEW_SOURCE_URL"),
    encoding: { state: "unwritten", main: env("NEW_ENC") },
    checks: { min_dated_arms: 0, min_assertions: 0 },
    legs: {},
  }),
);

write(
  "pins.json",
  json({
    _comment: [
      "NOT MEASURED. This file is a record of the `l4` CLI surface the stage table",
      "depends on, recovered by probing a real binary (etc/go/lib/discover.mjs).",
      "`new-subject` cannot produce it: it has no binary and no encoding to probe",
      "against, and a scaffolder that copied another subject's enumerations would",
      "be asserting a measurement it never took.",
      "",
      "p0-preflight compares the pins as SETS and reports BROKEN when they do not",
      "match, so leaving this empty is loud, not silent -- which is the intended",
      "behaviour for a subject whose surface has never been measured.",
      "",
      "To fill it: write the encoding, then follow etc/go/subjects/regcf/pins.json,",
      "whose own _comment records how each value was recovered and on what date.",
    ],
  }),
);

write(
  "known-defects.json",
  json({
    _comment: [
      "NOT MEASURED, and deliberately containing no groups.",
      "",
      "Every entry in this file is a NEGATIVE CONTROL: a defect observed on a stated",
      "date, which a leg then expects to keep reproducing. A negative control that",
      "stops reproducing is itself a finding, so the legs report BROKEN rather than",
      "turning green when an expected defect disappears.",
      "",
      "That machinery only works if every entry was actually observed. `new-subject`",
      "observes nothing, so it writes nothing: known-defects.mjs refuses with 'no",
      "group <name>' for any leg that needs one, which names the gap instead of",
      "hiding it. Predicting a defect here would be exactly the drift this",
      "orchestrator exists to prevent.",
      "",
      "See etc/go/subjects/regcf/known-defects.json for the entry shape and for the",
      "convention that an empty group states its reason.",
    ],
  }),
);

write(
  "NOTES.md",
  `# ${env("NEW_NAME")} — notes

Free-prose idiosyncrasies of this body of law. **No script reads this file**,
which is what makes it the right home for anything that does not fit the
sidecar's schema: quirks of the source text, why a floor is set where it is,
which sections resisted encoding and how that was resolved.

Scaffolded by \`etc/go/go.sh new-subject\`. Nothing below has been established
yet — replace this section as facts arrive, and do not leave a claim here that
the tree does not support.

## Status

The encoding is **not written**. \`subject.json\` says so
(\`encoding.state: "unwritten"\`) and every stage that reads a module will report
SKIPPED naming the file to deposit.

## Source

- Citation: ${env("NEW_CITATION")}
- Retrieved from: ${env("NEW_SOURCE_URL")}

Record here how the text was actually fetched, and anything about the source
that a later reader would otherwise have to rediscover — pagination, a PDF that
is authoritative where the HTML is only a table of contents, an amendment
consolidated in one place but not another.
`,
);

process.stdout.write(`new-subject: wrote ${dir}\n`);
