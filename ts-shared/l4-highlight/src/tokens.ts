/**
 * L4 token definitions — single source of truth for the TypeScript side.
 *
 * Canonical source: jl4-core/src/L4/Lexer.hs
 * Keep this file in sync when keywords or directives change in the Lexer.
 */

/**
 * Token categories, aligned with the Lexer's TokenCategory / LSP SemanticTokenTypes.
 *
 *   keyword    → CKeyword    → LSP Keyword
 *   directive  → CDirective  → LSP Macro
 *   annotation → CAnnotation → LSP Decorator
 *   comment    → CComment    → LSP Comment
 *   string     → CStringLit  → LSP String
 *   number     → CNumberLit  → LSP Number
 *   operator   → COperator   → LSP Operator
 *   symbol     → CSymbol     → LSP Operator
 *   variable   → CIdentifier (backtick-quoted)  → LSP Variable
 *   identifier → CIdentifier (regular, context may override to Type/Function/etc.)
 */
export type L4TokenType =
  | 'keyword'
  | 'directive'
  | 'annotation'
  | 'comment'
  | 'string'
  | 'number'
  | 'operator'
  | 'symbol'
  | 'variable'
  | 'identifier'

/**
 * Complete keyword list from jl4-core/src/L4/Lexer.hs `keywords` map.
 */
export const L4_KEYWORDS: ReadonlySet<string> = new Set([
  'A',
  'ABOVE',
  'AFTER',
  'AKA',
  'ALL',
  'AN',
  'AND',
  'AS',
  'ASSUME',
  'AT',
  'ATTEST',
  'BE',
  'BECAUSE',
  'BEFORE',
  'BELOW',
  'BRANCH',
  'BREACH',
  'BY',
  'COMMIT',
  'CONCAT',
  'CONSIDER',
  'DECIDE',
  'DECLARE',
  'DIVIDED',
  'DO',
  'DOES',
  'ELSE',
  'ENV',
  'EQUALS',
  'EVERY',
  'EXACTLY',
  'FETCH',
  'FOLLOWED',
  'FOR',
  'FROM',
  'FUNCTION',
  'GIVEN',
  'GIVES',
  'GIVETH',
  'GREATER',
  'HAS',
  'HAVE',
  'HENCE',
  'IF',
  'IMPLIES',
  'IMPORT',
  'IN',
  'IS',
  'LEAST',
  'LESS',
  'LEST',
  'LET',
  'LIST',
  'MAY',
  'MEAN',
  'MEANS',
  'MINUS',
  'MODULO',
  'MOST',
  'MUST',
  'NOT',
  'OF',
  'OFFICIAL',
  'ONCE',
  'ONE',
  'OR',
  'OTHERWISE',
  'PARTY',
  'PLUS',
  'POST',
  'PROVIDED',
  'RAND',
  'RECALL',
  'RECORD',
  'REFUSE',
  'REFUSED',
  'ROR',
  'SHANT',
  'SOME',
  'STARTING',
  'THAN',
  'THE',
  'THEN',
  'TIMES',
  'TO',
  'TYPE',
  'TYPICALLY',
  'UNLESS',
  'UPON',
  'WHEN',
  'WHERE',
  'WHO',
  'WHOSE',
  'WITH',
  'WITHIN',
  'YIELD',
])

/**
 * Directive names (without the leading #).
 * From jl4-core/src/L4/Lexer.hs `directives` map.
 */
export const L4_DIRECTIVES: ReadonlySet<string> = new Set([
  'EVAL',
  'EVALTRACE',
  'CHECK',
  'TRACE',
  'ASSERT',
])

/**
 * Operator symbols from jl4-core/src/L4/Lexer.hs `operators` map.
 */
export const L4_OPERATORS: ReadonlySet<string> = new Set([
  '*',
  '+',
  '-',
  '>=',
  '<=',
  '>',
  '<',
  '=',
  '==',
  '!=',
  '&&',
  '||',
  '=>',
  '/',
])

/**
 * Symbols that the Lexer's `symbols` map makes a CSymbol (LSP Operator) and
 * that the colorizers do not reach through an operator or identifier pattern.
 *
 * `_` is the wildcard of a norm-log read pattern, as in
 * `OUTSTANDING (PARTY patron MUST return _)` (jl4-core/src/L4/Lexer.hs,
 * `TUnderscore`; NORM-LOG-SPEC N4b, decided by Claude 2026-11-24, pending
 * Meng's review). The parser accepts it only inside a read pattern.
 */
export const L4_SYMBOLS: ReadonlySet<string> = new Set(['_'])
