### Rule: ask for identity and scope — never infer it from the local session

**NEVER derive who the user is, or what they are targeting, from state that happens to be
active on the machine.** Every one of these is an answer the user gives, not something to read:

| Never infer | From |
|---|---|
| nullplatform organization / account / NRN | `~/.np`, a cached session, or "the only one in the list" |
| AWS account or profile | `~/.aws/config`, `AWS_PROFILE`, an active SSO session, `aws sts get-caller-identity` |
| Azure subscription or tenant | `az account show`, "the only subscription visible" |
| GCP project | `gcloud config get-value project` |
| The application domain, public or private | the account slug, or any other value already on disk |
| The DNS parent zone | string surgery on the subdomain |

**The distinction that matters**: those same commands are the right tool for **verifying** what the
user told you. `az account show` to confirm the active subscription *matches* the one in
`terraform.tfvars` is correct and expected. `az account show` to *decide* which subscription to
use is not.

So: ask first, then verify the environment agrees, and stop if it does not.

**Why**: whoever is talking to Claude is frequently not the owner of the target. An implementation
engineer has half a dozen client profiles configured, a shared workstation carries whatever the
last run left active, and "the only account in the list" is an artifact of that person's
permissions, not of the client's setup. Inferring silently sends real resources to the wrong
tenant, and the failure surfaces after the apply — as a cluster in the wrong subscription, or a
DNS record in the wrong zone.

**One more, specific to domains**: a domain is not just a variable, it is what the DNS delegation
later depends on. `{account_slug}.nullapps.io` is a reasonable *suggestion* for an internal PoC and
wrong for any client that owns its own domain. Offer it as a default the user confirms or replaces,
never as a value you filled in.

**Exception**: none for identity. If the user cannot answer, stop and say what is missing — do not
proceed on a guess and do not pick "the obvious one". The one thing you may fill in without asking
is a value the user already gave you earlier in the same conversation.
