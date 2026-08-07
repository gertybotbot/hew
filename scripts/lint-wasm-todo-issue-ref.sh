#!/usr/bin/env bash
# lint-wasm-todo-issue-ref.sh
#
# Reject WASM-TODO markers that do not carry an issue reference.
# Every actionable WASM-TODO in source code must use the form:
#   WASM-TODO(#NNN): <description>
#
# Rationale: bare WASM-TODO comments with no issue reference cannot be
# tracked or prioritised.
#
# Checking the FORM of the reference is not sufficient. A marker pointing at a
# closed issue -- or at a merged PR number, which is not a tracking artifact at
# all -- satisfies the syntax while tracking nothing, which is the very defect
# the marker convention exists to prevent (issue #2827). So this script runs a
# second pass: every cited ref must appear as an `open` row in
# scripts/wasm-todo-tracking-refs.tsv. That registry is checked in, so the
# semantic check needs no network access and behaves identically offline and in
# CI. It cannot go stale silently: an unknown ref fails closed rather than
# passing.
#
# Excluded paths (category labels, not actionable TODO markers):
#   - docs/                         — uses WASM-TODO as a table column label
#   - .tmp/                         — local planning/orchestration prose quotes audits and examples
#   - CONTRIBUTING.md               — documents the marker convention itself
#   - .github/                      — PR template references the form by example
#   - Makefile                      — contains DROP-TODO|WASM-TODO grep pattern literal
#   - wasm-capability-manifest.toml — uses WASM-TODO as tracking_label data values
#   - hew-capability-gen/src/       — struct/field docs reference "WASM-TODO backlog" by name
#   - hew-capability-gen/tests/     — test string literals match markdown headings
#   - this script itself
set -Eeuo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# Match any WASM-TODO that is NOT immediately followed by an open paren
# containing a hash-prefixed issue number.
# Positive reference form: WASM-TODO(#NNN):
# Rejected forms: WASM-TODO:, WASM-TODO backlog, WASM-TODO (anything without #NNN)
bad=$(git grep -nE 'WASM-TODO([^(]|\([^#]|\(#[^0-9])' -- \
    ':!scripts/lint-wasm-todo-issue-ref.sh' \
    ':!docs/' \
    ':!.tmp/' \
    ':!CONTRIBUTING.md' \
    ':!.github/' \
    ':!Makefile' \
    ':!wasm-capability-manifest.toml' \
    ':!hew-capability-gen/src/' \
    ':!hew-capability-gen/tests/' \
    2>/dev/null || true)

if [[ -n "$bad" ]]; then
    echo "lint-wasm-todo: found WASM-TODO comments without issue reference:" >&2
    echo "$bad" >&2
    echo "" >&2
    echo "Use the form: WASM-TODO(#NNN): <description>" >&2
    echo "The issue cited must be OPEN and listed in" >&2
    echo "scripts/wasm-todo-tracking-refs.tsv. Do not cite a closed umbrella" >&2
    echo "issue or a PR number -- see https://github.com/hew-lang/hew/issues/2827" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Second pass: the cited ref must actually track something.
# ---------------------------------------------------------------------------

REGISTRY="scripts/wasm-todo-tracking-refs.tsv"

if [[ ! -f "$REGISTRY" ]]; then
    echo "lint-wasm-todo: missing registry $REGISTRY" >&2
    echo "The semantic check cannot run without it. Refusing to report ok." >&2
    exit 1
fi

# Refs recorded as open are the only ones a marker may cite.
open_refs=$(awk -F'\t' '!/^[[:space:]]*#/ && NF >= 2 && $2 == "open" { print $1 }' "$REGISTRY")

# Every ref cited by a marker in tracked source, with its locations.
cited=$(git grep -hoE 'WASM-TODO\(#[0-9]+\)' -- \
    ':!scripts/lint-wasm-todo-issue-ref.sh' \
    ':!scripts/wasm-todo-tracking-refs.tsv' \
    ':!docs/' \
    ':!.tmp/' \
    ':!CONTRIBUTING.md' \
    ':!.github/' \
    ':!Makefile' \
    ':!wasm-capability-manifest.toml' \
    ':!hew-capability-gen/src/' \
    ':!hew-capability-gen/tests/' \
    2>/dev/null | grep -oE '[0-9]+' | sort -un || true)

stale=""
for ref in $cited; do
    if ! grep -qx -- "$ref" <<<"$open_refs"; then
        reason=$(awk -F'\t' -v r="$ref" \
            '!/^[[:space:]]*#/ && $1 == r { print $2": "$4; found=1 }
             END { if (!found) print "not listed in the registry" }' "$REGISTRY")
        count=$(git grep -cE "WASM-TODO\(#${ref}\)" -- \
            ':!scripts/lint-wasm-todo-issue-ref.sh' \
            ':!scripts/wasm-todo-tracking-refs.tsv' \
            2>/dev/null | awk -F: '{ n += $NF } END { print n+0 }')
        stale+="  #${ref}  (${count} marker(s))  ${reason}"$'\n'
    fi
done

if [[ -n "$stale" ]]; then
    echo "lint-wasm-todo: WASM-TODO markers cite refs that track nothing:" >&2
    echo "" >&2
    printf '%s' "$stale" >&2
    echo "" >&2
    echo "A marker must cite an OPEN issue describing the specific deferral." >&2
    echo "Closed umbrella issues and PR numbers do not track anything." >&2
    echo "Registry: $REGISTRY   Context: https://github.com/hew-lang/hew/issues/2827" >&2
    exit 1
fi

echo "lint-wasm-todo: ok" >&2
