# Docs

Start here. These pages say what the repo does today and what is still planned.

## Status words

These three words are defined here, once. Every docs page uses them with this meaning.

- **Built**: the code exists in this repo today.
- **Reserved**: the folder, package, name or setting exists or is set aside in this repo, but nothing uses it yet.
  Placeholder packages (`apps/admin`, `services/*`, `packages/*`) are Reserved.
- **Planned**: the behavior is designed, but its code is not in this repo yet. The design may come from
  [CLAUDE.md](../CLAUDE.md), or from a review addition marked "proposed", which is not a rule until its approver says yes.

## Who reads what

| Folder or page                           | For                          | Start with                                      |
| ---------------------------------------- | ---------------------------- | ----------------------------------------------- |
| [Architecture](architecture.md)          | Engineers and agents         | What is built, where each kind of data lives    |
| [Data flow](data-flow.md)                | Engineers and agents         | How a lead moves through the platform (Planned) |
| [API index](api/README.md)               | Engineers and integrators    | Every endpoint and webhook (none built yet)     |
| [Help center index](help/README.md)      | Dealers and their staff      | Plain-English steps for each task (none yet)    |
| [Runbooks index](runbooks/README.md)     | Whoever is on call or fixing | What to do when something breaks                |
| [Developer setup](dev/setup.md)          | Engineers and builder agents | Install, run the checks, add a workspace        |
| [Environment variables](dev/env-vars.md) | Engineers, founders          | Every variable in `.env.example` and its status |
| `changelog/`                             | Everyone                     | One file per release, named by date and topic   |

Company rules for every agent are in [CLAUDE.md](../CLAUDE.md). The agent setup is in [SETUP.md](../SETUP.md).

## Rules that apply to every page

- No real customer data. Examples use fake data only, and fake SSNs use the 900-xx-xxxx range.
- No secrets. Write placeholders such as `<password>`. Real values live in Railway or GitHub secrets, never in docs.
- No internal URLs with tokens.
- When the code and a doc disagree, the code wins. Fix the doc in the same pull request and say so in its description.
