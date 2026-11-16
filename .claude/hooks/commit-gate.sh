#!/bin/bash
# PreToolUse(Bash) hook: blocks `git commit` when Swift in Packages/ or App/ changed after the
# last full Tools/test.sh run, or when that run is not green. Docs-only and Probes/-only commits
# pass untouched.
#
# Reads Temp/last-run.txt, written only by a full run of Tools/test.sh (no arguments).
#
# Bypass, only with Jorge's OK: `SKIP_TEST_GATE=1 git commit ...`
set -u

input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<< "$input")
case "$cmd" in *"git commit"*) ;; *) exit 0 ;; esac
case "$cmd" in *SKIP_TEST_GATE=1*) exit 0 ;; esac

# Check the repository the commit runs in, not the project root: in a worktree
# (.claude/worktrees/fase-N) the commit, its Swift and its Temp/last-run.txt live there.
cwd=$(jq -r '.cwd // empty' <<< "$input")
cd "${cwd:-${CLAUDE_PROJECT_DIR:-.}}" 2>/dev/null || cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
top=$(git rev-parse --show-toplevel 2>/dev/null) && cd "$top"
results="Temp/last-run.txt"

block() {
  {
    echo "commit-gate: $1"
    echo "Run the full suite first: Tools/test.sh (no arguments), or launch tf-qa; then commit."
    echo "Skip only if Jorge agrees: SKIP_TEST_GATE=1 git commit ..."
  } >&2
  exit 2
}

# Swift under Packages/ or App/ that the working tree has changed: staged, modified, untracked.
swift=$( { git diff --cached --name-only --diff-filter=ACMR
           git diff --name-only --diff-filter=ACMR
           git ls-files --others --exclude-standard; } | grep -E '^(Packages|App)/.*\.swift$' | sort -u )
[ -z "$swift" ] && exit 0

newest=0
newest_file=""
while IFS= read -r f; do
  [ -f "$f" ] || continue
  m=$(stat -f %m "$f")
  if [ "$m" -gt "$newest" ]; then newest=$m; newest_file=$f; fi
done <<< "$swift"

[ -f "$results" ] || block "no full test run yet ($results)."

first=$(head -n 1 "$results")
case "$first" in
  "DONE Passed"*) ;;
  RUNNING*) block "a test run is still in progress ($first)." ;;
  *) block "the last full test run is not green: $first" ;;
esac

[ "$(stat -f %m "$results")" -ge "$newest" ] || block "$newest_file changed after the last full test run."
exit 0
