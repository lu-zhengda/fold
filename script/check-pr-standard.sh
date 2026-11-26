#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "usage: check-pr-standard.sh  # expects PR_TITLE and PR_BODY in the environment" >&2
    exit 2
}

[[ -n "${PR_TITLE:-}" && -n "${PR_BODY:-}" ]] || usage

title_re='^(build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test)(\([[:alnum:]._-]+\))?: .+'
if [[ ! "$PR_TITLE" =~ $title_re ]]; then
    echo "PR title must match type(scope): subject (conventional commit types)." >&2
    echo "  got: $PR_TITLE" >&2
    exit 1
fi

body_line_count=$(printf '%s\n' "$PR_BODY" | wc -l | tr -d ' ')
if [[ "$body_line_count" -gt 40 ]]; then
    echo "PR body must be at most 40 lines (got $body_line_count)." >&2
    exit 1
fi

for section in Why What\ changed Blast\ Radius Verification; do
    if ! printf '%s\n' "$PR_BODY" | grep -qi "^##[[:space:]]*${section}[[:space:]]*$"; then
        echo "PR body must include a ## $section section." >&2
        exit 1
    fi
done

if ! printf '%s\n' "$PR_BODY" | grep -qE '^Fixes[[:space:]]+ZHE-[0-9]+[[:space:]]*$'; then
    echo "PR body must include a Fixes ZHE-<n> line." >&2
    exit 1
fi

echo "PR title and body meet the repository standard."