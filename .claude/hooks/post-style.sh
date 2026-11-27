#!/usr/bin/env sh
# PostToolUse hook: after an Edit/Write to a dated blog post or a figure card,
# run its mechanical style checker (R/post_style.R, R/card_style.R) and remind
# the agent to run the vignette-reviewer subagent before the PR. Exit 2 sends
# stderr back to the agent. Any other file, or a machine without Rscript/jq,
# passes silently.

command -v jq >/dev/null 2>&1 || exit 0
command -v Rscript >/dev/null 2>&1 || exit 0

file=$(jq -r '.tool_input.file_path // empty')
case "$file" in
  */vignettes/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*.qmd) kind=post ;;
  */vignettes/card-*.qmd) kind=card ;;
  *) exit 0 ;;
esac

root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
if [ "$kind" = post ]; then
  out=$(cd "$root" && Rscript -e '
    source("R/post_style.R")
    bad <- check_post_style(commandArgs(TRUE)[1])
    if (nrow(bad)) {
      cat(sprintf("%s:%s [%s] %s\n", bad$file, bad$line, bad$rule, bad$message), sep = "")
    }
  ' "$file" 2>&1)
  label="Post style violations (R/post_style.R):"
  review="Before opening the PR for this post, run the vignette-reviewer agent on $file and address its findings (AGENTS.md \"Blog posts\")."
else
  out=$(cd "$root" && Rscript -e '
    for (f in c("R/format.R", "R/card.R", "R/card_style.R")) source(f)
    bad <- check_card_style(commandArgs(TRUE)[1], root = ".")
    if (nrow(bad)) {
      cat(sprintf("%s:%s [%s/%s] %s\n", bad$file, bad$line, bad$rule, bad$severity, bad$message), sep = "")
    }
  ' "$file" 2>&1)
  label="Card style violations (R/card_style.R):"
  review="Before opening the PR for this card, run the vignette-reviewer agent on $file in card mode and address its findings."
fi

{
  if [ -n "$out" ]; then
    echo "$label"
    echo "$out"
  fi
  echo "$review"
} >&2
exit 2
