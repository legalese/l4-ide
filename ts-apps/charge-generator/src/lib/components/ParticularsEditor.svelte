<script lang="ts">
  import type { StringField } from '$lib/charges/schema-fill'

  /**
   * The CPC s 124 particulars and the "to wit" strings: every STRING/enum field
   * of the facts record, editable. The ladder owns the booleans; this owns the
   * words the charge recites. Edits go through `onChange` so the parent can
   * schedule the recital round trip.
   */
  let {
    fields,
    facts,
    onChange,
  }: {
    fields: readonly StringField[]
    facts: Record<string, unknown>
    onChange: (path: readonly string[], value: string) => void
  } = $props()

  function valueAt(path: readonly string[]): string {
    let cur: unknown = facts
    for (const k of path) {
      if (typeof cur !== 'object' || cur === null) return ''
      cur = (cur as Record<string, unknown>)[k]
    }
    return typeof cur === 'string' ? cur : ''
  }
</script>

<div class="particulars">
  {#each fields as f (f.path.join('/'))}
    {@const id = 'p-' + f.path.join('-').replace(/[^a-z0-9-]/gi, '_')}
    <label for={id}>
      <span class="name">{f.path.at(-1)}</span>
      {#if f.enum}
        <select
          {id}
          value={valueAt(f.path)}
          onchange={(e) =>
            onChange(f.path, (e.currentTarget as HTMLSelectElement).value)}
        >
          {#each f.enum as opt (opt)}
            <option value={opt}>{opt}</option>
          {/each}
        </select>
      {:else}
        <input
          {id}
          type="text"
          value={valueAt(f.path)}
          placeholder={f.description}
          title={f.description}
          onchange={(e) =>
            onChange(f.path, (e.currentTarget as HTMLInputElement).value)}
        />
      {/if}
    </label>
  {/each}
</div>

<style>
  .particulars {
    display: grid;
    gap: 0.45rem;
  }
  label {
    display: grid;
    grid-template-columns: 11rem 1fr;
    gap: 0.5rem;
    align-items: center;
    font-size: 0.9rem;
  }
  .name {
    color: var(--muted);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  input,
  select {
    border: 1px solid var(--hairline);
    border-radius: 8px;
    padding: 0.35rem 0.5rem;
    font: inherit;
    font-size: 0.9rem;
    background: var(--surface);
    color: var(--ink);
    min-width: 0;
  }
  input:focus,
  select:focus {
    outline: none;
    border-color: var(--brand);
  }
</style>
