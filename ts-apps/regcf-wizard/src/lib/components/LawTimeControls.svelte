<script lang="ts">
  import { formatIso, isIso } from '$lib/lawtime'

  /**
   * Ruling R8's pieces 1 and 3 as controls. Piece 2 — the disclosure — is in the
   * answer card, because that is where it has to be read.
   *
   * The fact date is a plain, required question a citizen can answer. The
   * override is deliberately buried in a <details>: R8 says it is "not for
   * citizens. For the auditor and the drafter of §5.0, whose questions cannot be
   * expressed as a fact date at all."
   */
  let {
    factDate,
    override,
    onFactDate,
    onOverride,
    error,
  }: {
    factDate: string
    override: string | null
    onFactDate: (v: string) => void
    onOverride: (v: string | null) => void
    error?: string
  } = $props()

  const overrideOn = $derived(override !== null)
</script>

<div class="field">
  <label for="fact-date">
    When did you, or when will you, invest? <span aria-hidden="true">*</span>
  </label>
  <p class="help" id="fact-date-help">
    Regulation Crowdfunding's investor limit has been amended more than once. We
    apply the rules that were in force on the day of the investment, not the
    rules as they read today.
  </p>
  <div class="input-wrap">
    <input
      id="fact-date"
      type="date"
      value={factDate}
      oninput={(e) => onFactDate((e.currentTarget as HTMLInputElement).value)}
      aria-describedby="fact-date-help"
      aria-invalid={error ? 'true' : undefined}
    />
  </div>
  {#if error}
    <p class="error" role="alert">{error}</p>
  {/if}
</div>

<details class="disclosure">
  <summary>Advanced: pin the rule date separately</summary>
  <div class="body">
    <p class="help">
      By default the rules applied are the rules in force on the date above. An
      auditor asking "was this lawful <em>then</em>?", or a drafter asking
      "which of my conclusions move when the next inflation adjustment lands?",
      needs the two clocks separated. Pinning a rule date here does exactly
      that, and the answer will say so.
    </p>
    <label class="toggle">
      <input
        type="checkbox"
        checked={overrideOn}
        onchange={(e) =>
          onOverride(
            (e.currentTarget as HTMLInputElement).checked ? factDate : null
          )}
      />
      <span>Apply the rules in force on a different date</span>
    </label>
    {#if overrideOn}
      <div class="input-wrap">
        <input
          type="date"
          value={override}
          oninput={(e) =>
            onOverride((e.currentTarget as HTMLInputElement).value)}
          aria-label="Rule date to apply"
        />
      </div>
      {#if override && isIso(override)}
        <p class="help">
          Rules as in force on {formatIso(override)}.
        </p>
      {:else}
        <p class="error" role="alert">Please give a date as YYYY-MM-DD</p>
      {/if}
    {/if}
  </div>
</details>

<style>
  .disclosure {
    border-top: 1px solid var(--hairline);
    padding: 0.7rem 0;
    margin-bottom: 1.5rem;
  }
  summary {
    cursor: pointer;
    font-weight: 600;
  }
  .body {
    padding-top: 0.6rem;
  }
  .toggle {
    display: flex;
    gap: 0.6rem;
    align-items: center;
    margin-bottom: 0.7rem;
    cursor: pointer;
  }
</style>
