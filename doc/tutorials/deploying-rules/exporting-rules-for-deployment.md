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

| Annotation                      | Meaning                                                                     |
| ------------------------------- | --------------------------------------------------------------------------- |
| `@export <description>`         | Publish this rule, with this description.                                   |
| `@export default <description>` | Publish it as the **default** rule, used when a caller names no rule.       |
| `@desc <description>`           | After a `GIVEN` input: describe the input for people and agents calling it. |

The descriptions become the rule's documentation in the API schema, and they are all an AI agent knows when it decides whether and how to call the rule, so write them with care. Rules without `@export` stay internal: other rules can use them, but they are not published.

An `@export` anywhere else, such as between `GIVETH` and `DECIDE`, is not picked up, and the rule is not published. See [annotations](../../reference/syntax/README.md#annotations) for the details.

---

## Step 2: Check what will be published

In VS Code, open the file, open the **L4** sidebar and select the **Deploy** tab. It lists every exported rule in the file, with its description, inputs and result type. If the list is empty, the file has no `@export` or does not type-check. The badge **ENTRY POINT** marks the rule `l4 batch` runs when you name none: the one marked `@export default`, or the first exported rule. The service has no such rule: a caller always names the rule. The badge does not mean the rule has a default value.

### Usual values

Some inputs have a **usual value**: what the rule uses when a caller leaves that input out.
L4 calls it a default and writes it with [`TYPICALLY`](../../reference/types/TYPICALLY.md).
The Deploy tab shows it beside the input, as `optional` and `usually 3`, so you can see what a caller who says nothing will get.
It does the same for the fields of a record, and for an input that is a choice from a list it marks the usual choice.
`usually empty` means the usual value is "nothing", and `usually false` means the usual answer is no.

The Deploy tab shows what the service publishes, and it has two limits:

- A usual value on an `ASSUME` (older files) is not published, and the service does not use it, so the tab shows nothing for it.
- The tab lists the fields of a record under the input, but not the fields inside the elements of a list, so a usual value on such a field is not shown there, although the service publishes it.

An input with no `usually` beside it can therefore still carry a usual value in the file.

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

#### When a usual value changes

A caller who leaves an input out gets its usual value, so changing that value changes the answer such a caller gets, without any message to them.
That is why the extension tells you.
Before it sends the update, it shows a **Usual values change** screen listing each change: the rule, the input, the old value and the new one.
A field of a record is named by its path, such as `cfg.retries`.

A changed usual value is reported, not refused.
It does not count as a breaking change, the screen is not a warning, and **Deploy Now** goes ahead.
When the update has been applied, the **Deployments** tab lists the same changes, as the service reported them, until you dismiss the list.
If the update also contains a breaking change, the usual warning appears, with the changed usual values listed under it.

What the check compares:

- It compares an input's usual value only when both the deployed version and the new one publish one.
- Adding a usual value to an input is not a change: the input just becomes optional, which callers cannot notice.
- Removing a usual value makes the input required again, which is a breaking change and is warned about as one.
- A deployment made by an older service publishes no usual values, so there is nothing to compare.
- An update with exactly the same content as the live version is not sent to the service as an update, so nothing is listed after it.

### From the command line

The `l4` command deploys the same way. Sign in once with the `legalese` command (`l4 install legalese`, then `legalese login`), then run `l4 deploy insurance-premium.l4` to create the deployment and `l4 redeploy insurance-premium.l4` to update it; `redeploy` refuses breaking changes unless you add `--force`. `l4 deployments` lists your deployments and `l4 undeploy NAME` removes one. With `--server`, the same commands deploy to a jl4-service you run yourself. See [Using the l4 CLI](../getting-started/l4-cli.md).

---

## Step 4: Manage deployments

The **Deployments** tab in the sidebar lists your organization's deployments, with each one's rules, descriptions and inputs, and the usual value of each input that has one (the same limits as in [Usual values](#usual-values) apply). From there you can open a deployment's **Integrate** dialog, which shows its addresses for each kind of client, or **Undeploy** it. Undeploying asks for confirmation, because it breaks every integration that uses the deployment.

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
