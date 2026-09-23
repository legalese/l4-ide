/**
 * `sidebarBindingsFor` — the three-method shim that lets `partial-eval-sidebar.svelte` be
 * reused verbatim by the Step-4 displayer.
 *
 * Two things can go wrong here and neither is visible by eye until it is annoying: the
 * `UBoolVal` (a class instance) → `UBoolValue` (a string tag) conversion can be dropped or
 * inverted, and `onChanged` can fire on the wrong subset of calls — on `getLabelForUnique`
 * it would re-render on every label lookup, and missing it on `submitNewBinding` would leave
 * the picture one click behind the sidebar. So both are asserted.
 */
import { describe, expect, it } from 'vitest'
import type {
  FunDecl as VizFunDecl,
  IRExpr,
  VersionedDocId,
} from '@repo/viz-expr'
import { LadderModel } from '../lib/model/ladder-model.js'
import { sidebarBindingsFor } from '../lib/displayers/svg/sidebar-bridge.js'
import { FalseVal, TrueVal } from '../lib/eval/type.js'
import type { L4Connection } from '../lib/l4-connection.js'

const nm = (label: string, unique: number) => ({ label, unique })
const iid = (id: number) => ({ id })
const ubool = (id: number, unique: number, label: string): IRExpr => ({
  $type: 'UBoolVar',
  id: iid(id),
  name: nm(label, unique),
  value: 'UnknownV',
  canInline: false,
  atomId: `atom-${unique}`,
})

const fn: VizFunDecl = {
  $type: 'FunDecl',
  id: iid(500),
  name: nm('bridged', 50),
  params: [],
  body: {
    $type: 'And',
    id: iid(51),
    args: [ubool(52, 60, 'wet'), ubool(53, 61, 'cold')],
  },
}

const deps = {
  l4Connection: {
    evalApp: () => {
      throw new Error('evalApp must not be called for an App-free tree')
    },
  } as unknown as L4Connection,
  verDocId: {} as VersionedDocId,
}

const mk = () => {
  const model = new LadderModel(fn, deps)
  let changes = 0
  const bindings = sidebarBindingsFor(model, () => changes++)
  return { model, bindings, changed: () => changes }
}

describe('sidebarBindingsFor', () => {
  it('submitNewBinding lands the value in the model, converted to a wire tag', async () => {
    const { model, bindings } = mk()
    bindings.submitNewBinding(null, { unique: 60, value: new TrueVal() })
    await model.recompute()
    expect(model.valuation.get(52)).toBe('TrueV')

    bindings.submitNewBinding(null, { unique: 61, value: new FalseVal() })
    await model.recompute()
    expect(model.valuation.get(53)).toBe('FalseV')
  })

  it('onChanged fires once per binding and once per reset', () => {
    const { bindings, changed } = mk()
    expect(changed()).toBe(0)
    bindings.submitNewBinding(null, { unique: 60, value: new TrueVal() })
    expect(changed()).toBe(1)
    bindings.resetBindings(null)
    expect(changed()).toBe(2)
  })

  it('onChanged does NOT fire on a label lookup — that is a pure read', () => {
    const { bindings, changed } = mk()
    expect(bindings.getLabelForUnique(null, 60)).toBe('wet')
    expect(bindings.getLabelForUnique(null, 61)).toBe('cold')
    expect(changed()).toBe(0)
  })

  it('resetBindings actually clears what was assigned', async () => {
    const { model, bindings } = mk()
    bindings.submitNewBinding(null, { unique: 60, value: new TrueVal() })
    await model.recompute()
    expect(model.valuation.get(52)).toBe('TrueV')

    bindings.resetBindings(null)
    await model.recompute()
    expect(model.valuation.get(52)).toBe('UnknownV')
  })
})
