# Deploy your rules

Publish L4 rules on [Legalese Cloud](https://legalese.cloud), where applications and AI agents can call them.

**Before you start:** [Install L4 and write your first rule](../getting-started/first-l4-file.md).

You will deploy an insurance premium calculator with two published rules, one that computes a premium and one that checks whether a discount applies, and then call one of them.

**Complete example:** [insurance-premium.l4](insurance-premium.l4)

---

## Step 1: Mark rules with `@export`

`@export` marks a rule for publication. Put it on the line directly above the rule's `GIVEN` (or above the rule itself, if it has no `GIVEN`). The rest of the line describes the rule:

```l4
DECLARE Applicant
    HAS `age`               IS A NUMBER
        `risk score`        IS A NUMBER
        `existing customer` IS A BOOLEAN

@export default Calculate the insurance premium for an applicant
GIVEN applicant IS AN Applicant @desc The applicant's details
GIVETH A NUMBER
DECIDE `calculate premium` IS
    IF applicant's `risk score` > 0.7
    THEN applicant's `age` * 100
    ELSE IF applicant's `existing customer`
         THEN applicant's `age` * 40
         ELSE applicant's `age` * 60

@export Check whether the applicant qualifies for a discount
GIVEN applicant IS AN Applicant @desc The applicant to check
GIVETH A BOOLEAN
DECIDE `qualifies for discount` IF
        applicant's `existing customer`
    AND applicant's `risk score` <= 0.5
```

| Annotation                      | Meaning                                                                                                             |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `@export <description>`         | Publish this rule, with this description.                                                                           |
| `@export default <description>` | Publish it as the **default** rule: `l4 batch` runs it when you name no rule. The service always needs a rule name. |
| `@desc <description>`           | After a `GIVEN` input: describe the input for people and agents calling it.                                         |

The descriptions become the rule's documentation in the API schema, and they are all an AI agent knows when it decides whether and how to call the rule, so write them with care. Rules without `@export` stay internal: other rules can use them, but they are not published.

An `@export` anywhere else, such as between `GIVETH` and `DECIDE`, is not picked up, and the rule is not published. See [annotations](../../reference/syntax/README.md#annotations) for the details.

---

## Step 2: Check what will be published

In VS Code, open the file, open the **L4** sidebar and select the **Deploy** tab. It lists every exported rule in the file, with its description, inputs and result type. If the list is empty, the file has no `@export` or does not type-check. The badge **ENTRY POINT** marks the rule `l4 batch` runs when you name none: the one marked `@export default`, or the first exported rule. The service has no such rule: a caller always names the rule. The badge does not mean the rule has a default value.

### Defaults

Some inputs have a **default**: a value the rule uses when a caller leaves that input out.
A caller is an application or an AI agent that runs your rule.
Below, "the service" is the decision service that runs your published rules, either on Legalese Cloud or on a `jl4-service` you run yourself.
L4 writes a default with [`TYPICALLY`](../../reference/types/TYPICALLY.md), so the Deploy tab says "typically".
This is not the `default` of `@export default` (the entry point), and not the `"report": "default"` in an answer: those are different things.
A default is not a suggestion: it is applied, and the answer says so.

Every answer from a published rule carries a list called **`presumed`**: the inputs the caller left out and the rule filled in for itself.
It lets whoever reads the answer see which facts were supplied and which were assumed.
It lists a default only when the answer relied on it.
The one exception is an event's party or action record in a request to the decision service for a rule that describes obligations: every field of it must be written, and a request that leaves one out is answered with an error (see [An event's party and action record](../../reference/types/TYPICALLY.md#an-events-party-and-action-record)).

Each input on a rule's card reads one of these:

- `required`: a caller must supply it.
- `optional`: a caller may leave it out. This is an input that may have no value (a `MAYBE`), and left out it is `NOTHING`.
- `optional, typically 0`: a caller may leave it out. The rule then uses 0, and the answer lists the input under `presumed` when it relied on it.

The card says it in words under the input: "If left out, 0 is used, and the answer lists b under presumed when it relies on that."
A field of a record is named by its path, such as `cfg.retries`.
For an input that is a choice from a list, the card marks the default choice.
`typically nothing` means the default is "nothing", and `typically false` means the default answer is no.

When some input has a default, the card adds a line: "Callers can turn the defaults off with presumption: hard (HTTP, batch, MCP, WebMCP)."
The switch is a setting named `presumption` that a caller sends with a request.
With it set to `hard`, a caller who leaves an input out gets an error naming it, instead of the default.
It works over **HTTP** (the ordinary web request a program sends to the address in [Step 5](#step-5-call-a-rule)) and in `l4 batch` (the command that runs a rule over many cases).
It works through **MCP** (the Model Context Protocol, which lets an AI agent use a rule as a tool; see [Connect an AI agent](../legalese-cloud/ai-agents.md)) and **WebMCP** (the same for the AI assistant in a visitor's browser; see [Embed rules in a website](../legalese-cloud/webmcp-embed.md)) too: this service's MCP tools advertise `presumption` and read it; a hosted server placed in front of this service may not list it until that server is updated, so look at the tool list.
[Connect an AI agent](../legalese-cloud/ai-agents.md#telling-a-rule-not-to-assume-anything) says what a server that does not know the argument does.

Under the inputs, **What callers see** is collapsed.
Open it to read the schema of the rule's inputs as the service describes them to callers, with each default written as `"default": 0` and the inputs a caller must supply listed under `"required"`.
The service publishes that schema in its **OpenAPI** document (OpenAPI is the standard format for describing a web interface; see [Call rules over REST](../legalese-cloud/openapi-spec.md)) and in its MCP tool list.
Without VS Code, read it from the OpenAPI document (`.../openapi.json`), from the MCP tool list, or from the function's own document, which the service returns for one rule at `GET .../functions/{fn}` with the rule's description, its inputs and its result.
The typed schema of an event, for a rule that describes obligations, is published in the function document and in `openapi.json` under each batch case's `events`.
The card shows the same schema that callers get, and does not write one of its own.
MCP and WebMCP spell input names without spaces: `start year` becomes `start-year`.
One thing differs: the OpenAPI document leaves out an input whose name is one of four reserved names (`alias`, `propertyOrder`, `x-l4-type` and `x-sanitized-name`) while still listing it as required, which is a defect in the service: for an input with one of those names, do not rely on the OpenAPI document.
The card shows such an input, as the MCP tool list does.
The document leaves the input out because of its name, so renaming the input in the rule to a name that is not one of the four, and redeploying, makes the document list it.
A rename is a breaking change for callers that send the old name ([Manage rules in git and CI](../getting-started/version-control-for-rules.md#redeploy-when-a-merge-changes-a-live-api)).

The Deploy tab shows what the service publishes, and it has limits:

- A default on an `ASSUME` (older files) is not published, and the service does not use it.
  The Deploy tab says `typically (not published)` for that input, and callers must still supply it.
  The Deployments tab cannot say this, because the service publishes no marker, so such an input reads `required` there.
- Neither tab lists the fields inside the elements of a list.
  A default on such a field is published, but it is not shown, and each tab says so.
- A deployment made by an older service publishes no defaults, so none are shown.

An input with no `typically` beside it can therefore still carry a default in the file.

---

## Step 3: Deploy

1. In the sidebar, sign in to your [Legalese Cloud](https://legalese.cloud) account.
2. Check the list of exported rules.
3. Click **Deploy**.
4. Enter a **deployment name**, such as `insurance-premium`. It becomes part of the API address: 1 to 36 characters, using letters, digits, hyphens and underscores.
5. Click **Deploy Now**.

The extension uploads the file and the service compiles it, and its status goes through **Pending** (uploaded), **Compiling**, then **Ready** (live) or **Failed** (with the compiler's error message).

### Update a deployment

Deploying to a name that already exists updates that deployment. The extension first checks for **breaking changes**, such as a removed rule, a removed or renamed input, or a changed result type, and warns you before you confirm. [Manage rules in git and CI](../getting-started/version-control-for-rules.md#redeploy-when-a-merge-changes-a-live-api) explains which changes break callers.

#### When a default changes

A caller who leaves an input out gets its default, so changing the default changes the answer such a caller gets, without any message to them.
That is why the extension tells you.
Before it sends the update, it shows a **Defaults change** screen with one line for each change, such as "the smaller of · b · typically 0 → 1: callers who leave b out will get different answers."
A field of a record is named by its path, such as `cfg.retries`.

A changed default is reported, not refused.
It does not count as a breaking change, the screen is not a warning, and **Deploy Now** goes ahead.
If the update also contains a breaking change, the usual warning appears, with the changed defaults listed under it.

After the update, the sidebar says what happened to the defaults:

- When it has been applied, the **Deployments** tab lists the changes, as the service reported them, until you dismiss the list or open the **Deploy** form again, which clears it.
- When the service rejects it, the **Deploy** tab says that nothing changed and lists the defaults the update would have changed.
- When the sidebar cannot read the result of the deploy (the connection to the service fails three times running), it says that the result could not be read and that the deploy may have been applied.
  It lists the defaults the review showed, marked as reported before the deploy.
  It never says the update was rejected, because the service did not say so.
  The **Deployments** list is left as it was, not fetched again, because a failed fetch would show it empty.
- The sidebar gives a failed read three tries, but it puts no limit on how long one read may take: if the service neither answers nor fails, the progress bar and the disabled button stay and no message appears.
- The list comes from the service, so it needs a service that reports changed defaults, which the service that ships with this change does.
  A service that does not report them leaves the sidebar to show the list it held before the deploy, and it says "Reported before the deploy; the service did not report them."

What the check compares:

- It compares an input's default only when both the deployed version and the new one publish one.
- It does not compare an input whose type changed, or the fields under it: the type change is a breaking change and is warned about as one.
- Adding a default to an input that was required makes it optional, which callers cannot notice, so it is not reported.
- Removing a default from an input that is required without it makes it required again, which is a breaking change and is warned about as one.
- An input that may have no value (a `MAYBE`) is optional with or without a default, so adding or removing one there changes nothing about what callers must supply.
- A deployment made by an older service publishes no defaults, so there is nothing to compare.
- An update whose content is exactly the live version's reaches the service as an unchanged upload, which has no changed defaults, so the service lists none.

### From the command line

The `l4` command deploys the same way. Sign in once with the `legalese` command (`l4 install legalese`, then `legalese login`), then run `l4 deploy insurance-premium.l4` to create the deployment and `l4 redeploy insurance-premium.l4` to update it; `redeploy` refuses breaking changes unless you add `--force`. `l4 deployments` lists your deployments and `l4 undeploy NAME` removes one. With `--server`, the same commands deploy to a jl4-service you run yourself. See [Using the l4 CLI](../getting-started/l4-cli.md).

A changed default is not a breaking change. If an update changes the default of an input, the value a rule uses when a caller leaves that input out, the service applies the update and reports each such change (the rule, the input, the old value and the new one) in the result of the deploy, and `l4 deploy` and `l4 redeploy` print it. The report sees only a default that is a plain value on both versions; a rate written in the body of a rule is not a default, and a change to one is not reported. An input whose type changed is reported as a breaking change and its defaults are not compared, so a rejection for a retyped input lists no changed default for it.

---

## Step 4: Manage deployments

The **Deployments** tab in the sidebar lists your organization's deployments, with each one's rules, descriptions and inputs, and the default of each input that has one (the same limits as in [Defaults](#defaults) apply). From there you can open a deployment's **Integrate** dialog, which shows its addresses for each kind of client, or **Undeploy** it. Undeploying asks for confirmation, because it breaks every integration that uses the deployment.

---

## Step 5: Call a rule

Once the deployment is **Ready**, each exported rule can be called over REST. Create an API key in the [Legalese Cloud console](https://legalese.cloud), then:

```bash
curl -X POST https://api.legalese.cloud/{orgSlug}/insurance-premium/functions/calculate-premium/evaluation \
  -H "Authorization: Bearer sk_..." \
  -H "Content-Type: application/json" \
  -d '{
    "arguments": {
      "applicant": {
        "age": 35,
        "risk-score": 0.4,
        "existing-customer": true
      }
    }
  }'
```

`{orgSlug}` is your organization on Legalese Cloud. In the address and the arguments, spaces in names become hyphens: the rule `` `calculate premium` `` is `calculate-premium`, and the field `` `risk score` `` is `"risk-score"`. The answer:

```json
{
  "contents": { "presumed": [], "result": { "value": 1400 } },
  "report": "default",
  "tag": "SimpleResponse"
}
```

The same deployment also works with AI agents, chat clients and websites. To pick a way in, see [Choose an integration](../legalese-cloud/README.md); for the REST interface in detail, including the answer format, see [Call rules over REST](../legalese-cloud/openapi-spec.md).

---

## Common mistakes

**Forgetting `@export`.** Without it, a rule is not published, however useful it is.

**Putting `@export` in the wrong place.** It goes directly above `GIVEN`, not between `GIVETH` and the rule:

```l4
@export Square a number
GIVEN x IS A NUMBER @desc The number to square
GIVETH A NUMBER
squared x MEANS x * x
```

**Leaving inputs undescribed.** Without `@desc`, callers and AI agents have only the input's name to go on.

---

## Next steps

- [Choose an integration](../legalese-cloud/README.md): AI agents, chat, REST or a website.
- [Manage rules in git and CI](../getting-started/version-control-for-rules.md): test and redeploy safely.
- [Annotations](../../reference/syntax/README.md#annotations): `@export`, `@desc` and the others.
