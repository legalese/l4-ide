<script lang="ts">
  import type { AiCloudSessionState } from 'jl4-client-rpc'

  // A cloud session's state as its cloud outline: a band sweeps
  // along it while the view loads it (quickly), while its compute starts
  // (slowly) and, in crimson, while the agent works; it is white when
  // running, amber when the agent asked a question, gray asleep (or
  // parked). The state's wording, or the progress, is the tooltip and
  // the accessible name.
  let {
    state,
    loading = false,
    detail = null,
    size = 14,
  }: {
    state: AiCloudSessionState | 'gone'
    /** An opened session whose state isn't known yet. */
    loading?: boolean
    /** Progress (files uploading or being added): the tooltip. */
    detail?: string | null
    size?: number
  } = $props()

  const shimmerId = `cloud-shimmer-${Math.random().toString(36).slice(2)}`
  const reducedMotion =
    typeof window !== 'undefined' &&
    window.matchMedia?.('(prefers-reduced-motion: reduce)').matches

  type Look = {
    tone: 'dim' | 'bright' | 'active' | 'warn' | 'gone'
    /** The sweep's period, or null for a still outline. */
    sweep: string | null
    label: string
  }
  const look = $derived.by((): Look => {
    if (loading) {
      return { tone: 'bright', sweep: '1.4s', label: 'Loading the session…' }
    }
    switch (state) {
      case 'starting':
        return {
          tone: 'bright',
          sweep: '2.6s',
          label: 'Starting cloud compute: this can take a minute',
        }
      case 'busy':
        return {
          tone: 'active',
          sweep: '2.6s',
          label: 'Busy: the agent is working',
        }
      case 'running':
        return {
          tone: 'bright',
          sweep: null,
          label: 'Running: ready for your next message',
        }
      case 'waiting':
        return {
          tone: 'warn',
          sweep: null,
          label: 'Waiting: the agent asked you a question',
        }
      case 'gone':
        return {
          tone: 'gone',
          sweep: null,
          label: 'This session no longer exists',
        }
      default:
        // Sleeping, or parked (its key chain ended): either way the next
        // message starts it.
        return {
          tone: 'dim',
          sweep: null,
          label: 'Sleeping: your next message starts it again',
        }
    }
  })
  const label = $derived(!loading && detail ? detail : look.label)
  const sweeping = $derived(look.sweep !== null && !reducedMotion)
</script>

<span class="cloud-status" role="img" aria-label={label} title={label}>
  <svg
    class="cloud-icon tone-{look.tone}"
    style:width="{size}px"
    style:height="{size}px"
    viewBox="0 0 16 16"
    aria-hidden="true"
  >
    {#if sweeping}
      <!-- A bright band sweeps along a dimmed outline. -->
      <defs>
        <linearGradient id={shimmerId} x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stop-color="currentColor" stop-opacity="0.3" />
          <stop offset="0.5" stop-color="currentColor" stop-opacity="1" />
          <stop offset="1" stop-color="currentColor" stop-opacity="0.3" />
          <animateTransform
            attributeName="gradientTransform"
            type="translate"
            from="-1 0"
            to="1 0"
            dur={look.sweep}
            repeatCount="indefinite"
          />
        </linearGradient>
      </defs>
    {/if}
    <path
      d="M4.6 12.5a2.6 2.6 0 0 1-.3-5.2 3.4 3.4 0 0 1 6.6-1 2.7 2.7 0 0 1 .6 6.2z"
      stroke={sweeping ? `url(#${shimmerId})` : 'currentColor'}
      stroke-width="1.2"
      fill="none"
      stroke-linejoin="round"
    />
  </svg>
</span>

<style>
  .cloud-status {
    display: inline-flex;
    flex-shrink: 0;
  }
  .cloud-icon {
    color: var(--vscode-descriptionForeground);
    transition:
      color 0.2s ease-out,
      opacity 0.2s ease-out;
  }
  .cloud-icon.tone-bright {
    color: var(--vscode-foreground);
  }
  .cloud-icon.tone-active {
    color: #c8376a;
  }
  .cloud-icon.tone-warn {
    color: var(--vscode-editorWarning-foreground, #cca700);
  }
  .cloud-icon.tone-gone {
    opacity: 0.4;
  }
</style>
