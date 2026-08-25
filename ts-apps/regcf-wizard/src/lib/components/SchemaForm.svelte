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
    submitLabel = 'Check my situation',
    busyLabel = 'Working out your answer…',
    onsubmit,
  }: {
    root: FieldNode
    value: FormState
    errors: Record<string, string>
    submitting: boolean
    submitLabel?: string
    busyLabel?: string
    onsubmit: () => void
  } = $props()

  // Cosmetic unwrap: an export with ONE record parameter (four of the five Reg
  // CF surfaces) would otherwise render a fieldset-in-a-fieldset. An export with
  // two roots — the law-time one, `rule date` + `facts` — does not match and
  // renders both roots, which is the shape a multi-root form has to survive.
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

  // Submit-time error summary. Walks the WHOLE tree, not just the top level:
  // with a multi-root form a failing leaf can sit one level down, and a summary
  // that silently omitted it would leave the citizen with a form that refuses to
  // submit and says nothing about why.
  function leaves(node: FieldNode): FieldNode[] {
    return node.widget === 'object' ? node.children.flatMap(leaves) : [node]
  }
  const errorList = $derived(
    leaves(formNode)
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
    {submitting ? busyLabel : submitLabel}
  </button>
</form>
