# Third-party skills (founder-owned)

Every third-party skill here is pinned. Agents never update skills. A founder opens a PR to update one,
and the security reviewer must pass it. CI checks `checksums.sha256` on every PR.

| Skill | Source | Upstream commit | License | Added |
|---|---|---|---|---|
| payload | github.com/payloadcms/skills `skills/payload` | 832d5bc4258ae784f08cb7f03a3a674d6b2fa5f1 | MIT (see payload/NOTICE.md) | 2026-10-09 |

Our own skills (manager, review-pr, daily-report, weekly-audit, payload-dealer-overrides) are not in the checksum file;
they change through normal founder PRs.

To update a pinned skill: install it again, update the commit above, then run
`bash scripts/check-skills.sh --write` and open a PR.
