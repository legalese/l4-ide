<script lang="ts">
  import { fieldId } from '$lib/schema/labels'
  import type { FieldNode } from '$lib/schema/types'

  let {
    node,
    value,
    onUpdate,
    error,
  }: {
    node: FieldNode
    value: string
    onUpdate: (v: string) => void
    error?: string
  } = $props()

  const id = $derived(fieldId(node))
  const helpId = $derived(id + '-help')
  const errId = $derived(id + '-error')

  // Seed-once from the prop (intentional, not a missed derived).
  // svelte-ignore state_referenced_locally
  let display = $state(value)

  function handle(e: Event): void {
    display = (e.currentTarget as HTMLInputElement).value
    onUpdate(display)
  }

  const describedBy = $derived(
    [node.help ? helpId : '', error ? errId : ''].filter(Boolean).join(' ') ||
      undefined
  )
</script>

<div class="field">
  <label for={id}>
    {node.label}{#if node.required}<span aria-hidden="true"> *</span>{/if}
  </label>
  {#if node.help}
    <p class="help" id={helpId}>{node.help}</p>
  {/if}
  <div class="input-wrap">
    <input
      {id}
      type="text"
      value={display}
      oninput={handle}
      aria-describedby={describedBy}
      aria-invalid={error ? 'true' : undefined}
    />
  </div>
  {#if error}
    <p class="error" id={errId} role="alert">{error}</p>
  {/if}
</div>
