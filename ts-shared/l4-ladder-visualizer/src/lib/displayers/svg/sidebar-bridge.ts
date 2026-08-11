/**
 * The three methods `partial-eval-sidebar.svelte` actually calls, and an adapter that gives
 * them to a `LadderModel`.
 *
 * E1 Step 4 says "reuse `partial-eval-sidebar.svelte` as-is — widen its prop to a structural
 * interface (~5 lines) and the whole 'Still Needed' panel comes along". This is the other
 * end of that widening. It lives in a `.ts` rather than inside the shell because it is the
 * only genuinely testable thing in the reuse: the `UBoolVal`→`UBoolValue` conversion is the
 * easiest thing here to get backwards, and `onChanged` firing on the wrong subset of calls
 * would show up as a picture that lags the sidebar by one click.
 *
 * Neither side imports the other's type: the interface is structural, so
 * `LadderGraphLirNode` satisfies it with `C = LirContext` (the old call site, untouched) and
 * this shim satisfies it with `C = null`.
 */
import type { Unique } from '@repo/viz-expr'
import type { UBoolVal } from '$lib/eval/type.js'
import { toVEBoolValue } from '$lib/eval/type.js'
import type { LadderModel } from '$lib/model/ladder-model.js'

export interface SidebarBindings<C> {
  resetBindings(context: C): unknown
  getLabelForUnique(context: C, unique: Unique): string
  submitNewBinding(
    context: C,
    binding: { unique: Unique; value: UBoolVal }
  ): unknown
}

/**
 * Adapt a `LadderModel` to what the sidebar calls.
 *
 * `onChanged` is the shell's serialised recompute. The LIR re-evaluated internally on every
 * binding; `LadderModel` deliberately does not (`recompute()` is async because `App` leaves
 * round-trip), so the host owns the re-run and this shim just says when one is owed.
 */
export function sidebarBindingsFor(
  model: LadderModel,
  onChanged: () => void
): SidebarBindings<null> {
  return {
    resetBindings: () => {
      model.resetBindings()
      onChanged()
    },
    // a pure read — it must NOT schedule a recompute, or every render loops
    getLabelForUnique: (_context, unique) => model.getLabelForUnique(unique),
    submitNewBinding: (_context, { unique, value }) => {
      model.setValueForUnique(unique, toVEBoolValue(value))
      onChanged()
    },
  }
}
