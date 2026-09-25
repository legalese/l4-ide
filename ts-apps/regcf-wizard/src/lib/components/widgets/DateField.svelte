<script lang="ts">
  import { fieldId } from '$lib/schema/labels'
  import type { FieldNode } from '$lib/schema/types'

  // An L4 `DATE` parameter. The service types it `{"type":"string",
  // "format":"date"}`, and the evaluator parses it strictly — so this is a
  // native date control, not a text box that hopes for the best. `<input
  // type=date>` emits exactly YYYY-MM-DD, which is what the wire wants; the
  // form-logic validator still checks the string, because a browser without the
  // native picker falls back to free text.
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

  function handle(e: Event): void {
    onUpdate((e.currentTarget as HTMLInputElement).value)
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
      type="date"
      {value}
      oninput={handle}
      aria-describedby={describedBy}
      aria-invalid={error ? 'true' : undefined}
    />
  </div>
  {#if error}
    <p class="error" id={errId} role="alert">{error}</p>
  {/if}
</div>
