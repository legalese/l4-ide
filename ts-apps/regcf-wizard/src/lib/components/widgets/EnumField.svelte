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
    {#each node.enumOptions as opt (opt)}
      <label class="option-card" class:selected={value === opt}>
        <input
          type="radio"
          name={id}
          value={opt}
          checked={value === opt}
          onchange={() => onUpdate(opt)}
        />
        <span>{opt}</span>
      </label>
    {/each}
  </div>
  {#if error}
    <p class="error" id={errId} role="alert">{error}</p>
  {/if}
</fieldset>
