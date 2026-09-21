// The page is a browser app over jl4-service (the ladder controller touches
// `document` in its constructor, so no SSR); the server half of this app is only
// the interview route under /api. No prerender: adapter-node serves the shell.
export const ssr = false
export const prerender = false
