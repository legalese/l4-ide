<script lang="ts">
  import type { ExportedFunctionInfo, FunctionParameter } from 'jl4-client-rpc'
  import {
    PRESUMPTION_NOTE,
    anyInputHasDefault,
    inputStatus,
  } from '$lib/param-defaults'
  import { publishedInputSchema } from '$lib/published-schema'

  let {
    func,
    expanded = false,
    onToggle,
    onReveal,
  }: {
    func: ExportedFunctionInfo
    expanded?: boolean
    onToggle?: () => void
    onReveal?: () => void
  } = $props()

  function toggle() {
    if (onToggle) onToggle()
  }

  function paramEntries(
    params: ExportedFunctionInfo['parameters']
  ): [string, FunctionParameter][] {
    const order = params.required ?? Object.keys(params.properties ?? {})
    const allKeys = new Set([...order, ...Object.keys(params.properties ?? {})])
    return Array.from(allKeys)
      .filter((k) => params.properties?.[k] != null)
      .map((k) => [k, params.properties[k]])
  }

  let paramCount = $derived(
    Object.keys(func.parameters?.properties ?? {}).length
  )

  function isRequired(
    name: string,
    params: ExportedFunctionInfo['parameters']
  ): boolean {
    return params.required?.includes(name) ?? false
  }

  /** Inputs the file gives a default that the service does not publish
   *  (an `ASSUME`'s), named by the language server. */
  let unpublished = $derived(new Set(func.unpublishedDefaults ?? []))

  /** Whether any input shows a default, which is when the presumption switch
   *  is worth a line. */
  let showsDefault = $derived(anyInputHasDefault([func]))

  /** The inputs' schema as this card was given it, less the keys only the
   *  language server and the service use (alias, propertyOrder, x-l4-type,
   *  x-sanitized-name), which the OpenAPI document and the MCP tool list drop:
   *  what a client is shown. Never composed here. */
  let publishedSchema = $derived(
    JSON.stringify(publishedInputSchema(func.parameters), null, 2)
  )

  function hasNestedProps(param: FunctionParameter): boolean {
    return (
      param.properties !== undefined && Object.keys(param.properties).length > 0
    )
  }
</script>

{#snippet nestedProperties(
  props: Record<string, FunctionParameter>,
  depth: number,
  requiredFields: string[] | undefined,
  parentPath: string
)}
  <div class="nested-props">
    {#each Object.entries(props) as [nestedName, nestedParam]}
      {@const path = `${parentPath}.${nestedName}`}
      {@const status = inputStatus(
        path,
        nestedParam,
        requiredFields?.includes(nestedName) ?? false
      )}
      <div class="param-row nested">
        <span class="param-name">{path}</span>
        <span class="param-type"
          >{nestedParam.type}{#if nestedParam.alias}
            ({nestedParam.alias}){/if}</span
        >
        {#if requiredFields !== undefined || status.kind === 'typically'}
          <span class="badge status-badge status-{status.kind}"
            >{status.label}</span
          >
        {/if}
      </div>
      {#if nestedParam.description}
        <div class="param-desc nested">
          {nestedParam.description}
        </div>
      {/if}
      {#if status.hint}
        <div class="param-hint nested">{status.hint}</div>
      {/if}
      {#if nestedParam.enum && nestedParam.enum.length > 0}
        <div class="param-enums nested">
          {#each nestedParam.enum as val}
            <span
              class="enum-tag"
              class:default={status.kind === 'typically' &&
                nestedParam.default === val}>{val}</span
            >
          {/each}
        </div>
      {/if}
      {#if hasNestedProps(nestedParam)}
        {@render nestedProperties(
          nestedParam.properties ?? {},
          depth + 1,
          nestedParam.required,
          path
        )}
      {/if}
    {/each}
  </div>
{/snippet}

<div class="tool-card" class:expanded>
  <button
    class="card-header"
    onclick={(e: MouseEvent) => {
      if ((e.metaKey || e.ctrlKey) && onReveal) onReveal()
      else toggle()
    }}
  >
    <span class="chevron" class:rotated={expanded}>&#9002;</span>
    {#if func.srcLine}
      <span class="source-location">{func.srcLine}:</span>
    {/if}
    <span class="func-name">{func.name}</span>
    {#if func.isDefault}
      <span
        class="badge entry-badge"
        title="The rule l4 batch runs when you name none: the one marked @export default, or the first exported rule"
        >ENTRY POINT</span
      >
    {/if}
    {#if !expanded && paramCount > 0}
      <span class="param-count"
        >{paramCount} param{paramCount !== 1 ? 's' : ''}</span
      >
    {/if}
    {#if func.returnType}
      <span class="return-type">{func.returnType}</span>
    {/if}
  </button>

  {#if func.description}
    <div class="func-description">{func.description}</div>
  {/if}

  {#if expanded}
    <div class="card-body">
      {#if paramCount > 0}
        <div class="section-label">Inputs</div>
        <div class="params-list">
          {#each paramEntries(func.parameters) as [name, param]}
            {@const status = inputStatus(
              name,
              param,
              isRequired(name, func.parameters),
              unpublished.has(name)
            )}
            <div class="param-row">
              <span class="param-name">{name}</span>
              <span class="param-type"
                >{param.type}{#if param.alias}
                  ({param.alias}){/if}</span
              >
              <span class="badge status-badge status-{status.kind}"
                >{status.label}</span
              >
            </div>
            {#if param.description}
              <div class="param-desc">{param.description}</div>
            {/if}
            {#if status.hint}
              <div class="param-hint">{status.hint}</div>
            {/if}
            {#if param.enum && param.enum.length > 0}
              <div class="param-enums">
                {#each param.enum as val}
                  <span
                    class="enum-tag"
                    class:default={status.kind === 'typically' &&
                      param.default === val}>{val}</span
                  >
                {/each}
              </div>
            {/if}
            {#if hasNestedProps(param)}
              {@render nestedProperties(
                param.properties ?? {},
                1,
                param.required,
                name
              )}
            {/if}
          {/each}
        </div>
        {#if showsDefault}
          <div class="presumption-note">{PRESUMPTION_NOTE}</div>
        {/if}
        <details class="callers-see">
          <summary>What callers see</summary>
          <p class="callers-see-note">
            The schema of this rule's inputs, as the service describes them to
            callers, less the keys that are only for L4's own tools. MCP and
            WebMCP spell input names without spaces (for example start year
            becomes start-year).{#if func.isDeontic}
              A DEONTIC rule also takes <code>startTime</code> and
              <code>events</code>, which the service adds.{/if}
          </p>
          <pre class="callers-see-json">{publishedSchema}</pre>
        </details>
      {/if}

      {#if func.returnType}
        {#if paramCount > 0}
          <div class="returns-separator"></div>
        {/if}
        <div class="section-label">Returns</div>
        <div class="return-info">
          <span class="param-type">{func.returnType}</span>
        </div>
      {/if}
    </div>
  {/if}
</div>

<style>
  .tool-card {
    border: 1px solid var(--vscode-panel-border, #444);
    border-left: 3px solid var(--vscode-panel-border, #444);
    border-radius: 4px;
    overflow: hidden;
  }

  .card-header {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 5px 8px;
    background: var(--vscode-sideBarSectionHeader-background, #252526);
    border: none;
    color: var(--vscode-foreground);
    cursor: pointer;
    width: 100%;
    text-align: left;
    font-family: inherit;
    font-size: inherit;
  }

  .card-header:hover {
    background: var(--vscode-list-hoverBackground, #2a2d2e);
  }

  .chevron {
    display: inline-block;
    color: var(--vscode-descriptionForeground);
    transition: transform 0.15s;
    transform-origin: 25% 50%;
    font-size: 11px;
    flex-shrink: 0;
  }

  .chevron.rotated {
    transform: rotate(90deg);
  }

  .source-location {
    font-family: var(--vscode-editor-font-family, monospace);
    font-size: 0.85em;
    color: var(--vscode-descriptionForeground);
    opacity: 0.7;
    flex-shrink: 0;
  }

  .func-name {
    font-family: var(--vscode-editor-font-family, monospace);
    font-size: 0.95em;
    flex: 1 1 0;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .param-count {
    font-size: 0.82em;
    color: var(--vscode-descriptionForeground);
    opacity: 0.6;
    flex-shrink: 0;
    margin-left: auto;
  }

  .return-type {
    font-family: var(--vscode-editor-font-family, monospace);
    font-size: 0.88em;
    color: var(--l4-tok-identifier, #4ec9b0);
    flex: 0 3 auto;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .param-count + .return-type {
    margin-left: 6px;
  }

  .func-description {
    padding: 2px 8px 5px 25px;
    font-size: 0.88em;
    color: var(--vscode-descriptionForeground);
    background: var(--vscode-sideBarSectionHeader-background, #252526);
  }

  .card-body {
    padding: 6px 8px 8px 8px;
    background: var(--vscode-editor-background);
    border-top: 1px solid var(--vscode-panel-border, #444);
  }

  .section-label {
    font-size: 0.82em;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--vscode-descriptionForeground);
    margin: 6px 0 4px 0;
    opacity: 0.7;
  }

  .section-label:first-child {
    margin-top: 0;
  }

  .returns-separator {
    height: 1px;
    background: var(--vscode-panel-border, #444);
    margin: 6px 0 2px 0;
  }

  .params-list {
    display: flex;
    flex-direction: column;
  }

  .param-row {
    padding: 0 4px;
    line-height: 1.5;
    word-break: break-word;
  }

  .param-row.nested {
    padding-left: 4px;
  }

  .param-row > :not(:first-child) {
    margin-left: 6px;
  }

  .param-name {
    font-family: var(--vscode-editor-font-family, monospace);
    font-size: 0.92em;
    color: var(--vscode-foreground);
  }

  .param-type {
    font-family: var(--vscode-editor-font-family, monospace);
    font-size: 0.88em;
    color: var(--l4-tok-identifier, #4ec9b0);
  }

  .param-desc {
    font-size: 0.85em;
    color: var(--vscode-descriptionForeground);
    padding: 0 4px 2px 4px;
    opacity: 0.8;
  }

  .param-desc.nested {
    padding-left: 4px;
  }

  .param-enums {
    display: flex;
    flex-wrap: wrap;
    gap: 3px;
    padding: 2px 4px 2px 16px;
  }

  .param-enums.nested {
    padding-left: 16px;
  }

  .enum-tag {
    font-family: var(--vscode-editor-font-family, monospace);
    font-size: 0.78em;
    padding: 1px 3px;
    border-radius: 3px;
    background: transparent;
    color: var(--vscode-badge-background, #4d4d4d);
    border: 1px solid var(--vscode-badge-background, #4d4d4d);
  }

  .badge {
    font-size: 0.78em;
    padding: 1px 5px;
    border-radius: 3px;
    flex-shrink: 0;
  }

  .entry-badge {
    background: none;
    border: none;
    padding: 0;
    color: var(--vscode-descriptionForeground);
    opacity: 0.5;
  }

  /* What a caller must do about an input: "required", "optional", or
     "optional, typically 0" (the default a caller who leaves it out gets).
     A default is information a person acts on, so it is not dimmed. */
  .status-badge {
    background: none;
    border: none;
    padding: 0;
    color: var(--vscode-descriptionForeground);
  }

  .status-required,
  .status-optional {
    opacity: 0.6;
  }

  .status-typically,
  .status-unpublished {
    font-family: var(--vscode-editor-font-family, monospace);
  }

  .param-hint {
    font-size: 0.85em;
    color: var(--vscode-descriptionForeground);
    padding: 0 4px 2px 4px;
  }

  .param-hint.nested {
    padding-left: 4px;
  }

  .enum-tag.default {
    border-color: var(--vscode-descriptionForeground);
    color: var(--vscode-foreground);
  }

  .presumption-note {
    font-size: 0.85em;
    color: var(--vscode-descriptionForeground);
    margin: 6px 0 0;
  }

  .callers-see {
    margin: 6px 0 0;
  }

  .callers-see summary {
    cursor: pointer;
    font-size: 0.85em;
    color: var(--vscode-descriptionForeground);
  }

  .callers-see-note {
    font-size: 0.85em;
    color: var(--vscode-descriptionForeground);
    margin: 4px 0;
  }

  .callers-see-json {
    margin: 0;
    padding: 6px 8px;
    overflow-x: auto;
    font-family: var(--vscode-editor-font-family, monospace);
    font-size: 0.85em;
    background: var(
      --vscode-textCodeBlock-background,
      rgba(127, 127, 127, 0.1)
    );
    border-radius: 3px;
  }

  .return-info {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 2px 4px;
  }

  .nested-props {
    border-left: 1px solid var(--vscode-panel-border, #444);
    margin-left: 4px;
    padding-left: 8px;
  }
</style>
