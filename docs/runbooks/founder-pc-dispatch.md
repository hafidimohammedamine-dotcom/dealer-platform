# Founder PC dispatch (heartbeat and agent schedules)

GitHub's `schedule` (cron) trigger is delayed or dropped for hours at times (GitHub community discussion #207346, since
2026-08). The agents' hourly heartbeat (`docs/runbooks/ci-guards.md`, "Heartbeat") and the agent shifts must not wait on
it, so a founder's always-on PC dispatches the workflows on time with the founder's own GitHub login (`gh auth status`
must show the founder account; the agents' account must never be used here - its dispatch of the main guard fails on
purpose and never counts).

Every dispatch is `gh workflow run <file> -R hafidimohammedamine-dotcom/dealer-platform --ref main`:

| Workflow | File | When | Why |
|---|---|---|---|
| Main guard (hourly check) | `main-guard.yml` | every 30 minutes | the heartbeat every Claude job needs (75-minute window) |
| Manager shift | `agent-manager.yml` | every hour at :20 | the cron at :15 may not fire; `concurrency` keeps one shift at a time |
| Daily report | `agent-daily-report.yml` | 11:05 UTC daily | |
| Weekly audit | `agent-weekly-audit.yml` | Sunday 07:05 UTC | |
| Egress lock probe | `egress-lock-claude.yml` | Monday 06:45 UTC | |

GitHub's own cron stays on in every workflow: when it does fire, it is a second run of the same check (harmless; the
manager's `concurrency` group lets one shift finish before the next starts).

## Windows (PC1): one scheduled task per line

Run in PowerShell as the founder (the task runs whether or not anyone is logged in, as long as the PC is on;
`powercfg` keeps PC1 awake, see the PC setup notes). `gh` must be on the system PATH (`winget install GitHub.cli` puts it
there) and logged in as the founder.

```
$r = "hafidimohammedamine-dotcom/dealer-platform"
$gh = (Get-Command gh).Source
schtasks /Create /F /TN "DealerPlatform\MainGuard"   /SC MINUTE /MO 30 /TR "`"$gh`" workflow run main-guard.yml -R $r --ref main"
schtasks /Create /F /TN "DealerPlatform\Manager"     /SC HOURLY /MO 1 /ST 00:20 /TR "`"$gh`" workflow run agent-manager.yml -R $r --ref main"
schtasks /Create /F /TN "DealerPlatform\DailyReport" /SC DAILY /ST 07:05 /TR "`"$gh`" workflow run agent-daily-report.yml -R $r --ref main"
schtasks /Create /F /TN "DealerPlatform\WeeklyAudit" /SC WEEKLY /D SUN /ST 03:05 /TR "`"$gh`" workflow run agent-weekly-audit.yml -R $r --ref main"
schtasks /Create /F /TN "DealerPlatform\LockProbe"   /SC WEEKLY /D MON /ST 02:45 /TR "`"$gh`" workflow run egress-lock-claude.yml -R $r --ref main"
```

The `/ST` times are the PC's local time (PC1 is in US Eastern: 07:05 local = 11:05 UTC in standard time; the hour of a
report does not matter to the agents). Check: `schtasks /Query /TN "DealerPlatform\MainGuard"`, and on GitHub,
Actions -> Main guard shows a `workflow_dispatch` run by the founder every 30 minutes. Remove: `schtasks /Delete /F /TN
"DealerPlatform\MainGuard"` (and the others).

## If the PC is off

Nothing breaks: every Claude job refuses to start until the next successful hourly run (cron or dispatch), and the
manager's next shift catches up. A founder can also dispatch by hand: Actions -> Main guard -> Run workflow (leave
`accept_sha` empty).
