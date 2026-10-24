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
    HAS `age`                  IS A NUMBER
        `risk score`           IS A NUMBER
        `is existing customer` IS A BOOLEAN

@export default Calculate the insurance premium for an applicant
GIVEN applicant IS AN Applicant @desc The applicant's details
GIVETH A NUMBER
DECIDE `calculate premium` IS
    IF applicant's `risk score` > 0.7
    THEN applicant's `age` * 100
    ELSE IF applicant's `is existing customer`
         THEN applicant's `age` * 40
         ELSE applicant's `age` * 60

@export Check whether the applicant qualifies for a discount
GIVEN applicant IS AN Applicant @desc The applicant to check
GIVETH A BOOLEAN
DECIDE `qualifies for discount` IF
        applicant's `is existing customer`
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

In VS Code, open the file, open the **L4** sidebar and select the **Deploy** tab. It lists every exported rule in the file, with its description, inputs and result type. If the list is empty, the file has no `@export` or does not type-check.

---

## Step 3: Deploy

1. In the sidebar, sign in to your [Legalese Cloud](https://legalese.cloud) account.
2. Check the list of exported rules.
3. Click **Deploy**.
4. Enter a **deployment name**, such as `insurance-premium`. It becomes part of the API address: 1 to 36 characters, using letters, digits, hyphens and underscores.
5. Click **Deploy Now**.

**Deploy** stays off while the file or a module it imports has an error: a parse or type error, an `IMPORT` that finds no module, or an import cycle. The sidebar lists the errors; click one to go to it. Warnings and failing `#ASSERT`s don't stop a deploy.

The extension uploads the file and the service compiles it, and its status goes through **Pending** (uploaded), **Compiling**, then **Ready** (live) or **Failed** (with the compiler's error message).

### Update a deployment

Deploying to a name that already exists updates that deployment. The extension first checks for **breaking changes**, such as a removed rule, a removed or renamed input, or a changed result type, and warns you before you confirm. [Manage rules in git and CI](../getting-started/version-control-for-rules.md#redeploy-when-a-merge-changes-a-live-api) explains which changes break callers.

### From the command line

The `l4` command deploys the same way. Sign in once with the `legalese` command (`l4 install legalese`, then `legalese login`), then run `l4 deploy insurance-premium.l4` to create the deployment and `l4 redeploy insurance-premium.l4` to update it; `redeploy` refuses breaking changes unless you add `--force`. `l4 deployments` lists your deployments and `l4 undeploy NAME` removes one. With `--server`, the same commands deploy to a jl4-service you run yourself. See [Using the l4 CLI](../getting-started/l4-cli.md).

---

## Step 4: Manage deployments

The **Deployments** tab in the sidebar lists your organization's deployments, with each one's rules, descriptions and inputs. From there you can open a deployment's **Integrate** dialog, which shows its addresses for each kind of client, or **Undeploy** it. Undeploying asks for confirmation, because it breaks every integration that uses the deployment.

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
        "is-existing-customer": true
      }
    }
  }'
```

`{orgSlug}` is your organization on Legalese Cloud. In the address and the arguments, spaces in names become hyphens: the rule `` `calculate premium` `` is `calculate-premium`, and the field `` `risk score` `` is `"risk-score"`. The answer:

```json
{ "contents": { "result": { "value": 1400 } }, "tag": "SimpleResponse" }
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
