import type { RequestHandler } from './$types'
import { json } from '@sveltejs/kit'

/**
 * The live interview route (PR 3). It will hold the Anthropic key server-side
 * and run the tool loop over jl4-service. Until it lands, the browser's
 * interview pane serves preloads locally and this route answers 501 so the UI
 * can say honestly that the live path is not wired yet.
 */
export const POST: RequestHandler = async () => {
  return json(
    {
      error:
        'The live interview is not wired in this build. Load a sample conversation, or set ANTHROPIC_API_KEY and deploy the interview route (PR 3).',
    },
    { status: 501 }
  )
}
