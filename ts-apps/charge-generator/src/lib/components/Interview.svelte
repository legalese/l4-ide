<script lang="ts">
  import { tick } from 'svelte'
  import { marked } from 'marked'
  import { casefile, freshId, type Turn } from '$lib/case/casefile.svelte'
  import { offenceBySection } from '$lib/catalogue'
  import { scheduleRecital } from '$lib/charges/recital'
  import { matchPreload, type Preload } from '$lib/interview/preload'
  import { PRELOADS } from '$lib/interview/preloads'
  import PreloadPicker from './PreloadPicker.svelte'
  import Moments from './Moments.svelte'

  /**
   * The interview pane. Two paths out of the composer:
   *
   *   - the text matches a preload EXACTLY → replay it here, no network: a
   *     "… some moments later …" beat, the reply streamed in, the case file set
   *     to the canned result (charges, evidence, uploads);
   *   - otherwise → POST /api/interview (the live route; 501 until PR 3).
   *
   * The transcript autoscrolls as text arrives (Meng's bonus).
   */
  let draft = $state('')
  let busy = $state(false)
  let moments = $state(false)
  let log = $state<HTMLDivElement | null>(null)
  let files = $state<FileList | null>(null)

  marked.setOptions({ breaks: false, gfm: true })
  const html = (t: string): string =>
    marked.parse(t, { async: false }) as string

  async function scrollToEnd(): Promise<void> {
    await tick()
    if (log) log.scrollTop = log.scrollHeight
  }

  const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))

  // Chunks of a few words per tick, not one word: a background tab's timers
  // are throttled to ~1 Hz, and a 150-word reply at one word per timer would
  // take minutes. Measured 2026-09-17 in a non-focused Chrome tab.
  async function stream(turn: Turn, text: string): Promise<void> {
    turn.streaming = true
    const words = text.split(/(\s+)/)
    const CHUNK = 12
    for (let i = 0; i < words.length; i += CHUNK) {
      turn.text += words.slice(i, i + CHUNK).join('')
      void scrollToEnd()
      await sleep(45)
    }
    turn.streaming = false
  }

  function applyResult(p: Preload): void {
    casefile.uploads = [
      ...casefile.uploads,
      ...p.result.uploads.filter(
        (u) => !casefile.uploads.some((x) => x.id === u.id)
      ),
    ]
    casefile.evidence = p.result.evidence
    casefile.pins = [...p.result.pins]
    for (const c of p.result.charges) {
      const o = offenceBySection(c.section)
      if (!o) continue
      const pc = casefile.propose(o, c.facts)
      scheduleRecital(pc)
    }
    casefile.selected = 0
  }

  async function replay(p: Preload): Promise<void> {
    moments = true
    await scrollToEnd()
    await sleep(1400)
    moments = false
    const t = casefile.say('assistant', '', true)
    t.tools = [...p.tools]
    // The charges land BEFORE the reply streams: the carousel fills while the
    // assistant is still "talking", which is the choreography the demo wants,
    // and a throttled background tab cannot hold the result hostage.
    applyResult(p)
    await stream(t, p.reply)
  }

  async function live(text: string): Promise<void> {
    const t = casefile.say('assistant', '', true)
    try {
      const res = await fetch('/api/interview', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ text, snapshot: casefile.snapshot() }),
      })
      const body = (await res.json().catch(() => ({}))) as {
        error?: string
        reply?: string
      }
      t.text =
        body.reply ??
        body.error ??
        `The interview route answered HTTP ${res.status}.`
    } catch (e) {
      t.text = `Could not reach the interview route: ${e instanceof Error ? e.message : String(e)}`
    } finally {
      t.streaming = false
      void scrollToEnd()
    }
  }

  async function submit(): Promise<void> {
    const text = draft.trim()
    if (!text || busy) return
    busy = true
    draft = ''
    if (files) {
      for (const f of Array.from(files)) {
        casefile.uploads = [
          ...casefile.uploads,
          { id: freshId('upload'), name: f.name, type: f.type, size: f.size },
        ]
      }
      files = null
    }
    casefile.say('user', text)
    await scrollToEnd()
    const p = matchPreload(text, PRELOADS)
    try {
      if (p) await replay(p)
      else await live(text)
    } finally {
      busy = false
      await scrollToEnd()
    }
  }

  function pick(p: Preload): void {
    draft = p.prompt
  }

  function onKey(e: KeyboardEvent): void {
    if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') {
      e.preventDefault()
      void submit()
    }
  }
</script>

<div class="chat" bind:this={log} aria-live="polite">
  {#if casefile.turns.length === 0}
    <p class="hint">
      Tell me what happened, who saw it, and what you have — statements,
      exhibits, CCTV. I will work through the Penal Code sections that fit, ask
      for what is missing, and frame each charge on the right.
    </p>
  {/if}
  {#each casefile.turns as t (t.id)}
    <div class={`bubble ${t.role}`}>
      {#if t.role === 'assistant'}
        {#if t.tools}
          {#each t.tools as tool, i (i)}
            <div class="tool-row">
              ⚙ {tool.name}({JSON.stringify(tool.args)}){tool.result !==
              undefined
                ? ' → ' + JSON.stringify(tool.result)
                : ''}
            </div>
          {/each}
        {/if}
        <!-- eslint-disable-next-line svelte/no-at-html-tags -->
        {@html html(t.text)}{#if t.streaming}<span class="cursor">▋</span>{/if}
      {:else}
        {t.text}
      {/if}
    </div>
  {/each}
  {#if moments}
    <Moments />
  {/if}
</div>

{#if casefile.uploads.length > 0}
  <p class="uploads">
    {#each casefile.uploads as u (u.id)}
      <span class="chip">📎 {u.name}</span>
    {/each}
  </p>
{/if}

<form
  class="composer"
  onsubmit={(e) => {
    e.preventDefault()
    void submit()
  }}
>
  <PreloadPicker preloads={PRELOADS} onPick={pick} />
  <textarea
    bind:value={draft}
    onkeydown={onKey}
    placeholder="What happened? Who is the complainant, when and where, and what do you have?"
    aria-label="Your message"
  ></textarea>
  <div class="composer-row">
    <input
      type="file"
      multiple
      bind:files
      aria-label="Attach statements or exhibits"
    />
    <button type="submit" class="submit" disabled={busy || !draft.trim()}>
      {busy ? 'Working…' : 'Send'}
    </button>
    <button type="button" class="linkish" onclick={() => casefile.reset()}
      >start over</button
    >
  </div>
</form>

<style>
  .hint {
    color: var(--muted);
    margin: 0;
  }
  .cursor {
    animation: moments-pulse 0.9s ease-in-out infinite;
  }
  .uploads {
    display: flex;
    gap: 0.35rem;
    flex-wrap: wrap;
    margin: 0.5rem 0 0;
  }
  .uploads .chip {
    background: var(--chip-bg);
    color: var(--chip-fg);
  }
</style>
