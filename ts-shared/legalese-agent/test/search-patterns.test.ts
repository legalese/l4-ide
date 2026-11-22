import { describe, test } from 'node:test'
import * as assert from 'node:assert/strict'
import {
  compilePatterns,
  invalidPatternNote,
  matchesAny,
  searchWords,
  splitPatterns,
} from '../src/index.js'

describe('splitPatterns', () => {
  test('splits on spaces outside groups, classes, backticks and quotes', () => {
    assert.deepEqual(splitPatterns('sum  max\tmin'), ['sum', 'max', 'min'])
    assert.deepEqual(
      splitPatterns(
        '^(GIVEN|DECIDE|@export)?.*(sum|max|min|map|`greater of`|maximum|minimum|fold)'
      ),
      [
        '^(GIVEN|DECIDE|@export)?.*(sum|max|min|map|`greater of`|maximum|minimum|fold)',
      ]
    )
    assert.deepEqual(splitPatterns('`the greater of` b'), [
      '`the greater of`',
      'b',
    ])
    assert.deepEqual(splitPatterns('[ (] x{1, 2} y'), ['[ (]', 'x{1, 2}', 'y'])
  })

  test('drops double quotes around a phrase', () => {
    assert.deepEqual(splitPatterns('"net income" tax'), ['net income', 'tax'])
  })

  test('an escaped space or bracket is part of the pattern', () => {
    assert.deepEqual(splitPatterns('a\\ b \\( c'), ['a\\ b', '\\(', 'c'])
  })

  test('a blank query has no patterns', () => {
    assert.deepEqual(splitPatterns('   '), [])
    assert.deepEqual(compilePatterns(''), [])
  })
})

describe('compilePatterns', () => {
  test('patterns are case-insensitive regexes, any one matching', () => {
    const matches = matchesAny(compilePatterns('^decide (total|sum)'))
    assert.equal(matches('DECIDE x'), true)
    assert.equal(matches('the SUM of'), true)
    assert.equal(matches('  DECIDE x'), false)
    assert.equal(matches('nothing'), false)
  })

  test('an invalid regex is matched as plain text and noted', () => {
    const patterns = compilePatterns('f(x ok')
    assert.deepEqual(
      patterns.map((p) => [p.source, p.invalid]),
      [['f(x ok', 'Unterminated group']]
    )
    assert.equal(matchesAny(patterns)('call f(x ok)'), true)
    assert.equal(
      invalidPatternNote(patterns),
      'Note: "f(x ok" is not a valid regular expression (Unterminated group), so it was matched as plain text.'
    )
    assert.equal(invalidPatternNote(compilePatterns('fine')), null)
  })
})

describe('searchWords', () => {
  test('keeps the words of any query, regex syntax included', () => {
    assert.deepEqual(
      searchWords('^(GIVEN|DECIDE|@export)?.*(sum|`greater of`|fold)'),
      ['given', 'decide', 'export', 'sum', 'greater', 'of', 'fold']
    )
    assert.deepEqual(searchWords('Late-payment  penalty, penalty'), [
      'late-payment',
      'penalty',
    ])
    assert.deepEqual(searchWords('a | ^ $'), [])
  })
})
