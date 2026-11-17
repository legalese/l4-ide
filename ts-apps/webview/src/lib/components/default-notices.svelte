<script lang="ts">
  import type { DefaultChangeNotice } from 'jl4-client-rpc'
  import { formatNoticeValue } from '$lib/deploy-compat'

  // The inputs whose usual value a redeploy changes: one line per input, the
  // rule, then the input with its old and new value. Shown in the deploy
  // review (before the deploy) and on the Deployments tab (after it, from the
  // service's report). Informational: nothing here blocks a deploy.
  let { items }: { items: DefaultChangeNotice[] } = $props()
</script>

<ul class="notice-list">
  {#each items as n}
    <li>
      <span class="ident">{n.function}</span><br />
      <span class="ident">{n.input}</span>:
      <span class="value">{formatNoticeValue(n.old)}</span>
      &rarr;
      <span class="value">{formatNoticeValue(n.new)}</span>
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
