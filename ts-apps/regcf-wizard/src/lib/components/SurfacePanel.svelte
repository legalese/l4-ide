<script lang="ts">
  import { onMount } from 'svelte'
  import { fetchSchema, evaluate, NetworkError } from '$lib/api/client'
  import { LAW_TIME_FN } from '$lib/config'
  import type { Surface } from '$lib/config'
  import { buildFieldTree } from '$lib/schema/build-tree'
  import { asWire } from '$lib/schema/types'
  import { createFormState } from '$lib/schema/form-state.svelte'
  import { validate, toArguments } from '$lib/schema/form-logic'
  import {
    asRaiseAssessment,
    asInvestmentLimitAnswer,
    asResaleAnswer,
    asReportingExitAnswer,
    asNumber,
    ShapeError,
  } from '$lib/api/validate'
  import { applyLawTime, isIso, todayIso } from '$lib/lawtime'
  import type { AppliedLawTime } from '$lib/lawtime'
  import SchemaForm from './SchemaForm.svelte'
  import StateViews from './StateViews.svelte'
  import LawTimeControls from './LawTimeControls.svelte'
  import RaiseCard from './answers/RaiseCard.svelte'
  import ResaleCard from './answers/ResaleCard.svelte'
  import ReportingExitCard from './answers/ReportingExitCard.svelte'
  import InvestmentLimitCard from './answers/InvestmentLimitCard.svelte'
  import type {
    ExportedFunctionInfo,
    FormState,
    RaiseAssessment,
    InvestmentLimitAnswer,
    ResaleAnswer,
    ReportingExitAnswer,
  } from '$lib/api/types'
  import type { FieldNode } from '$lib/schema/types'

  let { surface }: { surface: Surface } = $props()

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
  let errorMsg = $state<string | null>(null)
  let errorKind = $state<'network' | 'service'>('service')
  let fieldErrors = $state<Record<string, string>>({})

  let raise = $state<RaiseAssessment | null>(null)
  let resale = $state<ResaleAnswer | null>(null)
  let reporting = $state<ReportingExitAnswer | null>(null)
  let invest = $state<InvestmentLimitAnswer | null>(null)

  // The law-time trio (investor surface only).
  const today = todayIso()
  let factDate = $state(today)
  let override = $state<string | null>(null)
  let dateError = $state<string | undefined>(undefined)
  let applied = $state<AppliedLawTime | null>(null)
  let underRuleDate = $state<number | null>(null)
  let underToday = $state<number | null>(null)

  onMount(async () => {
    try {
      const fetched = await fetchSchema(surface.fn)
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
    dateError = undefined
    if (surface.kind === 'investmentLimit') {
      if (!isIso(factDate)) dateError = 'Please give a date as YYYY-MM-DD'
      if (override !== null && !isIso(override))
        dateError = 'Please give a date as YYYY-MM-DD'
    }
    if (Object.keys(errs).length > 0 || dateError) {
      focusFirstError(errs)
      return
    }
    phase = 'submitting'
    try {
      const args = toArguments(root, model)
      await run(args)
      phase = 'answered'
    } catch (e) {
      errorMsg =
        e instanceof ShapeError
          ? e.message
          : e instanceof Error
            ? e.message
            : 'Could not work out your answer.'
      errorKind = e instanceof NetworkError ? 'network' : 'service'
      phase = 'evalError'
    }
  }

  async function run(args: FormState): Promise<void> {
    if (!info) return
    switch (surface.kind) {
      case 'raise':
        raise = asRaiseAssessment(
          await evaluate(surface.fn, args, info.returnType)
        )
        return
      case 'resale':
        resale = asResaleAnswer(
          await evaluate(surface.fn, args, info.returnType)
        )
        return
      case 'reportingExit':
        reporting = asReportingExitAnswer(
          await evaluate(surface.fn, args, info.returnType)
        )
        return
      case 'investmentLimit': {
        // Three calls, one form. The rich, citation-carrying answer comes from
        // the undated export; the two comparable NUMBERS come from the law-time
        // export asked at two explicit rule dates. Asking for "today" EXPLICITLY
        // rather than leaning on the engine's unpinned current-day fallback is
        // what makes the comparison exact rather than nearly exact.
        const a = applyLawTime(factDate, override)
        const raw = args['facts']
        const facts: FormState =
          typeof raw === 'object' && raw !== null && !Array.isArray(raw)
            ? raw
            : args
        const [n, atRule, atToday] = await Promise.all([
          evaluate(surface.fn, args, info.returnType),
          evaluate(LAW_TIME_FN, { 'rule date': a.ruleDate, facts }, 'NUMBER'),
          evaluate(LAW_TIME_FN, { 'rule date': today, facts }, 'NUMBER'),
        ])
        invest = asInvestmentLimitAnswer(n)
        underRuleDate = asNumber(atRule)
        underToday = asNumber(atToday)
        applied = a
        return
      }
      case 'elicit':
        return
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
{:else if phase === 'answered'}
  {#if raise && surface.kind === 'raise'}
    <RaiseCard answer={raise} onRestart={backToForm} />
  {:else if resale && surface.kind === 'resale'}
    <ResaleCard answer={resale} onRestart={backToForm} />
  {:else if reporting && surface.kind === 'reportingExit'}
    <ReportingExitCard answer={reporting} onRestart={backToForm} />
  {:else if invest && applied && underRuleDate !== null && underToday !== null}
    <InvestmentLimitCard
      now={invest}
      {underRuleDate}
      {underToday}
      {applied}
      todayIsoDate={today}
      onRestart={backToForm}
    />
  {/if}
{:else if root && model}
  <p class="blurb">{surface.blurb}</p>

  {#if phase === 'evalError'}
    <StateViews
      kind="evalError"
      message={errorMsg ?? undefined}
      {errorKind}
      onRetry={backToForm}
    />
  {/if}

  {#if surface.kind === 'investmentLimit'}
    <LawTimeControls
      {factDate}
      {override}
      onFactDate={(v) => (factDate = v)}
      onOverride={(v) => (override = v)}
      error={dateError}
    />
  {/if}

  <SchemaForm
    {root}
    value={model}
    errors={fieldErrors}
    submitting={phase === 'submitting'}
    submitLabel="Work out my answer"
    onsubmit={handleSubmit}
  />
{/if}

<style>
  .blurb {
    color: var(--muted);
    margin: 0 0 1.5rem;
  }
</style>
