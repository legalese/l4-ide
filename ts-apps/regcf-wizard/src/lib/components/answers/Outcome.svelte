<script lang="ts">
  /**
   * The one badge every Reg CF answer card carries.
   *
   * The housing wizard's MUST/MAY distinction has no Reg CF analogue
   * (CORPUS-TRACK.md §3.5): here the equivalent is "qualifies / which limb
   * failed / which rule". So the badge states the outcome in words, and colour
   * is never the sole cue — there is an icon, a word and an aria-label as well.
   *
   * Colour is applied ONLY through the static .outcome-* classes in app.css,
   * never an inline style="", so the strict CSP `style-src 'self'` holds.
   */
  let {
    tone,
    word,
    line,
  }: {
    tone: 'yes' | 'no' | 'neither'
    word: string
    line: string
  } = $props()

  const icon = $derived(tone === 'yes' ? '✓' : tone === 'no' ? '✕' : '•')
</script>

<div
  class="outcome"
  class:outcome-clear={tone === 'yes'}
  class:outcome-must={tone === 'no'}
  class:outcome-may={tone === 'neither'}
  role="status"
  aria-label={word + '. ' + line}
>
  <p class="word"><span aria-hidden="true">{icon}</span> {word}</p>
  <p class="line">{line}</p>
</div>

<style>
  .outcome {
    border: 2px solid var(--hairline);
    border-radius: 12px;
    padding: 1.1rem 1.3rem;
    margin-bottom: 1.4rem;
  }
  .word {
    text-transform: uppercase;
    letter-spacing: 0.07em;
    font-size: 0.82rem;
    font-weight: 800;
    margin: 0 0 0.4rem;
  }
  .line {
    font-size: 1.15rem;
    font-weight: 700;
    line-height: 1.35;
    margin: 0;
  }
</style>
