# 2026-10-13 - hardened-step env: the proxy names once (GitHub reads env names without regard to case)

Founder change (`scripts/check-workflows-policy.json`, `scripts/check-workflows-hardened.py`, tests, runbook, pins). The
first push of #44's hardened workflows was refused by GitHub before any job ran: `failed to parse workflow: 'http_proxy'
is already defined` - a step `env:` with both `HTTP_PROXY` and `http_proxy` is a duplicate key to GitHub. The lowercase
twins leave `post_claude_empty_env` (no command in a hardened step uses the network, and the uppercase names stay), and
the checker refuses any two env names on a hardened step that differ only by case, so the file would never reach GitHub
in that state again. One checker test. Nothing on main uses the hardened shell yet (`post_claude_require_shell` is
`false`); #44 turns it on.
