<script lang="ts">
  import type { DefaultChangeNotice } from 'jl4-client-rpc'
  import { formatNoticeValue, noticeEnum } from '$lib/deploy-compat'

  // The inputs whose default a redeploy changes: one line per input, as
  // "rule · input · typically old → new: callers who leave input out will get
  // different answers." Shown in the deploy review (before the deploy) and
  // after it. The tail of each line follows what is known of the deploy: `will`
  // (it is going ahead, or was applied), `would` (it was rejected, so nothing
  // changed) or `maybe` (its result could not be read). Informational: nothing
  // here blocks a deploy.
  let {
    items,
    schemas = [],
    mood = 'will',
  }: {
    items: DefaultChangeNotice[]
    mood?: 'will' | 'would' | 'maybe'
    /** The rules' schemas, so that an enumerated input's constructors are
     *  spelled bare, as on the card. Without them, text is quoted. */
    schemas?: ReadonlyArray<{ name: string; parameters?: unknown }>
  } = $props()

  let lead = $derived(
    mood === 'maybe'
      ? 'if the deploy was applied, callers who leave'
      : 'callers who leave'
  )
  let verb = $derived(mood === 'would' ? 'would have got' : 'will get')
</script>

<ul class="notice-list">
  {#each items as n}
    <li>
      <span class="ident">{n.function}</span> &middot;
      <span class="ident">{n.input}</span> &middot; typically
      <span class="value"
        >{formatNoticeValue(n.old, noticeEnum(schemas, n))}</span
      >
      &rarr;
      <span class="value"
        >{formatNoticeValue(n.new, noticeEnum(schemas, n))}</span
      >: {lead}
      <span class="ident">{n.input}</span>
      out {verb} different answers.
    </li>
  {/each}
</ul>

<style>
  .notice-list {
    padding-left: 16px;
    margin: 0;
    color: var(--vscode-foreground);
  }

  .notice-list li {
    margin-bottom: 10px;
  }

  .ident {
    font-family: var(--vscode-editor-font-family, monospace);
    font-size: 0.92em;
    color: var(--l4-tok-identifier, #4ec9b0);
  }

  .value {
    font-family: var(--vscode-editor-font-family, monospace);
    font-size: 0.92em;
  }
</style>
