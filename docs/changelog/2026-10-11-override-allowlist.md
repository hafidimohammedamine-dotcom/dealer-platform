# 2026-10-11 - packages/data/override-allowlist.txt exists (empty)

Founder change. CLAUDE.md Payload rule 1 names `packages/data/override-allowlist.txt` as the only source of system jobs
that may use `overrideAccess: true`. PR #19's review (finding 1) found the lint rule using a plain array instead; the
founder-only file now exists, empty, with its format in the header, so the rule in #19 can read it and its tests can
assert that the array is gone.
