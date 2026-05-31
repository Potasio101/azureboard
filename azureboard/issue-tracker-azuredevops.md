# Issue tracker: Azure DevOps

Issues and PRDs for this repo live as Azure Boards Work Items. Use the `az boards` CLI (part of the [Azure DevOps extension](https://learn.microsoft.com/en-us/azure/devops/cli/)) for all operations.

## Setup (one-time per machine)

```bash
# Install the extension if not already present
az extension add --name azure-devops

# Set defaults so you don't have to repeat --org / --project on every command
az devops configure --defaults \
  organization=https://dev.azure.com/<org> \
  project=<project>

# Authenticate (opens browser)
az login
```

Infer the org and project from `git remote -v` — the URL pattern is
`https://dev.azure.com/<org>/<project>/_git/<repo>`.

## Work item types

Azure DevOps uses typed work items instead of generic "issues":

| Concept           | ADO type      | Valid states                                         |
| ----------------- | ------------- | ---------------------------------------------------- |
| Feature / story   | `Task`*       | _(run setup skill to discover)_                      |
| Bug               | `Bug`         | _(run setup skill to discover)_                      |
| Task / chore      | `Task`        | _(run setup skill to discover)_                      |
| Epic / PRD        | `Epic`        | _(run setup skill to discover)_                      |
| Technical debt    | `Task`        | _(run setup skill to discover)_                      |
| Issue             | `Task`        | _(run setup skill to discover)_                      |

> **\* Process-template note:** Types vary by process template (Basic, Agile, Scrum, CMMI) and custom templates. Valid states are even more volatile — they differ per template AND per type and must always be fetched live. The setup skill discovers both using:
> ```bash
> # Types
> az devops invoke \
>   --org https://dev.azure.com/<org> \
>   --area wit --resource workitemtypes \
>   --route-parameters project=<project> \
>   --output json --query "value[].name"
>
> # States per type
> az devops invoke \
>   --org https://dev.azure.com/<org> \
>   --area wit --resource workitemtypestates \
>   --route-parameters project=<project> type=<TypeName> \
>   --output json --query "value[].name"
> ```
> The generated `docs/agents/issue-tracker.md` contains the actual types **and states** for this project.

Choose the most appropriate type when creating work items.

## Before any az boards command

Always re-apply project defaults first. `az devops configure --defaults` is machine-global — if you switch repos without resetting it, commands will silently target the wrong project.

```bash
az devops configure --defaults \
  organization=https://dev.azure.com/<org> \
  project=<project>
```

The setup skill fills in the correct `<org>` and `<project>` values from `git remote -v` when generating `docs/agents/issue-tracker.md`.

## Conventions

- **Create a work item**:
  ```bash
  az boards work-item create \
    --type "User Story" \
    --title "..." \
    --description "..." \
    --assigned-to "user@example.com"   # optional
  ```
  Use `--type Bug`, `--type Task`, or `--type Epic` as appropriate.

- **Read a work item**:
  ```bash
  az boards work-item show --id <id> --output json
  ```

- **List work items** (via WIQL query):
  ```bash
  az boards query \
    --wiql "SELECT [System.Id],[System.Title],[System.State],[System.Tags] \
            FROM WorkItems \
            WHERE [System.TeamProject] = '<project>' \
              AND [System.State] <> 'Closed' \
            ORDER BY [System.ChangedDate] DESC" \
    --output json
  ```
  Filter by tag: add `AND [System.Tags] CONTAINS 'ready-for-agent'` to the WHERE clause.

- **Comment on a work item**:
  ```bash
  az boards work-item update --id <id> --discussion "..."
  ```

- **Apply tags** (Azure DevOps uses semicolon-separated tags, not labels):
  ```bash
  # Add a tag (preserve existing ones — fetch first, then set)
  CURRENT=$(az boards work-item show --id <id> --query "fields.\"System.Tags\"" -o tsv)
  az boards work-item update --id <id> --fields "System.Tags=${CURRENT}; needs-triage"
  ```

- **Change state** — states vary by process template:

  | Process template | In progress | Complete |
  | ---------------- | ----------- | -------- |
  | Basic (default)  | `Doing`     | `Done`   |
  | Agile            | `Active`    | `Closed` |
  | Scrum            | `Active`    | `Done`   |
  | CMMI             | `Active`    | `Closed` |

  ```bash
  # Check which states exist for a type in your project:
  az devops invoke \
    --org https://dev.azure.com/<org> \
    --area wit --resource workitemtypestates \
    --route-parameters project=<project> type=Task \
    --output json --query "value[].name"

  az boards work-item update --id <id> --state "Doing"   # in progress
  az boards work-item update --id <id> --state "Done"    # complete (Basic)
  ```

- **Close/complete a work item**:
  ```bash
  # Post a closing comment first, then mark complete
  az boards work-item update --id <id> --discussion "Completed: ..."
  az boards work-item update --id <id> --state "Done"    # Basic process
  # az boards work-item update --id <id> --state "Closed" # Agile/CMMI process
  ```

- **Create a Pull Request**:
  ```bash
  az repos pr create \
    --title "..." \
    --description "..." \
    --source-branch <branch> \
    --target-branch main \
    --work-items <id>   # link to work item(s)
  ```

- **View a Pull Request**:
  ```bash
  az repos pr show --id <pr-id> --output json
  ```

## Triage tags (Azure DevOps uses tags instead of labels)

The five canonical triage roles map to tags applied to work items:

| Role              | Tag string        |
| ----------------- | ----------------- |
| `needs-triage`    | `needs-triage`    |
| `needs-info`      | `needs-info`      |
| `ready-for-agent` | `ready-for-agent` |
| `ready-for-human` | `ready-for-human` |
| `wontfix`         | `wontfix`         |

## When a skill says "publish to the issue tracker"

Create an Azure Boards work item using `az boards work-item create`. Choose
`User Story` for features/PRDs, `Bug` for defects, `Task` for chores.

## When a skill says "fetch the relevant ticket"

Run `az boards work-item show --id <id> --output json`.

## Useful extras

```bash
# Open work item in browser
az boards work-item show --id <id> --open

# List all PRs for this repo
az repos pr list --output table

# Show iterations (sprints)
az boards iteration project list --output table
```
