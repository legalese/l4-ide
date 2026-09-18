<script lang="ts">
  import { onMount } from 'svelte'
  import { fromVizFunDecl, verdictFor } from '@repo/ladder-core'
  import type { FunDecl, NodeId, UBoolValue } from '@repo/ladder-core'
  import type { ProposedCharge } from '$lib/case/casefile.svelte'
  import { casefile } from '$lib/case/casefile.svelte'
  import { ladderOf, schemaOf, scheduleRecital } from '$lib/charges/recital'
  import {
    callPrefixes,
    elementPaths,
    pathByNode,
    valuationFor,
  } from '$lib/charges/valuation'
  import {
    cycle,
    readAt,
    writeAt,
    type FieldPath,
  } from '$lib/charges/leaf-field'
  import {
    factsSchema,
    stringFields,
    type StringField,
  } from '$lib/charges/schema-fill'
  import { layoutDag } from '$lib/evidence/graph'
  import Ladder from './Ladder.svelte'
  import ParticularsEditor from './ParticularsEditor.svelte'
  import EvidenceGraph from './EvidenceGraph.svelte'

  /**
   * One slide of the carousel: the section as a ladder (with the defining
   * sections' ladders stacked beneath when the offence calls them), the charge
   * as L4 recites it, the particulars the charge quotes, and the evidence the
   * elements rest on.
   *
   * The clicky-clicky loop lives here: click a leaf → its field flips in the
   * facts record → the ladder re-values LOCALLY (instant) → one debounced
   * evaluation asks the service for the new `Charge` → the recital replaces.
   */
  let { pc }: { pc: ProposedCharge } = $props()

  type VizFunDecl = Parameters<typeof fromVizFunDecl>[0]
  interface Decoded {
    readonly fnName: string
    readonly fn: FunDecl
    /** Where this rule's record sits inside the card's facts record (a nested call). */
    readonly prefix: FieldPath
    readonly paths: Map<NodeId, FieldPath>
  }

  let main = $state<Decoded | null>(null)
  let subs = $state<Decoded[]>([])
  let fields = $state<StringField[]>([])
  let loadError = $state<string | null>(null)

  const param = $derived(pc.offence.factsParam)

  function decode(fnName: string, raw: unknown, prefix: FieldPath): Decoded {
    const { fn } = fromVizFunDecl(raw as VizFunDecl)
    return { fnName, fn, prefix, paths: pathByNode(fn, param, prefix) }
  }

  onMount(async () => {
    try {
      const [mainRaw, info, ...subRaw] = await Promise.all([
        ladderOf(pc.offence.offenceFn),
        schemaOf(pc.offence.chargeFn),
        ...pc.offence.definitionFns.map((f) => ladderOf(f)),
      ])
      const m = decode(pc.offence.offenceFn, mainRaw, [])
      // A callee's record may be nested (`commits theft OF (f's theft)`): its
      // prefix is read off the call leaf of whoever calls it. definitionFns are
      // listed outer to inner, so one pass resolves the chain.
      const prefixes = new Map<string, FieldPath>(callPrefixes(m.fn, param))
      const decoded: Decoded[] = []
      pc.offence.definitionFns.forEach((f, i) => {
        const prefix = prefixes.get(f) ?? []
        const d = decode(f, subRaw[i], prefix)
        for (const [callee, arg] of callPrefixes(d.fn, param))
          if (!prefixes.has(callee)) prefixes.set(callee, [...prefix, ...arg])
        decoded.push(d)
      })
      main = m
      subs = decoded
      fields = stringFields(factsSchema(info.parameters, param))
      if (!pc.charge) scheduleRecital(pc)
    } catch (e) {
      loadError = e instanceof Error ? e.message : String(e)
    }
  })

  const triOfVerdict = (v: string): UBoolValue =>
    v === 'Holds' ? 'TrueV' : v === 'Fails' ? 'FalseV' : 'UnknownV'

  /**
   * Sub-ladder valuations, innermost first, so a callee's verdict is known
   * before the rule that calls it is valued; the verdicts then feed the call
   * leaves of the main ladder.
   */
  const subState = $derived.by(() => {
    const calls = new Map<string, UBoolValue>()
    const vals = new Map<string, Map<NodeId, UBoolValue>>()
    for (const d of [...subs].reverse()) {
      const v = valuationFor(d.fn, param, pc.facts, calls, d.prefix)
      vals.set(d.fnName, v)
      calls.set(d.fnName, triOfVerdict(verdictFor(d.fn, v)))
    }
    return { calls, vals }
  })
  const subValuations = $derived(
    subs.map((d) => ({
      d,
      v: subState.vals.get(d.fnName) ?? new Map<NodeId, UBoolValue>(),
    }))
  )
  const mainValuation = $derived(
    main
      ? valuationFor(main.fn, param, pc.facts, subState.calls)
      : new Map<NodeId, UBoolValue>()
  )
  const localVerdict = $derived(
    main ? verdictFor(main.fn, mainValuation) : 'Undetermined'
  )

  const elements = $derived(
    main ? elementPaths(main.fn, param).map((p) => p.join('/')) : []
  )
  const dag = $derived(
    layoutDag(
      casefile.evidence,
      pc.offence.section,
      pc.offence.title,
      [
        ...elements,
        ...subs.flatMap((s) =>
          elementPaths(s.fn, param).map((p) => [...s.prefix, ...p].join('/'))
        ),
      ].filter((v, i, a) => a.indexOf(v) === i)
    )
  )

  function toggle(d: Decoded, id: NodeId): void {
    const path = d.paths.get(id)
    if (!path) return
    pc.facts = writeAt(pc.facts, path, cycle(readAt(pc.facts, path)))
    scheduleRecital(pc)
  }

  function setParticular(path: readonly string[], value: string): void {
    pc.facts = writeAt(pc.facts, path, value)
    scheduleRecital(pc)
  }

  const badge = $derived(
    pc.pending
      ? { cls: 'pending', text: 'reciting…' }
      : pc.charge
        ? pc.charge['made out']
          ? { cls: 'made-out', text: 'made out' }
          : { cls: 'refused', text: 'not made out' }
        : { cls: 'pending', text: localVerdict }
  )
</script>

<article class="card" aria-label={`Charge under section ${pc.offence.section}`}>
  <header class="card-head">
    <div>
      <span class="chip">s {pc.offence.section}</span>
      <strong class="title">{pc.offence.title}</strong>
      <span class="defines">elements from {pc.offence.defines}</span>
    </div>
    <span class={`badge ${badge.cls}`}>{badge.text}</span>
  </header>

  {#if loadError}
    <p class="error">Could not load the section: {loadError}</p>
  {:else if !main}
    <p class="muted">Loading the section…</p>
  {:else}
    <Ladder
      fn={main.fn}
      valuation={mainValuation}
      interactive
      onClickNode={(id) => main && toggle(main, id)}
      caption={`Section ${pc.offence.section}. Click an element to toggle it: unknown → true → false. The charge below is re-framed by the encoded section on every click.`}
    />
    {#each subValuations as { d, v } (d.fnName)}
      <Ladder
        fn={d.fn}
        valuation={v}
        interactive
        variant="stacked"
        onClickNode={(id) => toggle(d, id)}
        caption={`${d.fnName} — the defining section, called from the ladder above.`}
      />
    {/each}
  {/if}

  <section class="recital-block">
    <h3>The charge</h3>
    {#if pc.error}
      <p class="error">{pc.error}</p>
    {:else if pc.charge?.['made out']}
      <p class="recital">{pc.charge.text}</p>
      <p class="punishment">Punishable with {pc.charge.punishment}.</p>
    {:else if pc.charge}
      <p class="recital refusal">{pc.charge.refusal}</p>
    {:else}
      <p class="muted">Waiting for the first evaluation…</p>
    {/if}
  </section>

  {#if fields.length > 0}
    <details class="particulars-block">
      <summary>Particulars the charge recites (CPC s 124)</summary>
      <ParticularsEditor {fields} facts={pc.facts} onChange={setParticular} />
    </details>
  {/if}

  <section class="evidence-block">
    <h3>What it rests on</h3>
    <EvidenceGraph {dag} />
  </section>
</article>

<style>
  .card {
    display: grid;
    gap: 0.8rem;
  }
  .card-head {
    display: flex;
    justify-content: space-between;
    align-items: baseline;
    gap: 0.6rem;
    flex-wrap: wrap;
  }
  .title {
    margin-left: 0.4rem;
  }
  .defines {
    margin-left: 0.5rem;
    color: var(--muted);
    font-size: 0.85rem;
  }
  h3 {
    font-size: 0.95rem;
    margin: 0 0 0.4rem;
  }
  .punishment {
    color: var(--muted);
    font-size: 0.9rem;
    margin: 0.4rem 0 0;
  }
  .muted {
    color: var(--muted);
  }
  .error {
    color: var(--must-fg);
  }
  details summary {
    cursor: pointer;
    font-weight: 600;
    font-size: 0.95rem;
    margin-bottom: 0.5rem;
  }
</style>
