#!/usr/bin/env bash
# One-time GitHub setup: labels and the two report issues.
# Run from the repo folder after `gh auth login`:  bash scripts/setup-github.sh
set -euo pipefail

label() { gh label create "$1" --color "$2" --description "$3" --force >/dev/null && echo "label: $1"; }

# Status
label "status:todo"         "ededed" "Ready for the manager to pick"
label "status:in-progress"  "1d76db" "An agent is working on it"
label "blocked"             "b60205" "Needs a founder decision"
# Review flow
label "changes-requested"   "d93f0b" "Review team found problems; manager sends fixes"
label "reviews-passed"      "0e8a16" "All reviewers passed with zero findings"
label "ready-to-merge"      "0e8a16" "Founder: review and merge"
label "round-1"             "fbca04" "Review round 1"
label "round-2"             "fbca04" "Review round 2"
label "round-3"             "e99695" "Review round 3 (next: Chief Engineer)"
label "escalated"           "7057ff" "Chief Engineer took over"
# Priority
label "priority:1"          "b60205" "Do first"
label "priority:2"          "d93f0b" "Next"
label "priority:3"          "fbca04" "Later"
# Agents
for a in builder-intake builder-ai builder-crm builder-inventory builder-finance tester designer devops docs founder; do
  label "agent:$a" "5319e7" "Owned by $a"
done
# Areas
for a in intake ai crm inventory website finance platform security architecture compliance devops design docs; do
  label "area:$a" "c5def5" "Area: $a"
done

# Report issues the agents post to
gh issue list --search "Manager log in:title" --state open --json number -q '.[0].number' | grep -q . \
  || gh issue create --title "Manager log" --body "The manager posts a log here after every shift."
gh issue list --search "Daily reports in:title" --state open --json number -q '.[0].number' | grep -q . \
  || gh issue create --title "Daily reports" --body "Daily founder reports and weekly audits. Subscribe to get them by email."

echo "Done. Pin the 'Daily reports' issue and click Subscribe on it."
