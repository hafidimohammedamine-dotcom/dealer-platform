# 2026-10-13 - review policy: block on safety, file the rest

Founder decision (`CLAUDE.md`, `.claude/skills/review-pr`, `.claude/skills/manager`). The first product PRs (#52, #54,
#55) spent their first day in review rounds over naming, duplicated lines and wording while every security finding was
already fixed; #54 reached `blocked` over two one-line style changes. From now on a PR merges when **security, tester and
compliance** say PASS with zero findings (and the designer raised no safety or data finding), CI is green and a founder
merges. Architect, docs and other designer findings go under `FOLLOW-UPS` in the review result; the manager files each
as a `follow-up` issue for the same builder (`[follow-up] #<pr>: ...`, `priority:3`), worked like any other issue after
the merge. Escalation and `blocked` apply to blocking findings only. Nothing changes for what is reviewed or how.
