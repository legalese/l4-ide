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
    value: number | null
    onUpdate: (v: number | null) => void
    error?: string
  } = $props()

  const id = $derived(fieldId(node))
  const helpId = $derived(id + '-help')
  const errId = $derived(id + '-error')

  // Local display string, seeded once from the initial value. Decoupled from the
  // model so a mid-typing value (e.g. "99.") is never clobbered by a reactive
  // re-render. type=number means the browser only admits numeric input. The
  // one-time read of `value` is intentional (seed-once), not a missed derived.
  // svelte-ignore state_referenced_locally
  let display = $state(value === null ? '' : String(value))

  function handle(e: Event): void {
    const el = e.currentTarget as HTMLInputElement
    display = el.value
    const t = display.trim()
    onUpdate(t === '' ? null : Number(t))
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
    <span class="prefix" aria-hidden="true">£</span>
    <input
      {id}
      type="number"
      inputmode="decimal"
      step="any"
      min="0"
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
