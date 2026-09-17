<script lang="ts">
  import type { DagLayout } from '$lib/evidence/graph'

  /**
   * The evidence DAG, drawn as four columns: charge → elements → facts →
   * sources. A dashed node is a GAP — an element no fact supports, or a fact
   * no source supports — and is what the interview should ask about next.
   * Pure SVG from a pure layout; presentational attributes only (CSP).
   */
  let { dag }: { dag: DagLayout } = $props()

  const COL_W = 190
  const ROW_H = 54
  const PAD = 12
  const BOX_H = 40
  const width = COL_W * 4 + PAD * 2
  const height = $derived(PAD * 2 + Math.max(1, dag.rows) * ROW_H)

  const x = (col: number): number => PAD + col * COL_W
  const y = (row: number): number => PAD + row * ROW_H
  const pos = $derived(
    new Map(dag.nodes.map((n) => [n.id, { x: x(n.col), y: y(n.row) }]))
  )

  function edgePath(from: string, to: string): string {
    const a = pos.get(from)
    const b = pos.get(to)
    if (!a || !b) return ''
    const x1 = a.x + COL_W - 16
    const y1 = a.y + BOX_H / 2
    const x2 = b.x
    const y2 = b.y + BOX_H / 2
    const mx = (x1 + x2) / 2
    return `M ${x1} ${y1} C ${mx} ${y1}, ${mx} ${y2}, ${x2} ${y2}`
  }

  const clip = (s: string, n: number): string =>
    s.length > n ? s.slice(0, n - 1) + '…' : s
</script>

<svg
  class="dag"
  viewBox={`0 0 ${width} ${height}`}
  width="100%"
  role="img"
  aria-label="Evidence graph: charge, elements, facts, sources"
>
  <g
    class="heads"
    font-size="11"
    font-weight="700"
    fill="currentColor"
    opacity="0.6"
  >
    <text x={x(0)} y="9">charge</text>
    <text x={x(1)} y="9">elements</text>
    <text x={x(2)} y="9">facts</text>
    <text x={x(3)} y="9">sources</text>
  </g>
  {#each dag.edges as e (e.from + '>' + e.to)}
    <path
      d={edgePath(e.from, e.to)}
      fill="none"
      stroke="currentColor"
      stroke-opacity="0.35"
      stroke-width="1.2"
    />
  {/each}
  {#each dag.nodes as n (n.id)}
    {@const p = pos.get(n.id)}
    {#if p}
      <g transform={`translate(${p.x} ${p.y})`}>
        <rect
          width={COL_W - 16}
          height={BOX_H}
          rx="7"
          fill={n.gap ? 'none' : 'currentColor'}
          fill-opacity={n.gap ? 0 : 0.06}
          stroke={n.gap ? '#c8376a' : 'currentColor'}
          stroke-opacity={n.gap ? 0.9 : 0.4}
          stroke-dasharray={n.gap ? '4 3' : undefined}
        />
        <text x="8" y={n.sub ? 16 : 24} font-size="11.5" fill="currentColor">
          {clip(n.label, 30)}
        </text>
        {#if n.sub}
          <text x="8" y="31" font-size="10" fill="currentColor" opacity="0.65"
            >{clip(n.sub, 32)}</text
          >
        {/if}
        {#if n.gap}
          <title>No evidence yet — ask about this</title>
        {:else}
          <title>{n.label}{n.sub ? ' — ' + n.sub : ''}</title>
        {/if}
      </g>
    {/if}
  {/each}
</svg>

<style>
  .dag {
    display: block;
    color: var(--ink);
    max-width: 100%;
    height: auto;
  }
</style>
