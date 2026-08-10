#!/usr/bin/env node
// Assign every file in `git diff --name-only main...unstable` to exactly one theme.
// First matching rule wins. Goldens inherit the theme of their source .l4.
import { execFileSync } from 'node:child_process'
import { writeFileSync, mkdirSync } from 'node:fs'

const git = (...a) => execFileSync('git', a, { encoding: 'utf8', maxBuffer: 1 << 28 })
const files = git('diff', '--name-only', 'origin/main...origin/unstable').trim().split('\n')

// ---------------------------------------------------------------- theme rules
// [theme, predicate]  — evaluated in order.
const re = (p) => (f) => p.test(f)

const RULES = [
  // ---- infrastructure / meta -------------------------------------------------
  ['ci-build', re(/^\.github\/|^\.husky\/|^package(-lock)?\.json$|^turbo\.json$/)],
  [
    'agent-tooling',
    re(
      /^\.claude\/skills\/writing-l4-rules\/|^(AGENTS|CLAUDE|BRANCH|TODO|README|REVIEW-PART1-CODEBASE-MAP|L4-LINT-DESIGN|BUILD-SPEC-dmnmd-to-l4)\.md$|^build-dmnmd-to-l4\.workflow\.js$/,
    ),
  ],

  // ---- prose -----------------------------------------------------------------
  ['papers', re(/^paper\//)],
  ['specs', re(/^specs\//)],
  ['docs', re(/^doc\//)],

  // ---- whole packages --------------------------------------------------------
  ['mlir', re(/^jl4-mlir\//)],
  ['proleg', re(/^jl4-proleg\/|^cabal\.project$/)],
  ['actus-archive', re(/^jl4-actus-analyzer\//)],
  ['wizards', re(/^ts-apps\/(regcf|housing)-wizard\/|^nix\/(regcf-wizard|jl4-web|jl4-service)/)],
  ['go-pipeline', re(/^etc\/go\/|^\.claude\/skills\/running-the-l4-pipeline\//)],
  ['experiments', re(/^jl4\/experiments\//)],

  // ---- export backends -------------------------------------------------------
  [
    'dmn-export',
    re(
      /^jl4-core\/src\/L4\/Dmn\/|^jl4\/tests\/DmnExport\.hs$|^jl4\/examples\/dmn\/|^etc\/(kie|camunda)-dmn-check\/|^etc\/validate-dmn\.mjs$|^jl4-core\/src\/L4\/Interchange\/Fidelity\.hs$/,
    ),
  ],
  [
    'bpmn-export',
    re(
      /^jl4-core\/src\/L4\/Bpmn\/|^jl4\/tests\/BpmnExport\.hs$|^jl4\/examples\/bpmn\/|^etc\/(check-)?bpmn|^etc\/validate-bpmn\.mjs$|^etc\/kie\//,
    ),
  ],
  [
    'openfisca-export',
    re(/^jl4-core\/src\/L4\/OpenFisca\/|^jl4\/examples\/openfisca\/|^jl4\/app\/L4\/Cli\/OpenFisca\.hs$/),
  ],

  // ---- visualiser ------------------------------------------------------------
  [
    'ladder-viz',
    re(
      /^ts-shared\/(ladder-core|ladder-svg|l4-ladder-visualizer|viz-expr|boolean-analysis|l4-highlight|jl4-client-rpc)\/|^jl4-core\/src\/L4\/(Viz\/|StateGraph\.hs)|^jl4-core\/test\/StateGraphSpec\.hs$|^jl4\/tests\/Viz|^jl4\/examples\/state-graphs\/|^jl4-lsp\/src\/LSP\/L4\/Viz\//,
    ),
  ],

  // ---- service + CLI ---------------------------------------------------------
  [
    'service-cli',
    re(
      /^jl4-service\/|^jl4-query-plan\/|^jl4\/app\/|^jl4-core\/src\/L4\/(Export|Export\/Document|FunctionSchema|JsonSchema|API)\.hs$|^jl4-core\/src\/L4\/API\//,
    ),
  ],
  ['lsp', re(/^jl4-lsp\//)],

  // ---- language core, split by concern --------------------------------------
  [
    'lang-printer',
    re(
      /^jl4-core\/src\/L4\/Print|^jl4-core\/src\/L4\/Parser\/Anno\.hs$|^jl4-core\/test\/(FormatFidelity|PrintRoundtrip|EventExactPrint|BulletParser|RefAnnotation|DirectiveAmbiguity)Spec\.hs$/,
    ),
  ],
  [
    'lang-temporal-ledger',
    re(
      /^jl4-core\/src\/L4\/(EvaluateLazy|TemporalContext)|^jl4-core\/src\/L4\/Evaluate\/|^jl4-core\/test\/(Bitemporal|Ledger|RecordLedger|M4PartyLedger|M45Read|M5Deontic|TemporalContext|Trace)\w*Spec\.hs$/,
    ),
  ],
  [
    'lang-imports-stdlib',
    re(
      /^jl4-core\/libraries\/|^jl4-core\/src\/L4\/Import\/|^jl4-core\/test\/(ImportResolution|ResolutionCascade)Spec\.hs$/,
    ),
  ],
  [
    'lang-typecheck',
    re(
      /^jl4-core\/src\/L4\/(TypeCheck|Mixfix|Names|Desugar|Diagnostic|Syntax|Lexer|Parser)/,
    ),
  ],
  ['lang-typecheck', re(/^jl4-core\/test\/(Unify|MixfixParser|PatternMatchParser|EdgeCrash)Spec\.hs$/)],
  ['lang-nlg', re(/^jl4-core\/src\/L4\/Nlg\.hs$/)],

  // ---- corpora ---------------------------------------------------------------
  ['corpus-regcf', re(/^jl4\/examples\/legal\/regcf/)],
  ['corpus-bna-charities', re(/^jl4\/examples\/legal\/(bna|charities-cleanroom)/)],
  ['corpus-legal-other', re(/^jl4\/examples\/legal\//)],
  ['corpus-notok', re(/^jl4\/examples\/not-ok\//)],
  ['tests-cli', re(/^jl4\/tests-cli\//)],
]

// ok/ corpus keyword buckets -> theme (checked against the .l4 stem)
const OK_BUCKETS = [
  [/^(temporal|ledger|bitemporal|record-|recall|attest|deontic-seq|state-ledger|party-ledger|trace)/, 'lang-temporal-ledger'],
  [/^(set-operators|setof|union|intersect)/, 'lang-sets'],
  [/^(fixity|infix|mixfix|bullet|pattern-match|clitic)/, 'lang-typecheck'],
  [/^(section-scoping|section-lexical|typo-binder|unify|overload|ambigu|shadow|resolution)/, 'lang-typecheck'],
  [/^(ymd|daydate|date|excel-date|actus-schedule|hierarchy|negation-as-failure|prelude|maybe|maximum|minimum)/, 'lang-imports-stdlib'],
  [/^(format|exactprint|print|roundtrip|columnar|ditto|garden-path)/, 'lang-printer'],
  [/^(typically|question-order|inert|ladder|viz|guarded)/, 'ladder-viz'],
  [/^(dmn|feel)/, 'dmn-export'],
  [/^(bpmn)/, 'bpmn-export'],
  [/^(openfisca)/, 'openfisca-export'],
  [/^(nlg)/, 'lang-nlg'],
]

// --------------------------------------------------------------- assignment
const assign = new Map()
const okTheme = new Map() // stem -> theme, so goldens can follow their source

function themeForOkStem(stem) {
  for (const [rx, t] of OK_BUCKETS) if (rx.test(stem)) return t
  return null
}

const unmatched = []
for (const f of files) {
  // goldens & sidecars: defer, resolved in pass 2
  let m = f.match(/^(.*)\/tests\/([^/]+?)\.(golden|ep\.golden|nlg\.golden|schema\.golden)$/)
  if (m) continue

  let hit = null
  for (const [theme, pred] of RULES) {
    if (pred(f)) {
      hit = theme
      break
    }
  }
  if (!hit && /^jl4\/examples\/ok\//.test(f)) {
    const stem = f.replace(/^jl4\/examples\/ok\//, '').replace(/\.[^/.]+$/, '')
    hit = themeForOkStem(stem.split('/')[0])
  }
  if (hit) {
    assign.set(f, hit)
    const om = f.match(/^jl4\/examples\/ok\/([^/]+)\.l4$/)
    if (om) okTheme.set(om[1], hit)
  } else unmatched.push(f)
}

// pass 2: goldens inherit from their source file
const orphanGoldens = []
for (const f of files) {
  const m = f.match(/^(.*)\/tests\/([^/]+?)\.(?:ep\.|nlg\.|schema\.)?golden$/)
  if (!m) continue
  const [, dir, stem] = m
  const src = `${dir}/${stem}.l4`
  if (assign.has(src)) assign.set(f, assign.get(src))
  else if (okTheme.has(stem)) assign.set(f, okTheme.get(stem))
  else orphanGoldens.push(f)
}

// ------------------------------------------------------------------ report
const counts = {}
for (const t of assign.values()) counts[t] = (counts[t] || 0) + 1
mkdirSync('.pr-split/analysis', { recursive: true })
writeFileSync(
  '.pr-split/analysis/assignment.tsv',
  [...assign].map(([f, t]) => `${t}\t${f}`).join('\n') + '\n',
)
writeFileSync('.pr-split/analysis/unmatched.txt', unmatched.join('\n') + '\n')
writeFileSync('.pr-split/analysis/orphan-goldens.txt', orphanGoldens.join('\n') + '\n')

console.log('total changed files:', files.length)
console.log('assigned:', assign.size, ' unmatched:', unmatched.length, ' orphan goldens:', orphanGoldens.length)
console.log('\n--- per theme ---')
for (const [t, n] of Object.entries(counts).sort((a, b) => b[1] - a[1])) console.log(String(n).padStart(5), t)
console.log('\n--- unmatched sample (first 60) ---')
console.log(unmatched.slice(0, 60).join('\n'))
console.log('\n--- orphan goldens sample (first 25) ---')
console.log(orphanGoldens.slice(0, 25).join('\n'))
