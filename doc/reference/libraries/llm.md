# llm

Calls large language models from L4: Anthropic's Claude, OpenAI, or any model on OpenRouter. Import it with `IMPORT llm`.

Each call sends one user message and gives back the provider's reply exactly as it arrives: the response body, a JSON text in a STRING. Take the answer out of it with `JSONDECODE` (see [Reading the reply](#reading-the-reply)).

**Example:** [llm-example.l4](llm-example.l4)

## Configuration

- **API keys.** The `call...` functions take the key as their first input; read it with the built-in `ENV` so it stays out of your file. `queryLLM` and `queryLLMWithDefaults` read the environment variables `OPENROUTER_API_KEY`, `OPENAI_API_KEY` and `ANTHROPIC_API_KEY` themselves.
- **Network.** The calls use the built-in `POST`, so every evaluation makes a real HTTPS request and needs network access. Where L4 runs in safe mode, as it does in the browser, the request is refused with an error. See [HTTP and JSON](../builtins/http-json.md).

## Functions

| Function               | Inputs                                                   | Gives           | What it does                                                                              |
| ---------------------- | -------------------------------------------------------- | --------------- | ----------------------------------------------------------------------------------------- |
| `callAnthropic`        | `apiKey`, `model`, `prompt`: STRING, `maxTokens`: NUMBER | STRING          | Calls Anthropic's Messages API                                                            |
| `callOpenAI`           | `apiKey`, `model`, `prompt`: STRING, `maxTokens`: NUMBER | STRING          | Calls OpenAI's Chat Completions API                                                       |
| `callOpenRouter`       | `apiKey`, `model`, `prompt`: STRING, `maxTokens`: NUMBER | STRING          | Calls OpenRouter's chat completions API                                                   |
| `callClaude`           | `apiKey`, `prompt`: STRING                               | STRING          | `callAnthropic` with the model `claude-sonnet-4-5-20250929` and 1000 tokens               |
| `callGPT4`             | `apiKey`, `prompt`: STRING                               | STRING          | `callOpenAI` with the model `gpt-4` and 1000 tokens                                       |
| `queryLLM`             | `model`, `prompt`: STRING, `maxTokens`: NUMBER           | STRING          | Calls the first provider whose key is set, trying OpenRouter, then OpenAI, then Anthropic |
| `queryLLMWithDefaults` | `prompt`: STRING                                         | STRING          | The same order, with each provider's default model and 1000 tokens                        |
| `parseResponse`        | `jsonString`: STRING                                     | EITHER STRING a | `JSONDECODE` of the text                                                                  |
| `createMessage`        | `role`, `content`: STRING                                | `Message`       | A `Message` record, as sent in the request                                                |

`queryLLM` passes the same model name to whichever provider it calls, and the providers name models differently (OpenRouter writes `anthropic/claude-3.5-sonnet`), so give it a name the provider you expect will accept.

When no key is set, `queryLLM` and `queryLLMWithDefaults` do not fail: they give a STRING that begins `ERROR: No LLM API keys configured`.

The defaults of `queryLLMWithDefaults` are `anthropic/claude-3.5-sonnet` on OpenRouter, `gpt-4` on OpenAI and `claude-sonnet-4-5-20250929` on Anthropic.

## Model names

These constants name models the way OpenRouter does, for `callOpenRouter`. They name older models; you can pass any current model name as a STRING instead.

| Constant            | Value                                      |
| ------------------- | ------------------------------------------ |
| `claudeOpusModel`   | `"anthropic/claude-3-opus"`                |
| `claudeSonnetModel` | `"anthropic/claude-3.5-sonnet"`            |
| `gpt4Model`         | `"openai/gpt-4"`                           |
| `gpt4TurboModel`    | `"openai/gpt-4-turbo"`                     |
| `gpt35Model`        | `"openai/gpt-3.5-turbo"`                   |
| `llama3Model`       | `"meta-llama/llama-3.1-70b-instruct"`      |
| `llama3FreeModel`   | `"meta-llama/llama-3.1-70b-instruct:free"` |
| `geminiProModel`    | `"google/gemini-pro"`                      |

## Reading the reply

The reply is the provider's JSON. Declare records for the fields you need and decode into them with `JSONDECODE`; fields you do not declare are ignored.

- Anthropic puts the text in `content`, a list of blocks that each have a `text` field: `{"content": [{"type": "text", "text": "..."}]}`.
- OpenAI and OpenRouter put it in `choices`, a list whose items have a `message` with a `content` field: `{"choices": [{"message": {"content": "..."}}]}`.

The example file decodes an Anthropic reply in `` `the text of` ``.

## Keeping judgment and rules apart

A model is good at questions of judgment, such as whether a notice is written in a professional tone. L4 is good at applying rules to the answers. Keep the two apart:

- Write the rule with the model's answer as an input (`GIVEN`), not as a call inside it. The rule can then be tested with `#EVAL` by passing answers directly, and it reads the same whoever, or whatever, supplies the answer.
- Ask for an answer in a fixed form, such as `YES` or `NO`, so the rule can compare it.
- A model can give different answers to the same prompt. If decisions must be audited, keep the prompt, the model name, the reply and the time of the call alongside the decision.
