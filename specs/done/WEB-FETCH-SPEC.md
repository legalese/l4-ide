# Web Fetch for Legalese AI

**Status:** Done (sidebar here; cloud sessions in ai-proxy).

Legalese AI could search the web (the AI service turns on the model's own web search for every compose request) but couldn't read a page by URL. When a pasted URL seemed to work, the search had found that page. Now the agent can read a page the user links, or one from search results, in both places it runs: the VS Code sidebar and cloud sessions. Each gets its own fetcher.

## Sidebar: `web__fetch` through VS Code

`WebFetchTools` (`ts-apps/vscode/src/ai/web-fetch-tool.ts`) is a `ToolProvider` with prefix `web__` and one tool:

```json
{ "name": "web__fetch", "parameters": { "url": "https://…" } }
```

It forwards the call to VS Code's own "Fetch Web Page" tool, `vscode_fetchWebPage_internal`, with `vscode.lm.invokeTool` and no invocation token (`vscode-lm.ts`). VS Code loads the page in a hidden browser window, so pages that need JavaScript work, and its proxy settings apply. Outside a chat session it asks in a modal dialog before a domain the user hasn't trusted, and fetches trusted ones without asking.

- **Advertised only while VS Code has the tool.** The name is internal and can change; without it, `web__fetch` is not listed and the agent still has web search.
- **http and https only.** VS Code's tool reads local files for any other scheme, which would get around the workspace's file checks, so anything else is refused before VS Code sees it.
- **One URL per call,** so each result belongs to one page and each untrusted domain gets its own dialog.
- **Errors are errors.** VS Code reports a failed fetch or a redirect as text; those become tool errors, the redirect naming `web__fetch` (VS Code's message names its own tool). A declined dialog says the user declined. Pages over 100,000 characters are cut, with a note.
- **Permission `web.fetch`,** setting `legaleseAi.permissions.fetchWebPages`, default `always`: VS Code already asks before untrusted domains, and asking here too would ask twice. `never` and `ask` work as for the other categories.
- **Only the sidebar registers it.** It is not in the shared built-in tools, so the cloud agent never gets it. `@legalese` in Copilot Chat already gets VS Code's tool directly from `vscode.lm.tools`.

The tool-call row shows "Fetching…" / "Fetched" and the URL, and the turn's Sources card lists the pages fetched next to search citations.

## Cloud sessions: OpenRouter's web fetch (ai-proxy)

A cloud session's compose requests carry OpenRouter's server tool:

```json
{
  "type": "openrouter:web_fetch",
  "parameters": {
    "engine": "native",
    "max_uses": 5,
    "max_content_tokens": 20000
  }
}
```

`native` uses the model's own fetch (Anthropic's on Claude, which fetches only URLs already in the conversation) and falls back to OpenRouter's fetcher. OpenRouter runs it inside the request, so the session's task never makes the request and the harness needs no change. Only the agent key's name (`cloud-session:<sid>:…`) turns it on, never the `X-Legalese-Session` header, so the sidebar never has two fetch tools.

OpenRouter doesn't say how a server tool shows up in a Chat Completions stream. If a call ever comes back to the proxy, its unknown-tool path logs it and answers with an error result. Pages it cites arrive as citations, which already reach the Sources card.

## Not covered

- The webchat has neither tool.
- Which pages a cloud session fetched is not shown, unless they're cited.
