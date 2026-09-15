#!/usr/bin/env node
// Recover the primary evidence behind results.json from the Claude Code
// workflow transcripts that produced it, and write it under transcripts/.
//
// The 48 readers and 4 judges of the 2026-09-16 run were subagents of one
// Claude Code workflow. Each subagent's transcript is a JSONL file under
//   ~/.claude/projects/<project-slug>/<session-uuid>/subagents/workflows/<wf>/
// and that directory's journal.jsonl labels every agent
// (`reader:<contract>:<artifact>:<model><repeat>`, `judge:<contract>`).
//
// Usage:
//   node etc/lts-reader-proxy/extract-transcripts.mjs <workflow-dir>
//   npx prettier@3.4.2 --write etc/lts-reader-proxy/transcripts   # CI runs format:check on .
//
// It writes, under etc/lts-reader-proxy/transcripts/:
//   prompts/<contract>.<artifact>.txt   the reader prompt, verbatim (asserted
//                                        byte-identical across the four readings
//                                        of a cell)
//   readings.json                       48 rows: cell, model id, timestamps, the
//                                        reader's text and its StructuredOutput
//                                        answers a1..a5, verbatim
//   judge/<contract>.prompt.txt         the judge prompt, verbatim (truth.json
//                                        plus the 12 readers' answers)
//   judge/<contract>.output.json        the judge's StructuredOutput, verbatim
//   judge.json                          judge model id and timestamps per contract
//
// and then checks, exiting non-zero on any mismatch, that
//   (1) every reader used no tool other than StructuredOutput;
//   (2) the answers the judge was shown are the answers the readers gave;
//   (3) results.json is exactly the judges' output (scores and rationale).
//
// The transcripts live in a per-user directory and are not committed; this
// script is committed so the derivation of transcripts/ is on record.

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createHash } from "node:crypto";

const here = dirname(fileURLToPath(import.meta.url));
const wf = process.argv[2];
if (!wf) {
  console.error("usage: extract-transcripts.mjs <workflow-dir>");
  process.exit(2);
}
const outDir = join(here, "transcripts");
mkdirSync(join(outDir, "prompts"), { recursive: true });
mkdirSync(join(outDir, "judge"), { recursive: true });

const jsonl = (p) =>
  readFileSync(p, "utf8")
    .split("\n")
    .filter(Boolean)
    .map((l) => JSON.parse(l));

const journal = jsonl(join(wf, "journal.jsonl"));
const agents = journal.filter((r) => r.type === "started");
const readerRe = /^reader:([^:]+):([ABC]):(haiku|sonnet)([01])$/;
const judgeRe = /^judge:([^:]+)$/;

const sha = (s) => createHash("sha256").update(s).digest("hex");

function transcript(agentId) {
  const p = join(wf, `agent-${agentId}.jsonl`);
  const rows = jsonl(p);
  const firstUser = rows.find(
    (r) => r.type === "user" && typeof r.message?.content === "string",
  );
  const assistants = rows.filter((r) => r.type === "assistant");
  const blocks = assistants.flatMap((r) => r.message.content);
  const models = [...new Set(assistants.map((r) => r.message.model))];
  const toolUses = blocks.filter((b) => b.type === "tool_use");
  const text = blocks
    .filter((b) => b.type === "text")
    .map((b) => b.text)
    .join("\n");
  // A reader whose first StructuredOutput failed schema validation (the
  // harness replies "Output does not match required schema") tried again; the
  // last attempt is the one that was accepted and handed to the judge.
  const attempts = toolUses.filter((b) => b.name === "StructuredOutput");
  const structured = attempts.at(-1)?.input;
  return {
    prompt: firstUser.message.content,
    startedAt: firstUser.timestamp,
    answeredAt: assistants.at(-1)?.timestamp,
    models,
    version: [...new Set(assistants.map((r) => r.version))],
    toolNames: [...new Set(toolUses.map((b) => b.name))],
    thinkingBlocks: blocks.filter((b) => b.type === "thinking").length,
    thinkingRedacted: blocks
      .filter((b) => b.type === "thinking")
      .every((b) => !b.thinking),
    structuredAttempts: attempts.length,
    rejectedAttempts: attempts.slice(0, -1).map((b) => b.input),
    text,
    structured,
    usage: assistants.at(-1)?.message?.usage,
  };
}

let failures = 0;
const fail = (m) => {
  failures++;
  console.error("MISMATCH: " + m);
};

// ---- readers ---------------------------------------------------------------
const readings = [];
const promptsByCell = new Map();
for (const a of agents) {
  const m = a.label.match(readerRe);
  if (!m) continue;
  const [, contract, artifact, model, repeat] = m;
  const t = transcript(a.agentId);
  const cell = `${contract}.${artifact}`;
  const h = sha(t.prompt);
  if (!promptsByCell.has(cell)) {
    promptsByCell.set(cell, h);
    writeFileSync(join(outDir, "prompts", `${cell}.txt`), t.prompt);
  } else if (promptsByCell.get(cell) !== h) {
    fail(`prompt differs within cell ${cell} (${a.label})`);
  }
  const extraTools = t.toolNames.filter((n) => n !== "StructuredOutput");
  if (extraTools.length) fail(`${a.label} used tools: ${extraTools.join(",")}`);
  if (t.models.length !== 1) fail(`${a.label} has models ${t.models}`);
  readings.push({
    contract,
    artifact,
    model,
    repeat: Number(repeat),
    model_id: t.models[0],
    harness: `claude-code ${t.version.join(",")} (workflow subagent; the harness system prompt is not in the transcript)`,
    agent_id: a.agentId,
    prompt_file: `prompts/${cell}.txt`,
    prompt_sha256: h,
    started_at: t.startedAt,
    answered_at: t.answeredAt,
    tools_used: t.toolNames,
    thinking_blocks: t.thinkingBlocks,
    thinking_redacted_in_transcript: t.thinkingRedacted,
    usage: t.usage,
    answer_text: t.text,
    structured_output_attempts: t.structuredAttempts,
    rejected_attempts: t.rejectedAttempts,
    answers: t.structured,
  });
}
readings.sort(
  (x, y) =>
    x.contract.localeCompare(y.contract) ||
    x.artifact.localeCompare(y.artifact) ||
    x.model.localeCompare(y.model) ||
    x.repeat - y.repeat,
);
if (readings.length !== 48)
  fail(`expected 48 readers, found ${readings.length}`);
writeFileSync(
  join(outDir, "readings.json"),
  JSON.stringify(readings, null, 2) + "\n",
);

// ---- judges ----------------------------------------------------------------
const judges = {};
const judged = [];
for (const a of agents) {
  const m = a.label.match(judgeRe);
  if (!m) continue;
  const contract = m[1];
  if (!readings.some((r) => r.contract === contract)) continue; // e.g. judge:render, another track
  const t = transcript(a.agentId);
  writeFileSync(join(outDir, "judge", `${contract}.prompt.txt`), t.prompt);
  writeFileSync(
    join(outDir, "judge", `${contract}.output.json`),
    JSON.stringify(t.structured, null, 2) + "\n",
  );
  judges[contract] = {
    model_id: t.models[0],
    harness: `claude-code ${t.version.join(",")} (workflow subagent; the harness system prompt is not in the transcript)`,
    agent_id: a.agentId,
    prompt_file: `judge/${contract}.prompt.txt`,
    prompt_sha256: sha(t.prompt),
    output_file: `judge/${contract}.output.json`,
    started_at: t.startedAt,
    answered_at: t.answeredAt,
    tools_used: t.toolNames,
    thinking_blocks: t.thinkingBlocks,
    thinking_redacted_in_transcript: t.thinkingRedacted,
  };
  // (2) the answers the judge saw are the readers' answers
  const head = t.prompt.indexOf("Reader answers");
  const start = t.prompt.indexOf("[", head);
  const end = t.prompt.indexOf("\nScore each answer", start);
  const shown = JSON.parse(t.prompt.slice(start, end));
  for (const s of shown) {
    const r = readings.find(
      (x) =>
        x.contract === contract &&
        x.artifact === s.artifact &&
        x.model === s.model &&
        x.repeat === s.repeat,
    );
    if (!r) {
      fail(
        `judge:${contract} saw a reading not in the readers: ${s.artifact}/${s.model}/${s.repeat}`,
      );
      continue;
    }
    if (JSON.stringify(r.answers) !== JSON.stringify(s.answers))
      fail(
        `judge:${contract} ${s.artifact}/${s.model}/${s.repeat}: shown answers != reader's StructuredOutput`,
      );
  }
  for (const row of t.structured.rows) judged.push({ contract, ...row });
}
writeFileSync(
  join(outDir, "judge.json"),
  JSON.stringify(judges, null, 2) + "\n",
);

// (3) results.json is the judges' output
const results = JSON.parse(readFileSync(join(here, "results.json"), "utf8"));
if (results.length !== judged.length)
  fail(
    `results.json has ${results.length} rows, judges emitted ${judged.length}`,
  );
for (const r of results) {
  const j = judged.find(
    (x) =>
      x.contract === r.contract &&
      x.artifact === r.artifact &&
      x.model === r.model &&
      x.repeat === r.repeat,
  );
  if (!j) {
    fail(
      `results.json row ${r.contract}/${r.artifact}/${r.model}/${r.repeat} has no judge row`,
    );
    continue;
  }
  if (JSON.stringify(j.scores) !== JSON.stringify(r.scores))
    fail(`scores differ at ${r.contract}/${r.artifact}/${r.model}/${r.repeat}`);
  if (j.rationale !== r.rationale)
    fail(
      `rationale differs at ${r.contract}/${r.artifact}/${r.model}/${r.repeat}`,
    );
}

const ids = {};
for (const r of readings) ids[r.model] = r.model_id;
console.log(
  `readers: ${readings.length}; prompts: ${promptsByCell.size} cells; judges: ${Object.keys(judges).length}`,
);
console.log(
  `reader model ids: ${JSON.stringify(ids)}; judge model ids: ${JSON.stringify([...new Set(Object.values(judges).map((j) => j.model_id))])}`,
);
console.log(
  failures
    ? `${failures} mismatch(es)`
    : "results.json == judge output; judge input == reader output; no reader used a tool",
);
process.exit(failures ? 1 : 0);
