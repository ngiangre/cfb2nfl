#!/usr/bin/env sh
# PostToolUse hook: after an Edit/Write to a figure card, run the mechanical
# card checker (R/card_style.R, decision 0054) and remind the agent to run the
# vignette-reviewer subagent before the PR. Exit 2 sends stderr back to the
# agent. Any other file, or a machine without Rscript/jq, passes silently.
# (The file keeps its post-era name because .claude/settings.json points here.)

command -v jq >/dev/null 2>&1 || exit 0
command -v Rscript >/dev/null 2>&1 || exit 0

file=$(jq -r '.tool_input.file_path // empty')
case "$file" in
  */vignettes/card-*.qmd) ;;
  *) exit 0 ;;
esac

# Check the repository the card lives in (a worktree has its own registries
# and thumbnails), falling back to the project directory.
root=$(git -C "$(dirname "$file")" rev-parse --show-toplevel 2>/dev/null)
[ -n "$root" ] || root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
out=$(cd "$root" && Rscript -e '
  for (f in c("R/format.R", "R/card.R", "R/card_style.R")) source(f)
  bad <- check_card_style(commandArgs(TRUE)[1], root = ".")
  if (nrow(bad)) {
    cat(sprintf("%s:%s [%s/%s] %s\n", bad$file, bad$line, bad$rule, bad$severity, bad$message), sep = "")
  }
' "$file" 2>&1)

{
  if [ -n "$out" ]; then
    echo "Card style violations (R/card_style.R):"
    echo "$out"
  fi
  echo "Before opening the PR for this card, run the vignette-reviewer agent on $file and address its findings (AGENTS.md \"Figure cards\")."
} >&2
exit 2
