# 2026-10-11 - a review longer than 60000 characters is posted again

Founder change (`scripts/check-claude-answer.sh`, pins).

- The first full review of PR #19 after the founders' fix round (run 38107504625) produced six reports over 60000
  characters. `check-claude-answer.sh answer` cut the text with `jq | head -c 60000`; under `pipefail` the early close
  killed `jq` (exit 141), the step failed and nothing was posted. The text is now read whole and cut in bash. The test
  asserts exit 0 on a long answer.
