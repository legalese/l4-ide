<script lang="ts">
  /**
   * Progressive disclosure in the answer card: the reasoning, the tail
   * obligations and the caveats are all present in every response and all
   * verbose (the raise check returns four caveats, five things to line up and
   * four post-close duties — 13 paragraphs). Showing them at once buries the
   * answer; hiding them loses the citation trail that is the point of the
   * exercise. A native <details> keeps them one keystroke away, is announced by
   * screen readers, prints expanded, and needs no JavaScript.
   */
  let {
    summary,
    count,
    open = false,
    children,
  }: {
    summary: string
    count?: number
    open?: boolean
    children: import('svelte').Snippet
  } = $props()
</script>

<details class="disclosure" {open}>
  <summary>
    {summary}{#if count !== undefined}<span class="count">{count}</span>{/if}
  </summary>
  <div class="body">{@render children()}</div>
</details>

<style>
  .disclosure {
    border-top: 1px solid var(--hairline);
    padding: 0.7rem 0;
  }
  summary {
    cursor: pointer;
    font-weight: 600;
    list-style-position: outside;
  }
  summary:focus-visible {
    outline: 3px solid var(--focus);
    outline-offset: 2px;
  }
  .count {
    margin-left: 0.45rem;
    font-weight: 700;
    font-size: 0.82rem;
    padding: 0.05rem 0.45rem;
    border-radius: 999px;
    background: var(--chip-bg);
    color: var(--chip-fg);
  }
  .body {
    padding-top: 0.6rem;
  }
</style>
