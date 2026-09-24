<script lang="ts">
  import FieldRenderer from './FieldRenderer.svelte'
  import { fieldId } from '$lib/schema/labels'
  import type { FieldNode } from '$lib/schema/types'
  import type { FormState } from '$lib/api/types'

  let {
    root,
    value,
    errors,
    submitting,
    onsubmit,
  }: {
    root: FieldNode
    value: FormState
    errors: Record<string, string>
    submitting: boolean
    onsubmit: () => void
  } = $props()

  // Cosmetic unwrap: the live schema wraps the five questions in a single
  // 'situation' object. Render its children directly so the tenant sees clean
  // questions, not a fieldset-in-a-fieldset. Fully generic: any single-object
  // wrapper is unwrapped; otherwise the root's own children are rendered.
  const single = $derived(
    root.children.length === 1 && root.children[0].widget === 'object'
      ? root.children[0]
      : null
  )
  const formNode = $derived(single ?? root)
  const formParent = $derived.by((): FormState => {
    if (single) {
      const v = value[single.key]
      if (typeof v === 'object' && v !== null && !Array.isArray(v)) return v
    }
    return value
  })

  // Submit-time summary of the top-level questions' errors (links to each
  // control). The live form is flat under 'situation', so this covers every
  // question.
  const errorList = $derived(
    formNode.children
      .map((c) => ({ id: fieldId(c), label: c.label, msg: errors[fieldId(c)] }))
      .filter((e) => Boolean(e.msg))
  )

  function handle(e: SubmitEvent): void {
    e.preventDefault()
    onsubmit()
  }
</script>

<form onsubmit={handle} novalidate>
  {#if errorList.length > 0}
    <div class="summary" role="alert">
      <p>Please check these answers:</p>
      <ul>
        {#each errorList as item (item.id)}
          <li><a href={'#' + item.id}>{item.label}</a>: {item.msg}</li>
        {/each}
      </ul>
    </div>
  {/if}

  {#each formNode.children as child (child.key)}
    <FieldRenderer node={child} parent={formParent} {errors} />
  {/each}

  <button type="submit" class="submit" disabled={submitting}>
    {submitting ? 'Working out your answer…' : 'Check my situation'}
  </button>
</form>
