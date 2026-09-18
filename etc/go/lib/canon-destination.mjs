#!/usr/bin/env node
// WHERE THIS ENCODING IS DESTINED, stated by the pipeline that produced it.
//
//   node etc/go/lib/canon-destination.mjs --subject-path sg/succession \
//        [--row cleanroom-2026-08] [--branch mengwong/drafts] [--json]
//
// Exit: 0 resolved · 1 refused (a destination the rules forbid) · 2 usage
//
// --- why a module and not a sentence in p10 ----------------------------------
//
// `p10-publish` refuses, and will keep refusing until depositing is an HG2 act
// somebody has signed. That is precisely why the destination should be COMPUTED
// rather than described: a refusal that names the exact directory it would have
// written is a refusal the reader can check, and the fence it enforces is then
// already built and already tested on the day the stage stops refusing. The MCP
// leg's loopback fence is the same shape — the one outward-facing write in this
// orchestrator has its guard written before it has its feature.
//
// --- what is RULED, and therefore enforced -----------------------------------
//
//   the repository   `legalese/canon`, ruled R1 2026-08-02. Not configurable.
//   the branch       a DRAFTS shelf. Never `main`. An encoding lands on
//                    somebody's drafts branch and stays there until its
//                    source-terms question is settled; a deposit straight onto
//                    `main` is a larger outward act than the one HG2 was asked
//                    about, and this refuses it rather than trusting the caller
//                    to remember.
//   the layout       subjects/<subject-path>/encodings/<row>/ — canon's ruled
//                    sidecar shape, one level below the subject (Q3).
//
// --- and what is only ADVISORY, with the reason -------------------------------
//
// The path grammar in canon's `docs/directory-conventions.md` (ISO 3166-1 alpha-2
// for the authority tree, `contracts` for the genre tree) is PROPOSED, not
// adopted — that document says so in its own header — and canon's `main` holds
// `western-australia/`, `singapore/` and `european-union/`, which predate it and
// do not conform. Its `mengwong/drafts` branch holds `sg/`, `il/`, `us/` and
// `contracts/`, which do.
//
// So a non-conforming path WARNS and does not fail. A validator that refused
// would be enforcing, from the tools repo, a convention the law repo has not
// adopted — and would reject paths that are correct for the tree as it stands.
// When the conventions land, the warning becomes a refusal in one edit, and the
// warning text is what tells a reader that day is coming.

import { execFileSync } from "node:child_process";

const SLUG = /^[a-z0-9][a-z0-9._-]*$/;

export const CANON_REPO = "legalese/canon";

/**
 * WHOSE DRAFTS SHELF. Derived from the person running the pipeline, never from
 * a name baked into this file.
 *
 * `mengwong/drafts` is where Meng's encodings go; somebody running the same
 * pipeline out of `legalese/l4-plugin` should land on THEIR shelf, not his. A
 * hardcoded default would quietly put every contributor's work on one person's
 * branch, and the failure would look like success.
 *
 * The sources are ordered by how much they actually know, and the one that
 * answered is RECORDED, because they are not equally trustworthy:
 *
 *   gh          `gh api user` — the GitHub identity itself. The branch lives on
 *               a GitHub repo, so this is the only source that is answering the
 *               question that was asked. Needs network and auth.
 *   git-config  `github.user` — set deliberately by someone who meant it.
 *   os-user     `$USER` — a GUESS, and flagged as one everywhere it surfaces.
 *               An OS account name need not be a GitHub login; when it is not,
 *               this invents a shelf belonging to nobody, on a public repo.
 *               Good enough to SHOW a destination, not good enough to push to.
 *
 * `exec` is injectable so the ordering can be tested without a network.
 */
export function defaultExec(cmd, args) {
  return execFileSync(cmd, args, {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
    timeout: 10000,
  }).trim();
}

export function resolveOwner({ env = process.env, exec = defaultExec } = {}) {
  const tried = [];
  const attempt = (source, fn) => {
    try {
      const v = fn();
      if (v && SLUG.test(v.toLowerCase())) return { owner: v, source };
    } catch {
      /* a missing tool is an ordinary outcome, not a failure */
    }
    tried.push(source);
    return null;
  };
  return (
    attempt("gh", () => exec("gh", ["api", "user", "--jq", ".login"])) ??
    attempt("git-config", () =>
      exec("git", ["config", "--get", "github.user"]),
    ) ??
    attempt("os-user", () => env.USER || env.LOGNAME || "") ?? {
      owner: null,
      source: null,
      tried,
    }
  );
}

/** The genre tree's root, per directory-conventions §3. */
const GENRE_ROOT = "contracts";

/**
 * A branch that is a drafts shelf.
 *
 * Both spellings observed in canon today: `mengwong/drafts` and
 * `aswathy/drafts`. `drafts/<something>` is admitted too because it is the
 * obvious other way to write the same intent, and refusing it would send a
 * reader hunting for a rule that is really just a house style.
 */
export function isDraftsBranch(b) {
  return /(^|\/)drafts($|\/)/.test(b);
}

export function validateSubjectPath(p) {
  const warnings = [];
  if (typeof p !== "string" || !p)
    throw new Error("canon.subject_path is required and must be a string");
  if (p.startsWith("/") || p.endsWith("/"))
    throw new Error(
      `canon.subject_path '${p}': no leading or trailing slash — it is a path BELOW subjects/`,
    );
  const parts = p.split("/");
  if (parts.length < 2)
    throw new Error(
      `canon.subject_path '${p}': needs at least a tree and a leaf, e.g. 'us/regcf' or 'contracts/investment/yc-safe-postmoney'`,
    );
  for (const c of parts)
    if (!SLUG.test(c))
      throw new Error(
        `canon.subject_path '${p}': component '${c}' is not an ASCII slug ([a-z0-9][a-z0-9._-]*)`,
      );
  // ADVISORY, for the reason in the header: the conventions are proposed and
  // canon's own main branch does not conform to them.
  if (parts[0] !== GENRE_ROOT && !/^[a-z]{2}$/.test(parts[0]))
    warnings.push(
      `'${parts[0]}' is neither '${GENRE_ROOT}' nor a two-letter jurisdiction code. ` +
        `canon's docs/directory-conventions.md (PROPOSED, not yet adopted) would key the ` +
        `authority tree on ISO 3166-1 alpha-2 — 'au/wa' rather than 'western-australia'. ` +
        `Not an error while that document is proposed and while canon's main branch holds ` +
        `the older spellings.`,
    );
  return { parts, warnings };
}

/**
 * The full destination, or a thrown refusal.
 *
 * `row` defaults to the encoding id, which is not a convenience but an
 * observation: canon's drafts branch already holds
 * `subjects/sg/succession/encodings/cleanroom-2026-08/`, and `cleanroom-2026-08`
 * is exactly this subject's sidecar encoding id. The two vocabularies already
 * agree, so the default keeps them agreeing rather than inventing a mapping.
 */
export function resolveDestination({
  subjectPath,
  row,
  branch,
  env = process.env,
  exec = defaultExec,
} = {}) {
  const { warnings } = validateSubjectPath(subjectPath);
  if (!row || !SLUG.test(row))
    throw new Error(
      `canon row '${row ?? "(none)"}': an encoding row id must be an ASCII slug — it names the OCCASION of the encoding, as the sidecar's encoding id does`,
    );
  // `primary` IS NOT A ROW NAME, and this refusal is the one place that can say
  // so before it reaches a public repository.
  //
  // It is the DRIVER's selector for "the committed encoding", which is a fine
  // run parameter and a terrible directory name: canon's Q3 ruling is that
  // encodings are equal rows and NO ROW IS PRIMARY, so filing one at
  // `encodings/primary/` re-creates the privilege in the law repository — the
  // more durable of the two places, and the one the ruling was about. The
  // committed encoding needs a name that says WHEN and BY WHOM, like every
  // other row canon holds (`legalese-2026-09`, `cleanroom-2026-08`).
  if (row === "primary")
    throw new Error(
      `canon row 'primary' is REFUSED. It is the driver's selector for the committed ` +
        `encoding, not a name for a row in canon — whose Q3 ruling is that encodings are ` +
        `equal rows and no row is primary. Declare the real one in the sidecar as ` +
        `canon.primary_row (e.g. "legalese-2026-08"), naming the occasion the way canon's ` +
        `other rows do.`,
    );
  // Explicit beats environment beats derived. The derived case is the one that
  // matters: it is what makes the same pipeline land a contributor's encoding on
  // THEIR shelf rather than on the shelf of whoever wrote the default.
  let branchSource = "explicit";
  let owner = null;
  let b = branch ?? null;
  if (b === null && env.L4_GO_CANON_BRANCH) {
    b = env.L4_GO_CANON_BRANCH;
    branchSource = "env";
  }
  if (b === null) {
    const r = resolveOwner({ env, exec });
    owner = r.owner;
    branchSource = r.source;
    b = owner ? `${owner}/drafts` : null;
  }
  if (b !== null) {
    if (/^(main|master)$/.test(b))
      throw new Error(
        `canon branch '${b}' is REFUSED. An encoding lands on a drafts shelf and stays there ` +
          `until its source-terms question is settled. Depositing straight onto the default ` +
          `branch is a larger outward act than the one HG2 was asked about, and it is not this ` +
          `pipeline's to take.`,
      );
    if (!isDraftsBranch(b))
      throw new Error(
        `canon branch '${b}' does not look like a drafts shelf. Expected '<who>/drafts' ` +
          `(canon has 'mengwong/drafts' and 'aswathy/drafts') or 'drafts/<what>'. ` +
          `Set L4_GO_CANON_BRANCH, or pass --branch.`,
      );
  }
  // A guessed owner is good enough to SHOW a destination and not good enough to
  // push to. Saying so here is the difference between a reader who checks the
  // branch name and one who assumes the tool knew.
  if (branchSource === "os-user")
    warnings.push(
      `the branch was derived from the OS account name ($USER='${owner}'), which need not be ` +
        `a GitHub login. If it is not, '${b}' is a shelf belonging to nobody on a public repo. ` +
        `Confirm it, or set L4_GO_CANON_BRANCH.`,
    );
  const subjectDir = `subjects/${subjectPath}`;
  return {
    repo: CANON_REPO,
    // null when nothing could name an owner. That is the honest value, not a
    // defect: whose shelf an encoding lands on is a fact about who is
    // depositing, and a pipeline that cannot tell must say so rather than
    // choose for them.
    branch: b,
    branch_source: b === null ? null : branchSource,
    owner,
    subject_dir: subjectDir,
    encoding_dir: `${subjectDir}/encodings/${row}`,
    row,
    warnings,
  };
}

/** One line for a refusal message or a report row. */
export function describe(d) {
  const br =
    d.branch ??
    "<USERNAME>/drafts — no owner could be resolved; set L4_GO_CANON_BRANCH";
  const via = d.branch_source ? ` (branch via ${d.branch_source})` : "";
  return `${d.repo} @ ${br} : ${d.encoding_dir}/${via}`;
}

// ---------------------------------------------------------------- CLI --------
if (import.meta.url === `file://${process.argv[1]}`) {
  const argv = process.argv.slice(2);
  const get = (k) => {
    const i = argv.indexOf(`--${k}`);
    return i >= 0 ? argv[i + 1] : undefined;
  };
  if (!get("subject-path")) {
    process.stderr.write(
      "usage: canon-destination.mjs --subject-path P --row R [--branch B] [--json]\n",
    );
    process.exit(2);
  }
  let d;
  try {
    d = resolveDestination({
      subjectPath: get("subject-path"),
      row: get("row"),
      branch: get("branch"),
    });
  } catch (e) {
    process.stderr.write(`canon-destination: ${e.message}\n`);
    process.exit(1);
  }
  if (argv.includes("--json")) {
    process.stdout.write(JSON.stringify(d, null, 2) + "\n");
  } else {
    process.stdout.write(describe(d) + "\n");
    for (const w of d.warnings) process.stdout.write(`  note: ${w}\n`);
  }
}
