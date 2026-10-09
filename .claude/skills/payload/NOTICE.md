# Notice (added by Itri Group; not part of upstream)

- Source: https://github.com/payloadcms/payload - `tools/claude-plugin/skills/payload` at tag v3.90.2
- Upstream commit: 6254c3bf561a205223849a6497d7dae824d4e81b
- License: MIT - Copyright (c) 2018-2026 Payload CMS, LLC (full text in UPSTREAM-LICENSE.md, from the upstream repo root)
- **Modified by Itri Group** (MIT allows this). Only deletions, nothing added or reworded:
  - `SKILL.md`: removed the "Quick Start" commands (`npx create-payload-app`, `pnpm dev`), the "Resources" link list
    (including `llms-full.txt`), and the four plugin-development rows and link.
  - `reference/ENDPOINTS.md`: removed the "Resources" link list.
  - `reference/ADVANCED.md`: removed the "TypeScript Type References" section (links plus "fetch these URLs").
  - `reference/PLUGIN-DEVELOPMENT.md`: removed (we don't build Payload plugins; npm scripts and links).
- A record of what was removed is `.claude/skills-patches/payload.diff`. To verify: check out the upstream commit and run
  `scripts/check-skill-upstream.sh <upstream>/tools/claude-plugin/skills/payload payload` (deletions only, nothing added).
