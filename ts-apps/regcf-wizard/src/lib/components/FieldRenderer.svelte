<script lang="ts">
  // Self-import for recursion: <svelte:self> is deprecated in Svelte 5.
  import Self from './FieldRenderer.svelte'
  import EnumField from './widgets/EnumField.svelte'
  import NumberField from './widgets/NumberField.svelte'
  import BooleanField from './widgets/BooleanField.svelte'
  import TextField from './widgets/TextField.svelte'
  import DateField from './widgets/DateField.svelte'
  import UnsupportedField from './widgets/UnsupportedField.svelte'
  import { fieldId } from '$lib/schema/labels'
  import type { FieldNode } from '$lib/schema/types'
  import type { FormState, FormValue } from '$lib/api/types'

  let {
    node,
    parent,
    errors,
  }: {
    node: FieldNode
    parent: FormState
    errors: Record<string, string>
  } = $props()

  // Read + write the leaf through the shared $state proxy. Mutating
  // parent[node.key] is a LEAF mutation — it never reassigns a branch, so deep
  // reactivity survives.
  const current = $derived(parent[node.key])
  const error = $derived(errors[fieldId(node)])

  function setValue(v: FormValue): void {
    parent[node.key] = v
  }

  const childObject = $derived(
    typeof current === 'object' && current !== null && !Array.isArray(current)
      ? current
      : ({} as FormState)
  )
</script>

{#if node.widget === 'object'}
  <fieldset class="group" id={fieldId(node)}>
    <legend class="group-legend">{node.label}</legend>
    {#if node.help}
      <p class="help">{node.help}</p>
    {/if}
    {#each node.children as child (child.key)}
      <Self node={child} parent={childObject} {errors} />
    {/each}
  </fieldset>
{:else if node.widget === 'enum'}
  <EnumField {node} value={current as string} onUpdate={setValue} {error} />
{:else if node.widget === 'number'}
  <NumberField
    {node}
    value={current as number | null}
    onUpdate={setValue}
    {error}
  />
{:else if node.widget === 'boolean'}
  <BooleanField
    {node}
    value={current as boolean | null}
    onUpdate={setValue}
    {error}
  />
{:else if node.widget === 'date'}
  <DateField {node} value={current as string} onUpdate={setValue} {error} />
{:else if node.widget === 'text'}
  <TextField {node} value={current as string} onUpdate={setValue} {error} />
{:else}
  <UnsupportedField {node} />
{/if}

<style>
  .group {
    border: 0;
    margin: 0;
    padding: 0;
    min-width: 0;
  }
  .group-legend {
    font-size: 1.15rem;
    font-weight: 700;
    margin-bottom: 1rem;
    padding: 0;
  }
</style>
