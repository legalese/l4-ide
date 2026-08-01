#!/usr/bin/env node
// Toolchain detection. Every miss produces a NAMED reason, never silence.
//
// House convention (etc/kie-dmn-check/run.sh): skip is not pass, and a missing
// toolchain is forgiven locally but fatal in CI. This module supplies the
// named reason; go.sh decides whether L4_GO_REQUIRED=1 turns it into exit 5.
//
// Usage:
//   node etc/go/lib/probe.mjs --json            # probe everything, emit JSON
//   node etc/go/lib/probe.mjs --need mvn        # exit 0 if present, 1 if not
//
// Nothing here installs anything, and nothing here touches the tree.

import { execFileSync, spawnSync } from "node:child_process";
import { existsSync } from "node:fs";

const which = (cmd) => {
  const r = spawnSync("command", ["-v", cmd], {
    shell: true,
    encoding: "utf8",
  });
  return r.status === 0 ? r.stdout.trim().split("\n")[0] : null;
};

const version = (cmd, args) => {
  try {
    return execFileSync(cmd, args, {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    })
      .trim()
      .split("\n")[0];
  } catch {
    return null;
  }
};

/** Each probe answers: present? where? which version? and, if absent, WHY that matters. */
export const PROBES = {
  node: () => {
    const p = which("node");
    return {
      present: !!p,
      path: p,
      version: process.version,
      needed_by: ["every .mjs checker"],
    };
  },
  npx: () => {
    const p = which("npx");
    return {
      present: !!p,
      path: p,
      needed_by: ["p7-dmn (dmn-moddle)", "p7-bpmn (bpmn-moddle)"],
    };
  },
  npm: () => {
    const p = which("npm");
    return {
      present: !!p,
      path: p,
      needed_by: ["p7-ladder (npm run demo:regcf)"],
    };
  },
  mvn: () => {
    const p = which("mvn");
    return {
      present: !!p,
      path: p,
      version: p ? version("mvn", ["-v"]) : null,
      needed_by: ["p7-bpmn (kie baseline)"],
    };
  },
  dot: () => {
    const p = which("dot");
    return {
      present: !!p,
      path: p,
      version: p ? version("dot", ["-V"]) : null,
      needed_by: ["p7-lts (SVG rendering; DOT emission does not need it)"],
    };
  },
  java17: () => {
    const home =
      process.env.KIE_CHECK_JAVA_HOME || process.env.JAVA_HOME_17_X64 || null;
    return {
      present: !!(home && existsSync(home)),
      path: home,
      needed_by: ["kie-dmn-check (not reachable at G1: no corpus cases file)"],
    };
  },
  java21: () => {
    const home =
      process.env.CAMUNDA_CHECK_JAVA_HOME ||
      process.env.JAVA_HOME_21_X64 ||
      null;
    return {
      present: !!(home && existsSync(home)),
      path: home,
      needed_by: [
        "camunda-dmn-check (not reachable at G1: no corpus cases file)",
      ],
    };
  },
  jl4_lsp: () => {
    const p = process.env.JL4_LSP_CMD || which("jl4-lsp");
    return {
      present: !!(p && (existsSync(p) || which(p))),
      path: p,
      needed_by: ["p7-ladder (the ladder generator drives the LSP)"],
    };
  },
  jl4_service: () => {
    const url = process.env.JL4_GO_SERVICE_URL || "";
    return {
      present: !!url,
      path: url || null,
      needed_by: ["p7-mcp (deployment); loopback only, see p7-mcp.sh"],
    };
  },
  git: () => {
    const p = which("git");
    return {
      present: !!p,
      path: p,
      needed_by: ["p0 (HEAD + tree state)", "p7-ladder (figure drift oracle)"],
    };
  },
};

export function probeAll() {
  const out = {};
  for (const [k, fn] of Object.entries(PROBES)) {
    try {
      out[k] = fn();
    } catch (e) {
      out[k] = { present: false, error: String(e), needed_by: [] };
    }
  }
  return out;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const args = process.argv.slice(2);
  const needIdx = args.indexOf("--need");
  if (needIdx >= 0) {
    const key = args[needIdx + 1];
    const fn = PROBES[key];
    if (!fn) {
      process.stderr.write(
        `probe.mjs: no probe named '${key}'; known: ${Object.keys(PROBES).join(", ")}\n`,
      );
      process.exit(2);
    }
    const r = fn();
    if (!r.present) {
      process.stderr.write(
        `probe.mjs: '${key}' is absent — needed by ${(r.needed_by || []).join("; ") || "(unstated)"}\n`,
      );
      process.exit(1);
    }
    process.stdout.write(`${r.path ?? "present"}\n`);
    process.exit(0);
  }
  process.stdout.write(JSON.stringify(probeAll(), null, 2) + "\n");
}
