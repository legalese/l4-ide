<script lang="ts">
  import type { DagLayout } from '$lib/evidence/graph'
  import { forceLayoutDag } from '$lib/evidence/force-layout'

  /**
   * The evidence DAG: charge → elements → facts → sources, laid out by a
   * column-constrained force simulation (`force-layout.ts`) so each rank
   * spreads around the nodes it connects to. A dashed node is a GAP — an
   * element no fact supports, or a fact no source supports — and is what the
   * interview should ask about next. Pure SVG; presentational attributes only.
   */
  let { dag }: { dag: DagLayout } = $props()
  const out = $derived(forceLayoutDag(dag))

  function edgePath(e: (typeof out.edges)[number]): string {
    const x1 = e.from.x + e.from.w / 2
    const y1 = e.from.y
    const x2 = e.to.x - e.to.w / 2
    const y2 = e.to.y
    const mx = (x1 + x2) / 2
    return `M ${x1} ${y1} C ${mx} ${y1}, ${mx} ${y2}, ${x2} ${y2}`
  }
  const clip = (s: string, n: number): string =>
    s.length > n ? s.slice(0, n - 1) + '…' : s
  const chars = (w: number): number => Math.floor((w - 12) / 6.4)
</script>

<div class="dag-wrap">
  <svg
    class="dag"
    viewBox={`0 0 ${out.width} ${out.height}`}
    width={out.width}
    height={out.height}
    role="img"
    aria-label="Evidence graph: charge, elements, facts, sources"
  >
    <g font-size="11" font-weight="700" fill="currentColor" opacity="0.55">
      <text x="14" y="10">charge</text>
      <text x="204" y="10">elements</text>
      <text x="394" y="10">facts</text>
      <text x="584" y="10">sources</text>
    </g>
    {#each out.edges as e (e.from.id + '>' + e.to.id)}
      <path
        d={edgePath(e)}
        fill="none"
        stroke="currentColor"
        stroke-opacity="0.32"
        stroke-width="1.2"
      />
    {/each}
    {#each out.nodes as n (n.id)}
      <g transform={`translate(${n.x - n.w / 2} ${n.y - n.h / 2})`}>
        <rect
          width={n.w}
          height={n.h}
          rx={n.h / 2}
          fill={n.gap ? 'none' : 'currentColor'}
          fill-opacity={n.gap ? 0 : 0.07}
          stroke={n.gap ? '#c8376a' : 'currentColor'}
          stroke-opacity={n.gap ? 0.9 : 0.45}
          stroke-dasharray={n.gap ? '4 3' : undefined}
        />
        <text
          x={n.w / 2}
          y={n.sub ? 15 : n.h / 2 + 4}
          font-size="11"
          text-anchor="middle"
          fill="currentColor"
        >
          {clip(n.label, chars(n.w))}
        </text>
        {#if n.sub}
          <text
            x={n.w / 2}
            y="28"
            font-size="9.5"
            text-anchor="middle"
            fill="currentColor"
            opacity="0.65"
          >
            {clip(n.sub, chars(n.w) + 4)}
          </text>
        {/if}
        <title
          >{n.gap
            ? 'No evidence yet — ask about this'
            : n.label + (n.sub ? ' — ' + n.sub : '')}</title
        >
      </g>
    {/each}
  </svg>
</div>

<style>
  .dag-wrap {
    overflow-x: auto;
  }
  .dag {
    display: block;
    color: var(--ink);
    max-width: 100%;
    height: auto;
  }
</style>
