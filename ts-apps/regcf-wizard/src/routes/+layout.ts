// Standalone SPA: no server-side rendering, all logic runs in the browser.
// The root (/) is prerendered to index.html as the app shell. There is no
// module-scope fetch anywhere, so prerendering only emits the shell — the schema
// fetch, the query-plan and the ladder GET all run in the browser, on mount.
//
// `ssr = false` is also what keeps the ladder controller safe to construct: it
// touches `document` and `ResizeObserver` in its constructor.
export const ssr = false
export const prerender = true
