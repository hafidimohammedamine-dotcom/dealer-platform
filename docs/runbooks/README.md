# Runbooks index

A runbook says what to do when something breaks. Runbooks are for the technical team and founders, not for dealers.

## Runbooks that exist

| Runbook                                                                      | When to use it                                                                |
| ---------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| [CI pipeline and build failures](ci-pipeline.md)                             | A step of `ci.yml` fails: install, lint, type check, tests, build, audit      |
| [Guards, review job and CI guard tests](ci-guards.md)                        | A guard, the review job or the main guard fails or posts an unexpected result |
| [Workflow checker](workflow-checker.md)                                      | `scripts/check-workflows.sh` reports a workflow rule                          |
| [Skill guards](skill-guards.md)                                              | A skill check fails: manifest, checksums, license or upstream                 |
| [Agent network lock](agent-network-lock.md)                                  | The agents' egress lock or its tests fail                                     |
| [Founder PC dispatch](founder-pc-dispatch.md)                                | The hourly heartbeat or an agent shift did not start on time                  |
| [Founders' auto-merge](founder-auto-merge.md)                                | The hourly merge did not merge a PR that was ready                            |
| [PAYLOAD_SECRET or FIELD_ENCRYPTION_KEY leaked or lost](key-leak-or-loss.md) | A key leaked or was lost. Partly planned: some steps need tools not built yet |

## Runbooks planned, not written

These are named in the design but have no page yet. Each one will be written when its part of the platform is built.

- **Texting fails** (Planned): Telnyx sends fail, or a consent or quiet-hours check blocks sends.
- **A lender callback is stuck** (Planned): a RouteOne or Dealertrack callback is not processed.
- **The admin is down** (Planned): the Payload admin app does not load.
- **A migration fails** (Planned): the one migration job in CI fails before deploy.

## Related

- [Architecture](../architecture.md): what is built today, where data lives, and CI.
- [Data flow](../data-flow.md): the lead path, step by step (Planned).
- [Developer setup](../dev/setup.md): install and run the checks locally.
- [Environment variables](../dev/env-vars.md): every variable and whether code reads it.
