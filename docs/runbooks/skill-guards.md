# Runbook: skill guards (`guards` job)

Founder-owned checks that keep `.claude/skills/` honest. They run from `main` in the `guards` workflow on every PR (the PR's
files are data); overview and the other guards: `docs/runbooks/ci-guards.md`.

## Step "Skills match manifest and checksums" fails
- `skill folder not in manifest: X` - add `X ours` or `X third-party` to `.claude/skills/manifest.txt`, or remove the folder.
- `manifest lists 'X' but the folder is missing` - remove the line or restore the folder.
- `manifest line for 'X' needs kind 'ours' or 'third-party'` - fix the second word on that line.
- `bad skill name in manifest: 'X'` - names are lowercase letters, digits and dashes.
- `third-party skill 'X' has no NOTICE.md` / `has no row in SKILLS-LOCK.md` - add the notice (source, commit, license) and the row.
- `symlink not allowed`, `special file not allowed`, `empty folder not allowed`, `file name with newline, backslash or control character`
  - replace with plain files with plain names, or delete.
- `unexpected file: .claude/skills/<name>` - only `manifest.txt`, `checksums.sha256` and `SKILLS-LOCK.md` may sit at the top.
- `files added`, `files removed or renamed`, `changed files` - files differ from `checksums.sha256`. Unintended: revert.
  Intended (founder): review the change, then `bash scripts/check-skills.sh --write`.
- `missing .claude/skills/manifest.txt` / `missing .claude/skills/checksums.sha256` - restore the file from `main`.
- `missing .claude/agents` - restore the folder from `main`.
- `<agent>.md: more than one 'skills:' line` - keep exactly one.
- `<agent>.md: 'skills:' must be a one-line comma list` - write it as `skills: a, b` (no YAML list, no brackets, not empty).
- `<agent>.md: skill 'X' is not in the manifest` - fix the spelling or add the skill.
- `<agent>.md: 'X' must be loaded together with 'Y'` - add `Y` to that agent's `skills:` line.
- `skill 'X' requires 'Y', which is not in the manifest` / `unknown option` - fix the manifest line (`<name> <kind> [requires=<skill>]`).
- `skill 'X' has no SKILL.md` / `front matter name is '...'` - each skill folder needs `SKILL.md` starting with `---`, `name: <folder>`.
- `third-party skill 'X' has no license file` - add the upstream license as `UPSTREAM-LICENSE` (plain, .md or .txt; exact
  upper-case name) at the top of the folder, non-empty. Upstream's own `LICENSE`/`LICENSE.md`/`LICENSE.txt` also counts.
- `NOTICE.md for 'X' has no full 40-character commit` / `commit for 'X' differs between SKILLS-LOCK.md and NOTICE.md` - write
  the same full lower-case commit SHA in NOTICE.md and the lock row.
- `SKILLS-LOCK.md row for 'X' must read '| X | owner/repo `path`, ... | <40-hex commit, lower case> | ...'` - fix the row's
  shape (the commit is the third cell). `has no row in SKILLS-LOCK.md` / `has more than one row` - one row per skill, first
  cell exactly the skill name.
- `listed more than once in the manifest` / `empty requires=` / `more than one requires=` / `needs requires=<our override skill>` /
  `must require one of our own (override) skills` / `CRLF` - fix `manifest.txt` (one LF line per skill; every third-party skill has
  exactly one `requires=` naming an `ours` skill).
- `skill 'X' is listed more than once in 'skills:'` - list each skill once on the agent's `skills:` line.
- `missing .claude/skills` - restore the folder from `main`.
- `skill '<x>': SKILL.md has no front matter (--- ... ---)` - start `SKILL.md` with a `---` block holding `name:`.
- `skill '<x>' requires itself` - a `requires=` names another skill (an `ours` override skill), never the skill itself.
- `<agent>.md: has 'skills' but no valid front matter` - put `skills:` inside the agent file's `---` front matter.
- `<agent>.md: write the key exactly as 'skills:' at the start of the line` - no indentation or other spelling.

## Step "Third-party skills compared with the base branch (no quiet switch to 'ours' or to another repo)"
`scripts/check-skills-vs-base.sh` (from `main`) compares the PR's manifest and SKILLS-LOCK.md rows with `main`'s. The log lists
every `CHANGED`, `NEW` and `REMOVED` third-party skill with its repo, path and commit, for the founders to read. Errors:
- `third-party skill 'X' is now listed as 'ours'` - a vendored skill stays third-party. To replace it, remove it and add a new one.
- `changed its source repo (a -> b)` - a different upstream (for example a fork) needs a new skill name.
- `removed from the manifest but its folder is still there` - delete the folder too, or keep the manifest line.

## Step "Third-party skills equal their pinned upstream with deletions only (fresh fetch of the locked commit)"
This step runs `scripts/check-skills-upstream-all.sh`: for each third-party skill it fetches the exact commit from its SKILLS-LOCK.md row and runs
`scripts/check-skill-upstream.sh`. Both read lock rows with `scripts/check-skills-lib.sh`, like `check-skills.sh`: the row whose
first cell is exactly the skill name, shaped `| <name> | <owner>/<repo> `<path>`, ... | <40-hex commit, lower case> |`.
It must print
`OK: .claude/skills/<name> = upstream with deletions only (<n> upstream file(s) removed) + top-level NOTICE.md/UPSTREAM-LICENSE; <name>.diff matches`.
Messages and fixes:
- `lines added or changed in <file>`, `file not in upstream: <file>`, `more than one UPSTREAM-LICENSE file`, `not a regular file or
  folder` - re-copy from upstream and only delete. The only files we may add are top-level `NOTICE.md` and one `UPSTREAM-LICENSE`
  (plain, .md or .txt).
- `lines removed from <file>: only whole-file deletions are allowed outside Markdown files` - delete the whole file or nothing.
- `deletions in <file> are not whole units:`, followed by one `upstream line <n>: removed line is <problem>: <text>` line per
  problem - deletions must be whole units (`scripts/check-skill-deletions.py`): a whole file;
  a heading's whole own body (the heading line up to the next heading of any level); a whole fenced code block (``` or ~~~, any
  length, an unclosed one runs to the end of the file); a whole table (header, separator and rows); or a single body row of a
  table, or a whole list item (marker line plus every deeper-indented line after it, nested items included), with no warning or
  rule word (`WARN_RE` in the script: ❌, ✅, WRONG, never, must, not, should, always, only, important, critical, required,
  access, overrideAccess, auth, secret, token, credential, password, permission, role, admin, tenant, PII, SSN, encrypt,
  sensitive, forbidden, prohibited, cannot, unless, validate, sanitize, escape, inject, limit, ...). A table's header or separator
  row alone, part of a list item (a parent without its nested items, or a nested item alone), partial prose, part of a code block
  (including indented code), a `|` line that is not a row of a real table (one whose second row is a separator) or a heading
  without its body fails. Blank lines can go anywhere. To drop a whole file's text,
  delete the file rather than emptying it.
- `a section, code block or table with a warning or rule word (...) that is not in the reviewed list (add '<file>:<line>' ...)`
  - a whole section, code block or table removed from upstream contains a warning word. A founder reads it and, if removing it
  is safe (for example a list of links), adds `<file>:<upstream line of the heading, opening fence or header row>` with a reason
  after `#` to `.claude/skills-patches/<name>.reviewed`. The guards log prints every such deletion as `REVIEWED <file>:<line> ...`.
- `deleted file <file> needs a review` / `whole file deleted that has a warning or rule word (...)` - a whole upstream Markdown
  file was deleted and it contains a warning word; after a founder review add `<file>:0` to the same `.reviewed` file.
  `stale entry in <name>.reviewed` - an entry no longer matches a deletion; remove it.
- `missing or empty record`, `<name>.diff does not match diff -ru of upstream and our copy`, `<name>.diff has added lines`,
  `records changes but our copy equals upstream` - regenerate the record from a folder holding the upstream copy as `upstream` and
  ours as `ours`:
  `diff -ru -a -x NOTICE.md -x UPSTREAM-LICENSE -x UPSTREAM-LICENSE.md -x UPSTREAM-LICENSE.txt upstream ours > .claude/skills-patches/<name>.diff`
- `diff failed on <file>` / `diff of upstream and ours failed (exit N)` - a file could not be read; fix permissions and re-run.
- `could not fetch <repo> at <commit>` - the repo or commit in the lock row is wrong, or GitHub was down (re-run once).
- `third-party skill '<name>' has no row in SKILLS-LOCK.md` (with `(no SKILLS-LOCK.md file)` when the file is missing),
  `skill '<name>' has more than one row in SKILLS-LOCK.md`, `SKILLS-LOCK.md row for '<name>' must read ...` - fix the lock row
  (the same messages as in `check-skills.sh`, from `lock_row_error` in `scripts/check-skills-lib.sh`).
- `bad skill name`, `upstream dir not found: <dir>`, `no skill folder <dir>` (`check-skill-upstream.sh`); `missing
  <dir>/manifest.txt`, `bad skill name '<x>'` (`check-skills-upstream-all.sh`) - a broken checkout or manifest; fix the name or
  re-run. `cannot read <file> (<reason>)` / `bad removed line number '<x>'` (`check-skill-deletions.py`) - an internal error of
  the deletion check; re-run, then tell a founder.
When every third-party skill passes, the step ends with `Upstream check OK for <n> third-party skill(s)`.
A founder can run it locally: `bash scripts/check-skills-upstream-all.sh .`
