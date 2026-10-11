#!/usr/bin/env bash
# Tests scripts/check-founder-merge.sh with a stub 'gh' that serves JSON files from a temp folder and logs every write.
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-founder-merge.sh"
TMPROOT="${TMPDIR:-/tmp}"
command -v jq >/dev/null || { echo "ERROR: jq required"; exit 2; }
W=$(mktemp -d "$TMPROOT/fm.XXXXXX") || exit 2; trap 'rm -rf "$W"' EXIT
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-testlib.sh"
SHA=0123456789abcdef0123456789abcdef01234567
# The stub: GET paths map to $W/<path with / as _>.json (jq applied); PUT/DELETE are logged to $W/writes; missing file = API error.
cat > "$W/gh" <<STUB
#!/usr/bin/env bash
m=GET; q=.; path=""; args=()
while [ \$# -gt 0 ]; do case "\$1" in api|--paginate) ;; -X) m=\$2; shift;; --jq) q=\$2; shift;; -f) args+=("\$2"); shift;; *) [ -z "\$path" ] && path=\$1;; esac; shift; done
[ "\$m" = GET ] || { echo "\$m \$path \${args[*]}" >> "$W/writes"; [ -f "$W/fail-\$m" ] && exit 1; exit 0; }
f="$W/\$(printf '%s' "\${path%%\\?*}" | tr '/' '_').json"; [ -f "\$f" ] || exit 1
jq -r "\$q" "\$f"
STUB
chmod +x "$W/gh"
reset() { rm -f "$W"/*.json "$W/writes" "$W"/fail-*; : > "$W/writes"
  echo '[{"number":7}]' > "$W/repos_o_r_pulls.json"
  pr '["ready-to-merge"]' true clean false
  checks '[{"name":"review","status":"completed","conclusion":"success"},{"name":"guards","status":"completed","conclusion":"success"},{"name":"checks","status":"completed","conclusion":"success"},{"name":"post","status":"completed","conclusion":"skipped"}]'
  files '[{"filename":"services/intake/src/adf.ts"},{"filename":"docs/api/intake.md"}]'; }
pr() { # pr <labels-json> <mergeable> <state> <draft> [headrepo]
  jq -n --argjson l "$1" --argjson m "$2" --arg s "$3" --argjson d "$4" --arg hr "${5:-o/r}" --arg sha "$SHA" \
    '{draft:$d, mergeable:$m, mergeable_state:$s, head:{sha:$sha, ref:"agent/7-x", repo:{full_name:$hr}}, labels:($l|map({name:.})), title:"#7 Intake adf"}' > "$W/repos_o_r_pulls_7.json"; }
checks() { jq -n --argjson c "$1" '{check_runs:$c}' > "$W/repos_o_r_commits_${SHA}_check-runs.json"; }
files() { printf '%s' "$1" > "$W/repos_o_r_pulls_7_files.json"; }
run() { # run <ok|fail> <name> <message> [--dry-run]
  out=$(GH="$W/gh" GH_REPO=o/r bash "$SCRIPT" ${4:-} 2>&1); rc=$?; assert_result "$1" "$rc" "$2" "$3" "$out"; }
not_merged() { ! grep -q "^PUT" "$W/writes"; }

reset; run ok "a cleared PR is squash-merged with its title and its branch deleted" "#7: merged (squash, $SHA): #7 Intake adf"
check "merge: the PUT names the head sha (no merging a later push) and the branch is deleted" bash -c 'grep -q "^PUT repos/o/r/pulls/7/merge merge_method=squash sha=$2 commit_title=#7 Intake adf (#7)$" "$1" && grep -q "^DELETE repos/o/r/git/refs/heads/agent/7-x" "$1"' _ "$W/writes" "$SHA"
reset; run ok "dry run merges nothing" "#7: would merge (dry run): #7 Intake adf" --dry-run; check "dry run: no writes" not_merged
reset; pr '["ready-to-merge"]' true clean true; run ok "a draft is skipped" "#7: draft"; check "draft: not merged" not_merged
reset; pr '["ready-to-merge"]' true clean false x/fork; run ok "a fork is skipped" "head is not a branch of this repository (x/fork)"; check "fork: not merged" not_merged
reset; pr '["reviews-passed"]' true clean false; run ok "without ready-to-merge nothing happens" "#7: not ready-to-merge (labels: reviews-passed)"; check "no label: not merged" not_merged
reset; pr '[]' true clean false; run ok "no labels at all" "#7: not ready-to-merge (labels: none)"
for bad in blocked changes-requested escalated; do
  reset; pr "[\"ready-to-merge\",\"$bad\"]" true clean false; run ok "label $bad wins over ready-to-merge" "#7: label $bad"; check "$bad: not merged" not_merged
done
reset; pr '["ready-to-merge"]' false dirty false; run ok "a conflict is skipped" "#7: not mergeable (mergeable=false state=dirty)"; check "conflict: not merged" not_merged
reset; pr '["ready-to-merge"]' true unstable false; run ok "anything but a clean state is skipped" "#7: not mergeable (mergeable=true state=unstable)"
reset; checks '[{"name":"review","status":"in_progress","conclusion":null},{"name":"guards","status":"completed","conclusion":"success"},{"name":"checks","status":"completed","conclusion":"success"}]'
run ok "a stale label: the head's review is still running" "#7: check 'review' has not passed on $SHA"; check "review running: not merged" not_merged
reset; checks '[{"name":"review","status":"completed","conclusion":"success"},{"name":"guards","status":"completed","conclusion":"failure"},{"name":"checks","status":"completed","conclusion":"success"}]'
run ok "guards red" "#7: check 'guards' has not passed on $SHA"; check "guards red: not merged" not_merged
reset; checks '[{"name":"review","status":"completed","conclusion":"success"},{"name":"guards","status":"completed","conclusion":"success"}]'
run ok "CI checks missing on the head" "#7: check 'checks' has not passed on $SHA"
reset; checks '[{"name":"review","status":"completed","conclusion":"success"},{"name":"guards","status":"completed","conclusion":"success"},{"name":"checks","status":"completed","conclusion":"success"},{"name":"lock","status":"completed","conclusion":"failure"}]'
run ok "any other red check run blocks too" "#7: check run not green: lock completed failure"; check "other red: not merged" not_merged
for f in CLAUDE.md apps/admin/CLAUDE.md .claude/agents/x.md .github/workflows/ci.yml scripts/check-x.sh .gitleaks.toml packages/data/override-allowlist.txt .yarnrc.yml packages/contracts/src/lead.ts; do
  reset; files "[{\"filename\":\"$f\"}]"; run ok "founder-only or contracts file $f needs a founder" "#7: needs a founder (founder-only or contracts files: $f )"; check "$f: not merged" not_merged
done
reset; files '[{"filename":"services/x.ts","previous_filename":"packages/contracts/old.ts"}]'; run ok "a rename out of a founder path counts" "needs a founder"
reset; echo '[]' > "$W/repos_o_r_pulls.json"; run ok "no open PRs" "No open pull requests."
reset; rm "$W/repos_o_r_pulls.json"; run fail "listing PRs fails" "ERROR: could not list the open pull requests."
reset; rm "$W/repos_o_r_pulls_7.json"; run fail "reading a PR fails" "ERROR: could not read pull request #7."
reset; rm "$W/repos_o_r_commits_${SHA}_check-runs.json"; run fail "reading check runs fails" "ERROR: could not read the check runs of #7."
reset; rm "$W/repos_o_r_pulls_7_files.json"; run fail "listing files fails" "ERROR: could not list the files of #7."
reset; touch "$W/fail-PUT"; run fail "GitHub refuses the merge" "ERROR: merging #7 failed"
reset; echo '[{"number":7},{"number":8}]' > "$W/repos_o_r_pulls.json"; cp "$W/repos_o_r_pulls_7.json" "$W/repos_o_r_pulls_8.json"; cp "$W/repos_o_r_pulls_7_files.json" "$W/repos_o_r_pulls_8_files.json"
run ok "two cleared PRs: both merged, counted" "Merged 2 pull request(s)."
out=$(GH="$W/gh" bash "$SCRIPT" 2>&1); [ $? != 0 ] && [[ "$out" == *"GH_REPO"* ]] && t PASS "GH_REPO required" || t FAIL "GH_REPO required: $out"
summary
