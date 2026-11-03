export const ssr = false
// Prerendering the (empty) shell puts modulepreload links for the editor's
// code into index.html, so the browser fetches it all at once instead of
// discovering it import by import.
export const prerender = true
