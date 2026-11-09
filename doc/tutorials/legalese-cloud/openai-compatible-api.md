# Chat with your rules through the OpenAI or Anthropic API

Ask a deployment questions in plain language from any OpenAI or Anthropic client. Legalese Cloud serves each deployment in both formats, backed by the same `legalese-comply-4` model pipeline: the model decides which exported rules to run, gathers their inputs and explains the result. It is the same service the **Use in chat** button in the VS Code Deployments tab connects to.

**Before you start:** a deployment on Legalese Cloud ([Deploy your rules](../deploying-rules/exporting-rules-for-deployment.md)). To compare this with the other integrations, see [Choose an integration](README.md).

---

## Endpoint

```
https://ai.legalese.cloud/{orgSlug}/{deploymentId}/v1
```

`{orgSlug}` is your Legalese Cloud organization; `{deploymentId}` is the deployment's name. The VS Code **Integrate** dialog pre-fills both for you. Append the path that matches your client's wire format:

| Client wire format | Append              |
| ------------------ | ------------------- |
| OpenAI             | `/chat/completions` |
| Anthropic Messages | `/messages`         |

Both paths lead to the same pipeline, with the same authentication and daily token quota; only the shape of requests and responses differs. Use whichever SDK your stack already has.

## Authentication

Send your credential, a Legalese Cloud session or an `sk_...` API key, in either header:

- `Authorization: Bearer {token}`: the OpenAI SDK's default, and what the VS Code extension sends with your session;
- `x-api-key: {token}`: the Anthropic SDK's default.

An API key needs the `ai:chat`, `l4:rules` and `l4:evaluate` permissions. With `ai:chat` but not `l4:evaluate`, the model can hold a conversation but cannot run any rule, and says it cannot compute the answer. See [API keys and permissions](README.md#api-keys-and-permissions).

## Use it

### OpenAI clients

#### curl

```bash
curl https://ai.legalese.cloud/{orgSlug}/{deploymentId}/v1/chat/completions \
  -H "Authorization: Bearer sk_..." \
  -H "Content-Type: application/json" \
  -d '{
    "model": "legalese-comply-4",
    "messages": [
      { "role": "user", "content": "Is a tenant who is 40 days late on rent in breach?" }
    ]
  }'
```

#### OpenAI SDK (Python)

```python
from openai import OpenAI

client = OpenAI(
    base_url="https://ai.legalese.cloud/{orgSlug}/{deploymentId}/v1",
    api_key="sk_...",
)

resp = client.chat.completions.create(
    model="legalese-comply-4",
    messages=[{"role": "user", "content": "Is a tenant 40 days late in breach?"}],
)
print(resp.choices[0].message.content)
```

#### OpenAI SDK (TypeScript)

```ts
import OpenAI from "openai";

const client = new OpenAI({
  baseURL: "https://ai.legalese.cloud/{orgSlug}/{deploymentId}/v1",
  apiKey: "sk_...",
});

const resp = await client.chat.completions.create({
  model: "legalese-comply-4",
  messages: [{ role: "user", content: "Is a tenant 40 days late in breach?" }],
});
console.log(resp.choices[0].message.content);
```

Streaming (`stream: true`) and multi-turn conversations work exactly as they do against `api.openai.com`.

### Anthropic clients

#### curl

```bash
curl https://ai.legalese.cloud/{orgSlug}/{deploymentId}/v1/messages \
  -H "x-api-key: sk_..." \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "legalese-comply-4",
    "max_tokens": 1024,
    "messages": [
      { "role": "user", "content": "Is a tenant who is 40 days late on rent in breach?" }
    ]
  }'
```

#### Anthropic SDK (Python)

```python
import anthropic

# Anthropic's SDK appends "/v1/messages" itself, so base_url stops at the deployment root.
client = anthropic.Anthropic(
    base_url="https://ai.legalese.cloud/{orgSlug}/{deploymentId}",
    api_key="sk_...",
)

resp = client.messages.create(
    model="legalese-comply-4",
    max_tokens=1024,
    messages=[{"role": "user", "content": "Is a tenant 40 days late in breach?"}],
)
print(resp.content[0].text)
```

#### Anthropic SDK (TypeScript)

```ts
import Anthropic from "@anthropic-ai/sdk";

// baseURL stops at the deployment root; the SDK appends "/v1/messages".
const client = new Anthropic({
  baseURL: "https://ai.legalese.cloud/{orgSlug}/{deploymentId}",
  apiKey: "sk_...",
});

const resp = await client.messages.create({
  model: "legalese-comply-4",
  max_tokens: 1024,
  messages: [{ role: "user", content: "Is a tenant 40 days late in breach?" }],
});
console.log(resp.content[0].type === "text" ? resp.content[0].text : "");
```

Streaming (`stream: true`), extended thinking, and multi-turn conversations work exactly as they do against `api.anthropic.com`. The model's reasoning arrives as ordinary `thinking` content blocks.

## Notes

- The endpoint knows only the rules exported in that deployment. It has no access to your editor, your workspace or your other deployments.
- The model name is always `legalese-comply-4`. Both formats reject other model names, such as `claude-opus-4-7`, with `400 model_not_found`.
- A self-hosted jl4-service does not offer this API; use [MCP](ai-agents.md) or [REST](openapi-spec.md) there.
