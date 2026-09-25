<script lang="ts">
  import { onMount } from 'svelte'
  import {
    fetchSchema,
    evaluate,
    NetworkError,
  } from '$lib/api/assessment-client'
  import { buildFieldTree } from '$lib/schema/build-tree'
  import { asWire } from '$lib/schema/types'
  import { createFormState } from '$lib/schema/form-state.svelte'
  import { validate, toArguments } from '$lib/schema/form-logic'
  import SchemaForm from '$lib/components/SchemaForm.svelte'
  import AnswerCard from '$lib/components/AnswerCard.svelte'
  import StateViews from '$lib/components/StateViews.svelte'
  import type {
    ExportedFunctionInfo,
    PossessionAssessment,
    FormState,
  } from '$lib/api/types'
  import type { FieldNode } from '$lib/schema/types'

  type Phase =
    | 'loadingSchema'
    | 'ready'
    | 'submitting'
    | 'answered'
    | 'schemaError'
    | 'evalError'

  let phase = $state<Phase>('loadingSchema')
  let info = $state<ExportedFunctionInfo | null>(null)
  let root = $state<FieldNode | null>(null)
  let model = $state<FormState | null>(null)
  let answer = $state<PossessionAssessment | null>(null)
  let errorMsg = $state<string | null>(null)
  let errorKind = $state<'network' | 'service'>('service')
  let fieldErrors = $state<Record<string, string>>({})

  // Fire-once schema fetch. onMount (not a bare $effect) so it never re-fires on
  // reactive reads; the phase state machine also guards it. No module-scope
  // fetch exists, so the prerender pass only emits the shell.
  onMount(async () => {
    try {
      const fetched = await fetchSchema()
      const built = buildFieldTree(
        asWire(fetched.parameters),
        '__root__',
        new Set()
      )
      info = fetched
      root = built
      model = createFormState(built)
      phase = 'ready'
    } catch (e) {
      errorMsg =
        e instanceof Error ? e.message : 'Could not load the questions.'
      errorKind = e instanceof NetworkError ? 'network' : 'service'
      phase = 'schemaError'
    }
  })

  async function handleSubmit(): Promise<void> {
    if (!root || !model || !info) return
    const errs = validate(root, model)
    fieldErrors = errs
    if (Object.keys(errs).length > 0) {
      focusFirstError(errs)
      return
    }
    phase = 'submitting'
    try {
      const args = toArguments(root, model)
      answer = await evaluate(args, info.returnType)
      phase = 'answered'
    } catch (e) {
      errorMsg =
        e instanceof Error ? e.message : 'Could not work out your answer.'
      errorKind = e instanceof NetworkError ? 'network' : 'service'
      phase = 'evalError'
    }
  }

  function focusFirstError(errs: Record<string, string>): void {
    const firstId = Object.keys(errs)[0]
    if (!firstId) return
    queueMicrotask(() => {
      const el = document.getElementById(firstId)
      const focusable = el?.querySelector('input, select, textarea')
      if (focusable instanceof HTMLElement) focusable.focus()
      else if (el instanceof HTMLElement) el.focus()
    })
  }

  function backToForm(): void {
    phase = 'ready'
  }
</script>

{#if phase === 'loadingSchema'}
  <StateViews kind="loading" />
{:else if phase === 'schemaError'}
  <StateViews
    kind="schemaError"
    message={errorMsg ?? undefined}
    {errorKind}
    onRetry={() => location.reload()}
  />
{:else if phase === 'answered' && answer && info && root && model}
  <AnswerCard
    assessment={answer}
    {info}
    facts={model}
    {root}
    onRestart={backToForm}
  />
{:else if root && model}
  <div class="intro">
    <h1>Could my landlord evict me for rent arrears?</h1>
    <p>
      Answer five short questions about your rent. This free check applies the
      Housing Act 1988 rules for rent-arrears possession (Grounds 8, 10 and 11)
      and tells you whether a court <strong>must</strong> or only
      <strong>may</strong> order possession — and why.
    </p>
  </div>

  {#if phase === 'evalError'}
    <StateViews
      kind="evalError"
      message={errorMsg ?? undefined}
      {errorKind}
      onRetry={backToForm}
    />
  {/if}

  <SchemaForm
    {root}
    value={model}
    errors={fieldErrors}
    submitting={phase === 'submitting'}
    onsubmit={handleSubmit}
  />
{/if}

<style>
  .intro h1 {
    font-size: 1.6rem;
    line-height: 1.25;
    margin: 0 0 0.7rem;
  }
  .intro p {
    color: var(--ink);
    margin: 0 0 1.6rem;
  }
  .intro strong {
    color: var(--brand-dark);
  }
</style>
