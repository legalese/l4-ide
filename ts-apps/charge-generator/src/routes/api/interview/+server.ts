import type { RequestHandler } from './$types'
import Anthropic from '@anthropic-ai/sdk'
import { OFFENCES } from '$lib/catalogue'
import { interviewTools, type CaseResult } from '$lib/server/tools'
import { EMPTY_GRAPH } from '$lib/evidence/types'

/**
 * The live interview. Holds the Anthropic credential server-side (never in
 * the browser) and runs the tool loop over jl4-service.
 *
 * Wire: the browser POSTs the officer's message, the prior turns (text only),
 * any uploads (PDF / image as base64, text as text) and the current case
 * result; the response is NDJSON, one event per line:
 *   {t:"text", delta}     assistant prose
 *   {t:"thinking", delta} the summarised reasoning (display: summarized)
 *   {t:"tool", name, args, result}
 *   {t:"case", charges, evidence, withdrawn}   what this turn established
 *   {t:"done", stop}      / {t:"error", message}
 *
 * Model: claude-opus-5, adaptive thinking, streaming, tool runner with
 * eager input streaming on every client tool; server-side refusal fallbacks
 * are opted in ("default" mode).
 */
const MODEL = 'claude-opus-5'

interface Body {
  text: string
  history?: { role: 'user' | 'assistant'; text: string }[]
  uploads?: { name: string; type: string; data?: string; text?: string }[]
  pins?: string[]
  result?: CaseResult
}

const SYSTEM = `You are the case assistant for a Singapore police investigating officer preparing charges under the Penal Code 1871.

The law is NOT yours to decide. Every offence available is encoded and deployed to a rules service; the tools are the only way to learn which elements an offence has (facts_schema), whether the facts make it out (evaluate), and how the charge reads (propose_charge). Never assert that an offence is or is not made out without an evaluate result, never write a charge sentence yourself, and never cite a section that list_offences did not return.

How to work:
1. Call list_offences once, then facts_schema for each section that plausibly fits the account.
2. Fill the facts record from what the officer said and uploaded. Set a boolean element TRUE only when the account or a document supports it; leave it out when unknown. Fill the string particulars in the wording the charge will recite (the schema's descriptions say how), using the officer's names, dates and places verbatim.
3. Call evaluate. Where elements are not yet known, ask the officer — one short round of specific questions, grouped. Where the refusal names missing elements, say so plainly.
4. propose_charge for each section that is made out (the aggravated and the simple form may both be; say which you recommend and why, briefly). If the officer pinned a section, work only on it.
5. attach_fact for each element of a proposed charge, naming the source (statement under CPC s 22, cautioned statement under s 23, conditioned statement under s 264, exhibit, document/CCTV, forensic report, First Information Report, or an upload) and quoting it where you can. An element you cannot source is a gap: say what evidence would fill it.
6. Reply in plain English for the officer: what fits, what is missing, what to confirm. Keep it under 250 words unless asked for more. Do not restate the charge text — it is on the officer's screen.`

export const POST: RequestHandler = async ({ request }) => {
  const body = (await request.json()) as Body
  const enc = new TextEncoder()
  const client = new Anthropic()

  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      const emit = (e: unknown) =>
        controller.enqueue(enc.encode(JSON.stringify(e) + '\n'))
      try {
        const initial: CaseResult = body.result ?? {
          charges: [],
          evidence: EMPTY_GRAPH,
          withdrawn: [],
        }
        const { tools, result } = interviewTools(initial, (e) =>
          emit({ t: 'tool', ...e })
        )

        const history: Anthropic.Beta.BetaMessageParam[] = (body.history ?? [])
          .filter((h) => h.text.trim())
          .map((h) => ({ role: h.role, content: h.text }))

        const content: Anthropic.Beta.BetaContentBlockParam[] = []
        for (const u of body.uploads ?? []) {
          if (u.data && u.type === 'application/pdf')
            content.push({
              type: 'document',
              source: {
                type: 'base64',
                media_type: 'application/pdf',
                data: u.data,
              },
              title: u.name,
            })
          else if (u.data && /^image\/(png|jpeg|gif|webp)$/.test(u.type))
            content.push({
              type: 'image',
              source: {
                type: 'base64',
                media_type: u.type as
                  | 'image/png'
                  | 'image/jpeg'
                  | 'image/gif'
                  | 'image/webp',
                data: u.data,
              },
            })
          else if (u.text)
            content.push({
              type: 'text',
              text: `--- uploaded file ${u.name} ---\n${u.text}`,
            })
        }
        const pins = body.pins?.length
          ? `\n\n(The officer has pinned section${body.pins.length > 1 ? 's' : ''} ${body.pins.join(', ')}: work only on ${body.pins.length > 1 ? 'those' : 'that'}.)`
          : ''
        const known = initial.charges.length
          ? `\n\n(Charges already on the carousel: ${initial.charges.map((c) => 's ' + c.section).join(', ')}. Their facts records are the ones you proposed earlier; re-propose to change them.)`
          : ''
        content.push({ type: 'text', text: body.text + pins + known })

        const runner = client.beta.messages.toolRunner({
          model: MODEL,
          max_tokens: 64000,
          system:
            SYSTEM +
            `\n\nSections encoded: ${OFFENCES.map((o) => `s ${o.section} (${o.title})`).join('; ')}.`,
          thinking: { type: 'adaptive', display: 'summarized' },
          betas: ['server-side-fallback-2026-07-01'],
          fallbacks: 'default',
          tools,
          messages: [...history, { role: 'user', content }],
          max_iterations: 24,
          stream: true,
        })

        let stop: string | null = null
        for await (const messageStream of runner) {
          for await (const event of messageStream) {
            if (event.type !== 'content_block_delta') continue
            if (event.delta.type === 'text_delta')
              emit({ t: 'text', delta: event.delta.text })
            else if (event.delta.type === 'thinking_delta')
              emit({ t: 'thinking', delta: event.delta.thinking })
          }
          const message = await messageStream.finalMessage()
          stop = message.stop_reason
          const hasToolUse = message.content.some((b) => b.type === 'tool_use')
          if (message.stop_reason === 'max_tokens' && hasToolUse) {
            emit({
              t: 'error',
              message:
                'The assistant ran out of room mid-tool-call; please send again.',
            })
            break
          }
          if (message.stop_reason === 'refusal') {
            emit({
              t: 'error',
              message: 'The assistant declined to continue this request.',
            })
            break
          }
        }
        emit({ t: 'case', ...result })
        emit({ t: 'done', stop })
      } catch (e) {
        const message =
          e instanceof Anthropic.AuthenticationError
            ? 'No Anthropic credential is configured on the server (set ANTHROPIC_API_KEY).'
            : e instanceof Anthropic.RateLimitError
              ? 'The model is rate-limited right now; try again in a moment.'
              : e instanceof Anthropic.APIError
                ? `The model API answered ${e.status ?? ''}: ${e.message}`
                : e instanceof Error
                  ? e.message
                  : String(e)
        emit({ t: 'error', message })
      } finally {
        controller.close()
      }
    },
  })

  return new Response(stream, {
    headers: {
      'Content-Type': 'application/x-ndjson',
      'Cache-Control': 'no-store',
    },
  })
}
