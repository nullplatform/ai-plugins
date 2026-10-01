# Project context: the `.np/` directory

A repository can carry its nullplatform context in a `.np/` directory at the
repo root. Every nullplatform skill loads it through the `np-api` pre-flight,
so an agent opened inside the repo already knows which application it is
working on. The same files work on every runtime that executes these skills
(Claude Code, Codex, Kiro): the behaviour is described in prose, the script is
a convenience.

## What gets loaded

Everything. The loader reads every regular file directly under `.np/`
(non-recursive, any extension) and puts it in context under a
`### .np/<file>` header. It does not validate or parse anything except
`application.yaml`. Use the other files for whatever the team wants an agent
to know about this repo: conventions, runbooks, "this repo is a scope, not an
application", a `context.yaml` with `kind: scope` and notes.

Skipped with a one-line note: files over 64 KB and files containing NUL bytes.

```bash
${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/np-context.sh load           # exit 3 → no .np/
${CLAUDE_PLUGIN_ROOT}/skills/np-api/scripts/np-context.sh load --root /path/to/repo
```

## `application.yaml`

The only file with a defined shape. It is what `/np-api context init` writes;
hand-written files with the same keys work the same.

```yaml
version: 1
repository:
  name: acme/payments-api                    # <org>/<repo> from the canonical URL
  url: https://github.com/acme/payments-api  # canonical https form
  app_path: services/payments                # only for monorepo applications
nullplatform:
  base_url: https://acme.app.nullplatform.io
  account_id: "712638527"
  namespace_id: "1002190236"
  application_id: "856012838"
  application_slug: payments-api             # human-readable, not used for lookups
```

- IDs are strings.
- `nullplatform.*` are the session defaults for any skill that needs an
  application, namespace or account. `base_url` is also the prefix for UI links
  (`<base_url>/account/<a>/namespace/<n>/application/<id>`).
- The file is guidance. An explicit instruction in the session (another
  application, namespace, account, organization) wins for that task.
- If the application it points to answers 404, say so once, ignore the
  defaults for that task and suggest `/np-api context init`.

## Generating it: `/np-api context init`

The command asks which application the repository is and derives the rest.
Hints come from the git remote; the user can always answer with a UI link or
an application id. See the `np-api` SKILL.md for the step-by-step flow. Script
subcommands used by that flow:

| Subcommand | What it does | Exit codes |
|------------|--------------|-----------|
| `discover [--remote <url>] [--path <p>]` | Canonical remote URL → `GET /application?repository_url=` (retries once with `.git`) → JSON `{canonical_url, candidates, match}` | 0; 2 no remote |
| `parse-link <ui-link>` | JSON `{base_url, account_id, namespace_id, application_id}` from a console link | 0; 2 not a link |
| `init --app <id> \| --link <link> [--write [--force]] [--root <dir>]` | Print (and optionally save) `application.yaml` | 0; 1 app not found; 2 bad input; 4 refused overwrite |
| `match-app <id> [--remote <url>] [--path <p>]` | Is `<id>` the application of this repository? JSON `{match, reason, application_slug, canonical_url, path}` | 0 match; 1 no match / not found; 2 no remote |
| `remote-url [<url>]` | Canonical https form of the remote | 0; 2 |

`init` never prompts. Confirmation before `--write`, and before `--force`, is
the skill's job.

## When the skill offers to create it

Never up front. A repository without `.np/` gets no hint on its own: it may be
a scope, a service, an infra repo, or nothing to do with nullplatform, and
guessing costs an API call per session and a question nobody asked for.

The offer happens only when the session already has a concrete application on
the table (the user passed an id, a UI link, or a name that was resolved) and
`match-app <id>` exits 0: the repository's remote is that application's
`repository_url`, and for monorepos the current directory is its
`repository_app_path`. Then the skill offers once per session to save
`.np/application.yaml`, and proceeds through `init` only after a yes. A
different repository, no remote, or an unknown application means silence.

### How the fields are derived

| Field | Source |
|-------|--------|
| `application_id` | The user's answer (candidate, link or id) |
| `account_id`, `namespace_id` | The application's NRN. A link also carries them; if they disagree, the NRN wins and the discrepancy is printed |
| `base_url` | The link's origin → `NP_LOGIN_URL` → `https://<organization slug>.app.nullplatform.io` |
| `repository.url` | The application's `repository_url`, normalized; the git remote if the entity has none |
| `repository.app_path` | `repository_app_path`, only when `is_mono_repo` is true |

### Remote URL normalization

`GET /application?repository_url=` is an exact match against the stored URL,
which is the plain https form. `discover` and `init` normalize before
querying:

| Input | Canonical |
|-------|-----------|
| `git@github.com:org/repo.git` | `https://github.com/org/repo` |
| `ssh://git@github.com/org/repo.git` | `https://github.com/org/repo` |
| `https://github.com/org/repo.git` | `https://github.com/org/repo` |
| `https://GitHub.com/org/repo/` | `https://github.com/org/repo` |
| `https://user:token@github.com/org/repo` | `https://github.com/org/repo` |

Host lowercased, credentials and port stripped, `.git` and trailing slash
removed, path case preserved, any host. If the canonical form returns nothing,
`discover` retries once with a `.git` suffix.

### Monorepos

Several applications can share one `repository_url`, each with its own
`repository_app_path`. `discover` compares each candidate's path with the
current directory relative to the repo root (`git rev-parse --show-prefix`).
Exactly one match → `match` is set. Otherwise `match` is `null` and all
candidates are returned so the skill can ask.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `load` exits 3 | No `.np/` at the repo root | Run `/np-api context init`, or create the directory by hand |
| `discover` returns no candidates for a repo that is an application | The stored `repository_url` differs from the remote (different host, renamed repo) | Answer the question with the UI link or the application id |
| `init` exits 1 | Application id does not exist or the token cannot see it | Check the id; `/np-api check-auth` for the org the token belongs to |
| `init` exits 4 | `application.yaml` exists with different content | Show the diff to the user; `--write --force` only after they agree |
| `base_url` is wrong | `NP_LOGIN_URL` set for another org, or organization slug differs from the console host | Pass the UI link to `init`, or edit the file |
| Skills keep asking "which application?" | `.np/` is not at the repo root, or the file is not named `application.yaml` | `np-context.sh load` shows what is being read |
