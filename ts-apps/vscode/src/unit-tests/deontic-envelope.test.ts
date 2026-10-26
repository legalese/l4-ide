/** Whether a function takes the DEONTIC simulation envelope, as the deploy
 *  sidebar asks it before diffing the local interface against the deployed one
 *  (jl4-client-rpc's `isDeonticFunction`, tested here because this package has
 *  the `node --test` rig and that one does not). The sidebar page itself is a
 *  Svelte component and has no rig; it calls this and nothing else to decide. */
import { test, describe } from 'node:test'
import * as assert from 'node:assert/strict'
import { isDeonticFunction } from 'jl4-client-rpc'

describe('isDeonticFunction', () => {
  test('is the flag when there is one', () => {
    assert.equal(isDeonticFunction({ isDeontic: true }), true)
    assert.equal(isDeonticFunction({ isDeontic: false }), false)
  })

  test('takes a function that returns PROVISION OF by its flag, as its DEONTIC twin', () => {
    // PROVISION OF is the deprecated alias of DEONTIC: the same type, so the
    // same envelope, and a display name that does not begin with "DEONTIC".
    const twin = {
      isDeontic: true,
      returnType: 'DEONTIC Driver `Driver Action`',
    }
    const alias = {
      isDeontic: true,
      returnType: 'PROVISION OF Driver, `Driver Action`',
    }
    assert.equal(isDeonticFunction(twin), true)
    assert.equal(isDeonticFunction(alias), true)
  })

  test('believes the flag over the display name', () => {
    // The type decided the flag; a name that merely looks like one does not
    // overrule it.
    assert.equal(
      isDeonticFunction({ isDeontic: false, returnType: 'DEONTIC LIKE' }),
      false
    )
    assert.equal(
      isDeonticFunction({ isDeontic: true, returnType: 'BOOLEAN' }),
      true
    )
  })

  describe('with no flag (a deployment stored before the service kept one)', () => {
    test('reads DEONTIC and PROVISION OF from the display name', () => {
      assert.equal(isDeonticFunction({ returnType: 'DEONTIC A B' }), true)
      assert.equal(isDeonticFunction({ returnType: 'PROVISION OF A, B' }), true)
    })

    test('is not deontic for anything else', () => {
      assert.equal(isDeonticFunction({ returnType: 'BOOLEAN' }), false)
      assert.equal(isDeonticFunction({ returnType: 'LIST OF NUMBER' }), false)
      assert.equal(isDeonticFunction({}), false)
    })
  })
})
