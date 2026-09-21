<script lang="ts">
  /** The fourth-wall spinner: the demo says out loud that time is being skipped. */
  let { text = '… some moments later …' }: { text?: string } = $props()
</script>

<div class="moments" role="status" aria-live="polite">{text}</div>
