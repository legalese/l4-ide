import { seed } from './form-logic'
import type { FieldNode } from './types'
import type { FormState } from '$lib/api/types'

/**
 * The ONLY runes file in the schema layer. Wraps the pure `seed` tree in a single
 * top-level $state root. Svelte 5 deep-proxies the nested plain objects reachable
 * through this root, so widgets can bind to leaves at any depth.
 *
 * Reactivity discipline (load-bearing): widgets MUTATE leaves only; never
 * reassign or spread a branch (spreading detaches the proxy and writes stop
 * propagating). toArguments builds a fresh output instead of cloning a branch.
 */
export function createFormState(root: FieldNode): FormState {
  const state = $state(seed(root))
  return state
}
