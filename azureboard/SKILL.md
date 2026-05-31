---
name: setup-matt-pocock-skills
description: Sets up an `## Agent skills` block in AGENTS.md/CLAUDE.md and `docs/agents/` so the engineering skills know this repo's issue tracker (GitHub or local markdown), triage label vocabulary, and domain doc layout. Run before first use of `to-issues`, `to-prd`, `triage`, `diagnose`, `tdd`, `improve-codebase-architecture`, or `zoom-out` — or if those skills appear to be missing context about the issue tracker, triage labels, or domain docs.
disable-model-invocation: true
---

# Setup Matt Pocock's Skills

Scaffold the per-repo configuration that the engineering skills assume:

- **Issue tracker** — where issues live (GitHub by default; local markdown is also supported out of the box)
- **Triage labels** — the strings used for the five canonical triage roles
- **Domain docs** — where `CONTEXT.md` and ADRs live, and the consumer rules for reading them

This is a prompt-driven skill, not a deterministic script. Explore, present what you found, confirm with the user, then write.

## Process

### 1. Explore

Look at the current repo to understand its starting state. Read whatever exists; don't assume:

- `git remote -v` and `.git/config` — is this a GitHub repo? Which one?
- `AGENTS.md` and `CLAUDE.md` at the repo root — does either exist? Is there already an `## Agent skills` section in either?
- `CONTEXT.md` and `CONTEXT-MAP.md` at the repo root
- `docs/adr/` and any `src/*/docs/adr/` directories
- `docs/agents/` — does this skill's prior output already exist?
- `.scratch/` — sign that a local-markdown issue tracker convention is already in use

### 2. Present findings and ask

Summarise what's present and what's missing. Then walk the user through the three decisions **one at a time** — present a section, get the user's answer, then move to the next. Don't dump all three at once.

Assume the user does not know what these terms mean. Each section starts with a short explainer (what it is, why these skills need it, what changes if they pick differently). Then show the choices and the default.

**Section A — Issue tracker.**

> Explainer: The "issue tracker" is where issues live for this repo. Skills like `to-issues`, `triage`, `to-prd`, and `qa` read from and write to it — they need to know whether to call `gh issue create`, write a markdown file under `.scratch/`, or follow some other workflow you describe. Pick the place you actually track work for this repo.

Default posture: these skills were designed for GitHub. If a `git remote` points at GitHub, propose that. If a `git remote` points at GitLab (`gitlab.com` or a self-hosted host), propose GitLab. If a `git remote` points at `dev.azure.com` or `visualstudio.com`, propose Azure DevOps. Otherwise (or if the user prefers), offer:

- **GitHub** — issues live in the repo's GitHub Issues (uses the `gh` CLI)
- **GitLab** — issues live in the repo's GitLab Issues (uses the [`glab`](https://gitlab.com/gitlab-org/cli) CLI)
- **Azure DevOps** — work items live in Azure Boards (uses the `az boards` CLI via the azure-devops extension); triage roles map to semicolon-separated tags
- **Local markdown** — issues live as files under `.scratch/<feature>/` in this repo (good for solo projects or repos without a remote)
- **Other** (Jira, Linear, etc.) — ask the user to describe the workflow in one paragraph; the skill will record it as freeform prose

**If Azure DevOps is confirmed — run live discovery before moving to Section B:**

Always extract org and project from `git remote -v` — never from `az devops configure --defaults` (which is machine-global and may point to a different repo).

```
URL pattern: https://<user>@dev.azure.com/<org>/<project>/_git/<repo>
Extract:     org     = https://dev.azure.com/<org>
             project = <project>
```

Then run the following steps in order:

1. **Query work item types** (using org/project from git remote, not global config):
   ```bash
   az devops invoke \
     --org https://dev.azure.com/<org> \
     --area wit --resource workitemtypes \
     --route-parameters project=<project> \
     --output json --query "value[].name"
   ```
   If this fails (not authenticated or extension not installed) — **pause** and tell the user:
   > "I need to query your Azure Board to get the real work item types. Please run:
   > `az extension add --name azure-devops && az login`
   > Tell me when you're ready."
   Then retry with the same org/project from git remote.

2. **Filter out system types** — remove these 9 types that exist in every Azure DevOps project and are never created manually:
   `Test Case`, `Test Plan`, `Test Suite`, `Shared Steps`, `Shared Parameter`,
   `Code Review Request`, `Code Review Response`, `Feedback Request`, `Feedback Response`

3. **Query states for each remaining type**:
   ```bash
   az devops invoke \
     --org https://dev.azure.com/<org> \
     --area wit --resource workitemtypestates \
     --route-parameters project=<project> type=<TypeName> \
     --output json --query "value[].name"
   ```

4. **Build the canonical mapping** — for each concept, resolve the ADO type using these rules:

   - If only one candidate exists → use it directly, no question needed.
   - If multiple candidates are valid for the same concept → **ask the user to choose** before proceeding. Do not guess.

   Resolution rules per concept:

   | Concept          | Check types in this order                 | Ask when…                                             |
   | ---------------- | ----------------------------------------- | ----------------------------------------------------- |
   | Feature / story  | `User Story`, `Issue`, `Feature`, `Task`  | both `User Story` **and** `Task` exist in the project |
   | Bug              | `Bug`, else fall back to Feature/story type | only if no dedicated `Bug` type exists              |
   | Task / chore     | `Task`                                    | rarely ambiguous                                      |
   | Epic / PRD       | `Epic`                                    | rarely ambiguous                                      |
   | Technical debt   | same as Task / chore                      | inherit Task/chore resolution                         |

   Example question for Feature/story ambiguity:
   > "Tu proyecto tiene disponibles `User Story` y `Task`. Para el concepto Feature/story, ¿cuál usamos?"

   Resolve **all** ambiguities before moving to step 5 — the proposed table is built with confirmed types only.

5. **Show the proposed mapping to the user for confirmation** before writing anything. The table MUST include the `Valid states` column populated from the state queries you ran in step 3. States come **only** from the live `az devops invoke` results — never guess or assume them. States differ across Basic, Agile, Scrum, CMMI, and custom templates; the only correct source is your project's live data. Example (the states shown are from a real Agile project — yours will differ):

   ```
   Discovered types: User Story, Bug, Task, Epic

   Proposed mapping (states fetched live from your project):

   | Concept          | ADO type      | Valid states (discovered)                           |
   | ---------------- | ------------- | --------------------------------------------------- |
   | Feature / story  | `User Story`  | New → Active → Resolved → Closed · Removed          |
   | Bug              | `Bug`         | New → Active → Resolved → Closed                    |
   | Task / chore     | `Task`        | New → Active → Closed · Removed                     |
   | Epic / PRD       | `Epic`        | New → Active → Resolved → Closed · Removed          |
   | Technical debt   | `Task`        | New → Active → Closed · Removed                     |
   | Issue            | `Task`        | New → Active → Closed · Removed                     |

   Does this look right?
   ```

   If states for any type could not be fetched, show the error and ask the user to supply them — **do not omit the column or leave cells empty**.

After the user confirms, write `docs/agents/issue-tracker.md` using the confirmed types and their full discovered state lists.

**Section B — Triage label vocabulary.**

> Explainer: When the `triage` skill processes an incoming issue, it moves it through a state machine — needs evaluation, waiting on reporter, ready for an AFK agent to pick up, ready for a human, or won't fix. To do that, it needs to apply labels (or the equivalent in your issue tracker) that match strings *you've actually configured*. If your repo already uses different label names (e.g. `bug:triage` instead of `needs-triage`), map them here so the skill applies the right ones instead of creating duplicates.

The five canonical roles:

- `needs-triage` — maintainer needs to evaluate
- `needs-info` — waiting on reporter
- `ready-for-agent` — fully specified, AFK-ready (an agent can pick it up with no human context)
- `ready-for-human` — needs human implementation
- `wontfix` — will not be actioned

Default: each role's string equals its name. Ask the user if they want to override any. If their issue tracker has no existing labels, the defaults are fine.

**Section C — Domain docs.**

> Explainer: Some skills (`improve-codebase-architecture`, `diagnose`, `tdd`) read a `CONTEXT.md` file to learn the project's domain language, and `docs/adr/` for past architectural decisions. They need to know whether the repo has one global context or multiple (e.g. a monorepo with separate frontend/backend contexts) so they look in the right place.

Confirm the layout:

- **Single-context** — one `CONTEXT.md` + `docs/adr/` at the repo root. Most repos are this.
- **Multi-context** — `CONTEXT-MAP.md` at the root pointing to per-context `CONTEXT.md` files (typically a monorepo).

### 3. Confirm and edit

Show the user a draft of:

- The `## Agent skills` block to add to whichever of `CLAUDE.md` / `AGENTS.md` is being edited (see step 4 for selection rules)
- The contents of `docs/agents/issue-tracker.md`, `docs/agents/triage-labels.md`, `docs/agents/domain.md`

Let them edit before writing.

### 4. Write

**Pick the file to edit:**

- If `CLAUDE.md` exists, edit it.
- Else if `AGENTS.md` exists, edit it.
- If neither exists, ask the user which one to create — don't pick for them.

Never create `AGENTS.md` when `CLAUDE.md` already exists (or vice versa) — always edit the one that's already there.

If an `## Agent skills` block already exists in the chosen file, update its contents in-place rather than appending a duplicate. Don't overwrite user edits to the surrounding sections.

The block:

```markdown
## Agent skills

### Issue tracker

[one-line summary of where issues are tracked]. See `docs/agents/issue-tracker.md`.

### Triage labels

[one-line summary of the label vocabulary]. See `docs/agents/triage-labels.md`.

### Domain docs

[one-line summary of layout — "single-context" or "multi-context"]. See `docs/agents/domain.md`.
```

Then write the three docs files using the seed templates in this skill folder as a starting point:

- [issue-tracker-github.md](./issue-tracker-github.md) — GitHub issue tracker
- [issue-tracker-gitlab.md](./issue-tracker-gitlab.md) — GitLab issue tracker
- [issue-tracker-azuredevops.md](./issue-tracker-azuredevops.md) — Azure DevOps Boards issue tracker (`az boards` CLI; tags instead of labels)
- [issue-tracker-local.md](./issue-tracker-local.md) — local-markdown issue tracker
- [triage-labels.md](./triage-labels.md) — label mapping
- [domain.md](./domain.md) — domain doc consumer rules + layout

For "other" issue trackers, write `docs/agents/issue-tracker.md` from scratch using the user's description.

### 5. Done

Tell the user the setup is complete and which engineering skills will now read from these files. Mention they can edit `docs/agents/*.md` directly later — re-running this skill is only necessary if they want to switch issue trackers or restart from scratch.
