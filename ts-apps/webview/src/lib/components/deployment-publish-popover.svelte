<script lang="ts">
  // Marketplace "Publish" pop-over (VSCODE-PUBLISH-SPEC.md §2). Same shell
  // as deployment-integrate-popover: absolute backdrop inside
  // `.tab-content-frame`, Esc/backdrop-click to close. Two views:
  //   - wizard (4 steps): visibility → access mode → listing → terms
  //   - manage: shown for already-published deployments (state, change
  //     mode, unpublish with inline confirm)
  import type {
    SidebarMarketplaceInfo,
    SidebarPublishParams,
  } from 'jl4-client-rpc'

  const TERMS_VERSION = '2026-08'
  const TERMS_URL = 'https://legalese.com/provable/publisher-terms'

  let {
    deploymentId,
    description = '',
    marketplace,
    orgSlug = '',
    onClose,
    onPublish,
    onUnpublish,
  }: {
    deploymentId: string
    description?: string
    marketplace?: SidebarMarketplaceInfo
    orgSlug?: string
    onClose: () => void
    onPublish: (params: SidebarPublishParams) => Promise<{
      success: boolean
      live?: boolean
      url?: string
      error?: string
    }>
    onUnpublish: () => Promise<{ success: boolean; error?: string }>
  } = $props()

  type View = 'manage' | 'wizard' | 'done'
  let view: View = $state(marketplace?.published ? 'manage' : 'wizard')
  let step = $state(1)
  let busy = $state(false)
  let errorMsg = $state('')
  let confirmUnpublish = $state(false)
  let doneLive = $state(false)
  let doneUrl = $state('')

  // ── Form state (prefilled per spec §2 step 3) ──────────────────────────
  const hasDescription = description.trim().length > 0
  let mode: 'account' | 'public' = $state(
    marketplace?.mode === 'public' ? 'public' : 'account'
  )
  let displayName = $state(
    deploymentId.replace(/[-_]+/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase())
  )
  let summary = $state(
    (description.split(/(?<=[.!?])\s/)[0] ?? '').slice(0, 200)
  )
  let category = $state('')
  let tags = $state('')
  let license = $state('All rights reserved')
  let jurisdiction = $state('')
  let supportUrl = $state('')
  let termsAccepted = $state(false)

  const listingValid = $derived(
    displayName.trim().length > 0 &&
      summary.trim().length > 0 &&
      summary.length <= 200
  )

  const stepValid = $derived(
    step === 1
      ? hasDescription
      : step === 2
        ? true
        : step === 3
          ? listingValid
          : termsAccepted
  )

  async function submit(): Promise<void> {
    busy = true
    errorMsg = ''
    const res = await onPublish({
      deploymentId,
      mode,
      termsVersion: TERMS_VERSION,
      listing: {
        displayName: displayName.trim(),
        summary: summary.trim(),
        ...(category ? { category } : {}),
        ...(tags.trim()
          ? {
              tags: tags
                .split(',')
                .map((t) => t.trim())
                .filter(Boolean)
                .slice(0, 5),
            }
          : {}),
        ...(license.trim() ? { license: license.trim() } : {}),
        ...(jurisdiction.trim() ? { jurisdiction: jurisdiction.trim() } : {}),
        ...(supportUrl.trim() ? { supportUrl: supportUrl.trim() } : {}),
      },
    })
    busy = false
    if (!res.success) {
      errorMsg = res.error ?? 'Publish failed.'
      return
    }
    doneLive = res.live === true
    doneUrl = res.url ?? ''
    view = 'done'
  }

  async function unpublish(): Promise<void> {
    busy = true
    errorMsg = ''
    const res = await onUnpublish()
    busy = false
    if (!res.success) {
      errorMsg = res.error ?? 'Unpublish failed.'
      confirmUnpublish = false
      return
    }
    onClose()
  }

  function onKeydown(e: KeyboardEvent): void {
    if (e.key === 'Escape') {
      e.stopPropagation()
      onClose()
    }
  }
</script>

<svelte:window on:keydown={onKeydown} />

<div
  class="publish-backdrop"
  role="presentation"
  onclick={onClose}
  onkeydown={null}
>
  <div
    class="publish-dialog"
    role="dialog"
    aria-modal="true"
    aria-label="Publish deployment"
    tabindex="-1"
    onclick={(e) => e.stopPropagation()}
    onkeydown={null}
  >
    <div class="dialog-header">
      <span class="dialog-title">
        {#if view === 'manage'}Published: <strong>{deploymentId}</strong>
        {:else}Publish <strong>{deploymentId}</strong>{/if}
      </span>
      <button
        class="dialog-close"
        onclick={onClose}
        title="Close"
        aria-label="Close">✕</button
      >
    </div>

    <div class="dialog-body">
      {#if view === 'manage'}
        <div class="section">
          <div class="section-label">Status</div>
          <p class="copy">
            {#if marketplace?.live}
              Live on the marketplace in
              <strong>{marketplace?.mode}</strong> mode.
            {:else}
              Submitted in <strong>{marketplace?.mode}</strong> mode —
              <strong>pending first-publisher review</strong>. Not callable by
              other organisations until approved.
            {/if}
          </p>
          {#if marketplace?.mode === 'unlisted' && marketplace?.allowedOrgs?.length}
            <p class="copy">
              Shared privately with: {marketplace.allowedOrgs.join(', ')}
            </p>
          {/if}
          <p class="copy">
            Listing: <a href="https://skills.legalese.cloud/{orgSlug}"
              >skills.legalese.cloud/{orgSlug}</a
            >
          </p>
        </div>
        <div class="section">
          <div class="btn-row">
            <button
              class="btn secondary"
              onclick={() => {
                view = 'wizard'
                step = 2
              }}>Change mode</button
            >
            {#if !confirmUnpublish}
              <button
                class="btn danger"
                onclick={() => (confirmUnpublish = true)}>Unpublish</button
              >
            {/if}
          </div>
          {#if confirmUnpublish}
            <div class="warn-panel">
              Unpublishing removes this skill from the catalog and revokes all
              cross-org access within about a minute. Reviews are retained;
              republishing does not restore install counts.
              <div class="btn-row">
                <button class="btn danger" disabled={busy} onclick={unpublish}
                  >{busy ? 'Unpublishing…' : 'Confirm unpublish'}</button
                >
                <button
                  class="btn secondary"
                  onclick={() => (confirmUnpublish = false)}
                  >Keep published</button
                >
              </div>
            </div>
          {/if}
          {#if errorMsg}<p class="error">{errorMsg}</p>{/if}
        </div>
      {:else if view === 'done'}
        <div class="section">
          {#if doneLive}
            <div class="section-label">Published — live now</div>
            <p class="copy">
              Anyone{mode === 'public' ? '' : ' with a Legalese Cloud account'}
              can now discover and call these rules.
            </p>
          {:else}
            <div class="section-label">Submitted — pending review</div>
            <p class="copy">
              First-time publishers are reviewed before going live. Your skill
              is not callable by other organisations until approved.
            </p>
          {/if}
          {#if doneUrl}
            <p class="copy">Listing: <a href={doneUrl}>{doneUrl}</a></p>
          {/if}
          <div class="btn-row">
            <button class="btn primary" onclick={onClose}>Done</button>
          </div>
        </div>
      {:else}
        <div class="steps" aria-hidden="true">
          {#each ['Visibility', 'Access', 'Listing', 'Terms'] as label, i (label)}
            <span class="step" class:active={step === i + 1}>{label}</span>
          {/each}
        </div>

        {#if step === 1}
          <div class="section">
            <div class="section-label">What becomes visible</div>
            <p class="copy">
              Publishing makes the following visible to anyone who can access
              this skill:
            </p>
            <ul class="copy">
              <li>the generated SKILL.md and your Intended-use text,</li>
              <li>function names, descriptions, and schemas,</li>
              <li>
                <strong>the deployment's .l4 source files</strong> — auditable rules
                are part of the product; anyone who can call the skill can read its
                rules.
              </li>
            </ul>
            <p class="copy">
              Not visible: execution traces, your org configuration, your other
              deployments.
            </p>
            {#if !hasDescription}
              <div class="warn-panel">
                This deployment has no "Intended use" description. Add one and
                redeploy before publishing — it becomes the skill's load-bearing
                summary for AI agents.
              </div>
            {/if}
          </div>
        {:else if step === 2}
          <div class="section">
            <div class="section-label">Who can call it</div>
            <label class="radio">
              <input type="radio" bind:group={mode} value="account" />
              <span>
                <strong>Requires a Legalese Cloud account</strong> (recommended)
                <span class="hint"
                  >Callers are billed for their own usage; you'll earn revenue
                  share when that ships. On the free tier, cross-org calls are
                  capped org-wide; any paid plan removes the cap.</span
                >
              </span>
            </label>
            <label class="radio">
              <input type="radio" bind:group={mode} value="public" />
              <span>
                <strong>Public — no account needed</strong>
                <span class="hint">Anyone on the internet can call this.</span>
              </span>
            </label>
            {#if mode === 'public'}
              <div class="warn-panel">
                Public evaluations <strong>bill to your org</strong> and count against
                your org's own daily request limit, exactly like your own traffic.
              </div>
            {/if}
          </div>
        {:else if step === 3}
          <div class="section">
            <div class="section-label">Listing</div>
            <label class="field"
              >Display name
              <input type="text" bind:value={displayName} />
            </label>
            <label class="field"
              >Summary <span class="hint">({summary.length}/200)</span>
              <textarea rows="2" maxlength="200" bind:value={summary}
              ></textarea>
            </label>
            <label class="field"
              >Category
              <select bind:value={category}>
                <option value="">—</option>
                <option value="tax">Tax</option>
                <option value="employment">Employment</option>
                <option value="housing">Housing</option>
                <option value="trade">Trade</option>
                <option value="compliance">Compliance</option>
                <option value="other">Other</option>
              </select>
            </label>
            <label class="field"
              >Tags <span class="hint">(comma-separated, max 5)</span>
              <input
                type="text"
                bind:value={tags}
                placeholder="e.g. singapore, penal code"
              />
            </label>
            <label class="field"
              >License
              <input type="text" bind:value={license} />
            </label>
            <label class="field"
              >Jurisdiction
              <input
                type="text"
                bind:value={jurisdiction}
                placeholder="e.g. Singapore"
              />
            </label>
            <label class="field"
              >Support URL
              <input
                type="text"
                bind:value={supportUrl}
                placeholder="https://…"
              />
            </label>
          </div>
        {:else}
          <div class="section">
            <div class="section-label">Publisher terms</div>
            <p class="copy">
              You are publishing computational rules others may rely on. The
              listing carries a mandatory disclaimer; you remain responsible for
              the rules' content, and the platform may suspend listings that are
              reported and not remedied.
            </p>
            <label class="radio">
              <input type="checkbox" bind:checked={termsAccepted} />
              <span
                >I agree to the
                <a href={TERMS_URL}>Publisher Agreement</a>
                ({TERMS_VERSION})</span
              >
            </label>
          </div>
        {/if}

        {#if errorMsg}<p class="error">{errorMsg}</p>{/if}

        <div class="btn-row nav">
          {#if step > 1}
            <button class="btn secondary" onclick={() => (step -= 1)}
              >Back</button
            >
          {/if}
          {#if step < 4}
            <button
              class="btn primary"
              disabled={!stepValid}
              onclick={() => (step += 1)}>Continue</button
            >
          {:else}
            <button
              class="btn primary"
              disabled={!stepValid || busy}
              onclick={submit}>{busy ? 'Publishing…' : 'Publish'}</button
            >
          {/if}
        </div>
      {/if}
    </div>
  </div>
</div>

<style>
  .publish-backdrop {
    position: absolute;
    inset: 0;
    z-index: 1000;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 32px;
    box-sizing: border-box;
    background: rgba(0, 0, 0, 0.4);
  }

  .publish-dialog {
    width: 100%;
    max-width: 520px;
    max-height: 100%;
    display: flex;
    flex-direction: column;
    background: var(--vscode-sideBar-background);
    border: 1px solid
      var(
        --vscode-menu-border,
        var(--vscode-widget-border, rgba(128, 128, 128, 0.35))
      );
    border-radius: 6px;
    box-shadow: 0 0 36px rgba(0, 0, 0, 0.95);
    box-sizing: border-box;
  }

  .dialog-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 16px 20px;
    border-bottom: 1px solid
      var(--vscode-panel-border, rgba(128, 128, 128, 0.2));
  }
  .dialog-title {
    font-size: 1em;
  }
  .dialog-close {
    background: none;
    border: none;
    color: var(--vscode-foreground);
    cursor: pointer;
    opacity: 0.6;
    padding: 2px;
    font-size: 1em;
    line-height: 1;
  }
  .dialog-close:hover {
    opacity: 1;
  }

  .dialog-body {
    padding: 4px 20px 16px;
    overflow-y: auto;
  }

  .steps {
    display: flex;
    gap: 12px;
    padding: 12px 0 0;
    font-size: 0.85em;
    color: var(--vscode-descriptionForeground);
  }
  .step.active {
    color: var(--vscode-foreground);
    font-weight: 600;
    border-bottom: 2px solid #c8376a;
  }

  .section {
    padding: 14px 0;
  }
  .section-label {
    font-size: 0.9em;
    font-weight: 600;
    margin-bottom: 8px;
  }

  .copy {
    font-size: 0.9em;
    color: var(--vscode-foreground);
    margin: 6px 0;
  }
  ul.copy {
    padding-left: 18px;
  }
  .copy a {
    color: #c8376a;
  }
  .hint {
    display: block;
    font-size: 0.9em;
    color: var(--vscode-descriptionForeground);
    font-weight: 400;
  }

  .warn-panel {
    margin-top: 10px;
    padding: 10px 12px;
    font-size: 0.9em;
    border-radius: 4px;
    background: var(
      --vscode-inputValidation-warningBackground,
      rgba(180, 130, 0, 0.15)
    );
    border: 1px solid
      var(--vscode-inputValidation-warningBorder, rgba(180, 130, 0, 0.6));
  }

  .radio {
    display: flex;
    gap: 8px;
    align-items: flex-start;
    margin: 10px 0;
    font-size: 0.9em;
    cursor: pointer;
  }
  .radio input {
    margin-top: 2px;
  }

  .field {
    display: block;
    margin: 10px 0;
    font-size: 0.9em;
  }
  .field input[type='text'],
  .field textarea,
  .field select {
    display: block;
    width: 100%;
    margin-top: 4px;
    padding: 6px 8px;
    box-sizing: border-box;
    background: var(--vscode-input-background);
    color: var(--vscode-input-foreground);
    border: 1px solid var(--vscode-input-border, transparent);
    border-radius: 4px;
    font-family: inherit;
    font-size: inherit;
  }

  .btn-row {
    display: flex;
    gap: 8px;
    margin-top: 12px;
  }
  .btn-row.nav {
    justify-content: flex-end;
    padding-bottom: 8px;
  }

  .btn {
    padding: 6px 14px;
    border-radius: 4px;
    font-size: 0.9em;
    cursor: pointer;
    border: 1px solid transparent;
  }
  .btn:disabled {
    opacity: 0.5;
    cursor: default;
  }
  .btn.primary {
    background: #c8376a;
    color: #fff;
    border: none;
  }
  .btn.primary:hover:not(:disabled) {
    background: #d94d7e;
  }
  .btn.secondary {
    background: var(--vscode-button-secondaryBackground, transparent);
    color: var(--vscode-button-secondaryForeground, var(--vscode-foreground));
    border: 1px solid var(--vscode-widget-border, rgba(128, 128, 128, 0.35));
  }
  .btn.danger {
    background: transparent;
    color: var(--vscode-errorForeground, #f48771);
    border: 1px solid var(--vscode-errorForeground, #f48771);
  }

  .error {
    font-size: 0.9em;
    color: var(--vscode-errorForeground, #f48771);
    margin-top: 8px;
  }
</style>
