# 2026-10-09 - Instant fix rounds

- When the review team fails an agent's PR (`agent/` branch), the review job starts a manager shift right away
  (`gh workflow run agent-manager.yml`), so the builder starts fixing within minutes instead of waiting for the hourly shift.
- Only one manager shift runs at a time; extra starts wait in line. Founder PRs never start a shift.
- The manager accepts these automatic starts only from the review job's own token and only without "focus" text.
