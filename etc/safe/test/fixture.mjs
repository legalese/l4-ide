// Locating a subject to test against, and building a WRITABLE copy of it.
//
// The canon checkout is read-only as far as these tools are concerned — make-templates
// writes into <subject>/templates, and a test must not leave files in someone's canon
// working tree. So every test that needs a subject copies the four inputs (source/md,
// source/docx, source/footers.json, templates/holes.json) into a temp directory and
// symlinks the encoding row, then works there.
//
// CLAUDE.md §1.2: canon is evidence when it happens to be checked out, never a
// dependency. With no subject, the tests that need one skip and say why.

import {
  cpSync,
  existsSync,
  mkdirSync,
  readdirSync,
  symlinkSync,
} from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, "..", "..", "..");

/** @returns an absolute path, or null with the reason on `.reason`. */
export function locateSubject() {
  // A checkout of legalese/canon may sit beside this repo, or beside the l4wt
  // directory that holds this worktree (CLAUDE.md §2: work happens in
  // ~/src/legalese/l4wt/<name>, and canon is ~/src/legalese/canon).
  const leaf = join("subjects", "contracts", "investment", "yc-safe-postmoney");
  const candidates = [
    process.env.SAFE_SUBJECT,
    resolve(REPO, "..", "canon", leaf),
    resolve(REPO, "..", "..", "canon", leaf),
  ].filter(Boolean);
  for (const c of candidates)
    if (
      existsSync(join(c, "source", "md")) &&
      existsSync(join(c, "templates", "holes.json"))
    )
      return c;
  return null;
}

export const NO_SUBJECT =
  "no YC SAFE subject directory: set SAFE_SUBJECT=<dir>, or check out legalese/canon " +
  "beside this repo (or beside its l4wt parent) so that " +
  "canon/subjects/contracts/investment/yc-safe-postmoney exists with source/md and " +
  "templates/holes.json";

/** Copy the read-only inputs into `dir` and return it, ready for make-templates. */
export function buildScratchSubject(src, dir) {
  mkdirSync(join(dir, "source"), { recursive: true });
  mkdirSync(join(dir, "templates"), { recursive: true });
  mkdirSync(join(dir, "encodings"), { recursive: true });
  cpSync(join(src, "source", "md"), join(dir, "source", "md"), {
    recursive: true,
  });
  if (existsSync(join(src, "source", "docx")))
    cpSync(join(src, "source", "docx"), join(dir, "source", "docx"), {
      recursive: true,
    });
  cpSync(
    join(src, "source", "footers.json"),
    join(dir, "source", "footers.json"),
  );
  cpSync(
    join(src, "templates", "holes.json"),
    join(dir, "templates", "holes.json"),
  );
  for (const row of readdirSync(join(src, "encodings")))
    symlinkSync(join(src, "encodings", row), join(dir, "encodings", row));
  return dir;
}

export const GEN = join(HERE, "..", "gen.mjs");
export const MAKE_TEMPLATES = join(HERE, "..", "make-templates.mjs");
export const CHECK_TEMPLATES = join(HERE, "..", "check-templates.mjs");
export const CHECK_ENCODING = join(HERE, "..", "check-encoding.mjs");
