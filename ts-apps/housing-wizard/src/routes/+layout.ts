// Standalone SPA: no server-side rendering, all logic runs in the browser.
// The root (/) is prerendered to index.html as the app shell. There is no
// module-scope fetch anywhere, so prerendering only emits the shell — the
// schema fetch to the jl4-service runs in the browser, on mount.
export const ssr = false
export const prerender = true
