// A line-level unified diff, dependency-free.
//
// It exists for one caller: when the §5.3 round-trip proof fails, the message has to
// show WHICH bytes of the publisher's form the template no longer reproduces. A boolean
// "differs" would send the reader back to the shell to find out what the tool already
// knew. Documents here are a few hundred lines, so a plain O(n·m) LCS is fast enough and
// is worth far more than a clever algorithm nobody can check.

function lcsTable(a, b) {
  const n = a.length;
  const m = b.length;
  const dp = Array.from({ length: n + 1 }, () => new Uint32Array(m + 1));
  for (let i = n - 1; i >= 0; i--)
    for (let j = m - 1; j >= 0; j--)
      dp[i][j] =
        a[i] === b[j]
          ? dp[i + 1][j + 1] + 1
          : Math.max(dp[i + 1][j], dp[i][j + 1]);
  return dp;
}

/** @returns [{op: " "|"-"|"+", line: string}] */
export function diffLines(a, b) {
  const dp = lcsTable(a, b);
  const out = [];
  let i = 0;
  let j = 0;
  while (i < a.length && j < b.length) {
    if (a[i] === b[j]) out.push({ op: " ", line: a[i++] }), j++;
    else if (dp[i + 1][j] >= dp[i][j + 1]) out.push({ op: "-", line: a[i++] });
    else out.push({ op: "+", line: b[j++] });
  }
  while (i < a.length) out.push({ op: "-", line: a[i++] });
  while (j < b.length) out.push({ op: "+", line: b[j++] });
  return out;
}

/** A unified diff with `context` lines of context, or "" when the texts are equal. */
export function unifiedDiff(fromText, toText, fromName, toName, context = 3) {
  const a = fromText.split("\n");
  const b = toText.split("\n");
  const ops = diffLines(a, b);
  if (!ops.some((o) => o.op !== " ")) return "";

  // Group the changed lines into hunks, keeping `context` unchanged lines around each.
  const keep = new Array(ops.length).fill(false);
  ops.forEach((o, k) => {
    if (o.op === " ") return;
    for (let d = -context; d <= context; d++)
      if (k + d >= 0 && k + d < ops.length) keep[k + d] = true;
  });

  const lines = [`--- ${fromName}`, `+++ ${toName}`];
  let ai = 0;
  let bi = 0;
  let k = 0;
  while (k < ops.length) {
    if (!keep[k]) {
      if (ops[k].op !== "+") ai++;
      if (ops[k].op !== "-") bi++;
      k++;
      continue;
    }
    const startA = ai;
    const startB = bi;
    const body = [];
    while (k < ops.length && keep[k]) {
      const o = ops[k++];
      body.push(o.op + o.line);
      if (o.op !== "+") ai++;
      if (o.op !== "-") bi++;
    }
    lines.push(
      `@@ -${startA + 1},${ai - startA} +${startB + 1},${bi - startB} @@`,
      ...body,
    );
  }
  return lines.join("\n") + "\n";
}
