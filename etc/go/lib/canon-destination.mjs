#!/usr/bin/env node
// WHERE THIS ENCODING IS DESTINED, stated by the pipeline that produced it.
//
//   node etc/go/lib/canon-destination.mjs --subject-path sg/succession \
//        [--row cleanroom-2026-08] [--branch <branch>] [--json]
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
//   the branch       `main`, ruled 2026-09-26: members of the `legalese`
//                    GitHub organisation commit straight to canon's `main`.
//                    `--branch` or L4_GO_CANON_BRANCH names another — a fork's
//                    branch, for a contributor outside Legalese, who then opens
//                    a pull request. Depositing is still HG2's either way.
//   the layout       subjects/<subject-path>/encodings/<row>/ — canon's ruled
//                    sidecar shape, one level below the subject (Q3).
//
// --- and what is only ADVISORY, with the reason -------------------------------
//
// canon's `docs/directory-conventions.md` (ISO 3166-1 alpha-2 for the authority
// tree, `contracts` for the genre tree) was ruled onto `main` with the ISO
// spelling on 2026-09-26 (legalese/canon#3). A non-conforming first component
// still WARNS rather than fails, because canon already holds a `doctrine/` tree
// that the conventions do not mention; refusing wants a ruling on that tree
// first.

const SLUG = /^[a-z0-9][a-z0-9._-]*$/;

export const CANON_REPO = "legalese/canon";

/** The genre tree's root, per directory-conventions §3. */
const GENRE_ROOT = "contracts";

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
  // ADVISORY, for the reason in the header: canon holds a `doctrine/` tree the
  // conventions do not cover, so a refusal here would outrun the rulings.
  if (parts[0] !== GENRE_ROOT && !/^[a-z]{2}$/.test(parts[0]))
    warnings.push(
      `'${parts[0]}' is neither '${GENRE_ROOT}' nor a two-letter jurisdiction code. ` +
        `canon's docs/directory-conventions.md, ruled onto main on 2026-09-26 with the ISO ` +
        `spelling, keys the authority tree on ISO 3166-1 alpha-2 — 'au/wa' rather than ` +
        `'western-australia'.`,
    );
  return { parts, warnings };
}

/**
 * The full destination, or a thrown refusal.
 *
 * `row` defaults to the encoding id, which is not a convenience but an
 * observation: canon already holds
 * `subjects/sg/succession/encodings/cleanroom-2026-08/`, and `cleanroom-2026-08`
 * is exactly this subject's sidecar encoding id. The two vocabularies already
 * agree, so the default keeps them agreeing rather than inventing a mapping.
 */
export function resolveDestination({
  subjectPath,
  row,
  branch,
  env = process.env,
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
  // Explicit beats environment beats the ruled default.
  let branchSource = "explicit";
  let b = branch ?? null;
  if (b === null && env.L4_GO_CANON_BRANCH) {
    b = env.L4_GO_CANON_BRANCH;
    branchSource = "env";
  }
  if (b === null) {
    b = "main";
    branchSource = "default";
  }
  const subjectDir = `subjects/${subjectPath}`;
  return {
    repo: CANON_REPO,
    branch: b,
    branch_source: branchSource,
    subject_dir: subjectDir,
    encoding_dir: `${subjectDir}/encodings/${row}`,
    row,
    warnings,
  };
}

/** One line for a refusal message or a report row. */
export function describe(d) {
  return `${d.repo} @ ${d.branch} : ${d.encoding_dir}/ (branch via ${d.branch_source})`;
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
