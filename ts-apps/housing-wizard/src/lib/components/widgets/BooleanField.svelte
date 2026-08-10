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
    value: boolean | null
    onUpdate: (v: boolean) => void
    error?: string
  } = $props()

  const id = $derived(fieldId(node))
  const helpId = $derived(id + '-help')
  const errId = $derived(id + '-error')
  const describedBy = $derived(
    [node.help ? helpId : '', error ? errId : ''].filter(Boolean).join(' ') ||
      undefined
  )
</script>

<fieldset class="field" {id} aria-describedby={describedBy}>
  <legend>
    {node.label}{#if node.required}<span aria-hidden="true"> *</span>{/if}
  </legend>
  {#if node.help}
    <p class="help" id={helpId}>{node.help}</p>
  {/if}
  <div class="options">
    <label class="option-card" class:selected={value === true}>
      <input
        type="radio"
        name={id}
        checked={value === true}
        onchange={() => onUpdate(true)}
      />
      <span>Yes</span>
    </label>
    <label class="option-card" class:selected={value === false}>
      <input
        type="radio"
        name={id}
        checked={value === false}
        onchange={() => onUpdate(false)}
      />
      <span>No</span>
    </label>
  </div>
  {#if error}
    <p class="error" id={errId} role="alert">{error}</p>
  {/if}
</fieldset>
