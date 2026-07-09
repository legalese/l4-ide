<script lang="ts">
  import type { FieldNode } from '$lib/schema/types'

  let { node }: { node: FieldNode } = $props()
</script>

<div class="field unsupported" role="note">
  <p class="legend-like">{node.label}</p>
  <p class="help">
    This question can’t be shown here. Please contact us so we can help you with
    it.
  </p>
</div>

<style>
  .unsupported {
    border: 2px dashed var(--hairline);
    border-radius: 10px;
    padding: 0.9rem 1.1rem;
  }
  .legend-like {
    font-weight: 600;
    margin: 0 0 0.4rem;
  }
</style>
