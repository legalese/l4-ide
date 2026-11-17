<script lang="ts">
  import type { DefaultChangeNotice } from 'jl4-client-rpc'
  import { formatNoticeValue, noticeEnum } from '$lib/deploy-compat'

  // The inputs whose default a redeploy changes: one line per input, as
  // "rule · input · typically old → new: callers who leave input out will get
  // different answers." Shown in the deploy
  // review (before the deploy) and on the Deployments tab (after it, from the
  // service's report). Informational: nothing here blocks a deploy.
  let {
    items,
    schemas = [],
  }: {
    items: DefaultChangeNotice[]
    /** The rules' schemas, so that an enumerated input's constructors are
     *  spelled bare, as on the card. Without them, text is quoted. */
    schemas?: ReadonlyArray<{ name: string; parameters?: unknown }>
  } = $props()
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
      >: callers who leave
      <span class="ident">{n.input}</span> out will get different answers.
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
