#!/usr/bin/env bash
# Prepare pspdev after clone or pull.
#
# This follows the exact submodule gitlinks recorded by the parent repository.
# It intentionally does NOT use `git submodule update --remote`, so running it
# never advances component versions or dirties the parent repository.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
JOBS="${GITPREP_JOBS:-8}"

cd "${ROOT}"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "ERROR: ${ROOT} is not a Git working tree." >&2
    exit 1
fi

TOPLEVEL="$(git rev-parse --show-toplevel)"
if [[ "${TOPLEVEL}" != "${ROOT}" ]]; then
    echo "ERROR: gitprep.sh must be run from the repository root." >&2
    echo "  repository: ${TOPLEVEL}" >&2
    echo "  script:     ${ROOT}" >&2
    exit 1
fi

if [[ ! -f .gitmodules ]]; then
    echo "No .gitmodules file; nothing to prepare."
    exit 0
fi

# Protect intentional, not-yet-committed gitlink changes. A submodule checked
# out at a different commit appears as a parent-repository change even when
# the submodule's own working tree is clean.
if ! git diff --quiet --ignore-submodules=none -- components 2>/dev/null; then
    echo "ERROR: unstaged component/gitlink changes are present." >&2
    echo "Commit, stage, or explicitly discard them before running gitprep.sh." >&2
    exit 1
fi

if ! git diff --cached --quiet --ignore-submodules=none -- components 2>/dev/null; then
    echo "ERROR: staged component/gitlink changes are present." >&2
    echo "Commit or unstage them before running gitprep.sh." >&2
    exit 1
fi

# Protect actual edits inside already-initialized submodules.
if ! git submodule foreach --quiet --recursive \
    'git diff --quiet && git diff --cached --quiet'
then
    echo "ERROR: a submodule contains uncommitted file changes." >&2
    echo "Commit, stash, or discard those changes before running gitprep.sh." >&2
    exit 1
fi

echo "Synchronizing submodule URLs..."
git submodule sync --recursive

echo "Initializing/updating recorded submodule revisions..."
git -c remote.origin.tagOpt=--no-tags submodule update \
    --init \
    --recursive \
    --depth 1 \
    --jobs "${JOBS}"

# Keep all initialized nested components from auto-following remote tags.
git submodule foreach --quiet --recursive \
    'git config remote.origin.tagOpt --no-tags'

echo "Verifying submodule state..."
bad=0
while IFS= read -r line; do
    [[ -z "${line}" ]] && continue

    case "${line:0:1}" in
        " ")
            ;;
        "-")
            echo "ERROR: uninitialized submodule: ${line}" >&2
            bad=1
            ;;
        "+")
            echo "ERROR: submodule is not at its recorded gitlink: ${line}" >&2
            bad=1
            ;;
        "U")
            echo "ERROR: submodule has unresolved conflicts: ${line}" >&2
            bad=1
            ;;
        *)
            echo "ERROR: unexpected submodule state: ${line}" >&2
            bad=1
            ;;
    esac
done < <(git submodule status --recursive)

(( bad == 0 )) || exit 1

# Catch the dangerous case where `git -C components/foo ...` would silently
# walk upward into the parent repository because foo was never initialized.
while read -r _ path; do
    [[ -z "${path}" ]] && continue

    component_root="$(git -C "${path}" rev-parse --show-toplevel 2>/dev/null || true)"
    expected_root="${ROOT}/${path}"

    if [[ "${component_root}" != "${expected_root}" ]]; then
        echo "ERROR: ${path} is not an initialized submodule working tree." >&2
        echo "  resolved Git root: ${component_root:-<none>}" >&2
        exit 1
    fi
done < <(git config -f .gitmodules --get-regexp '^submodule\..*\.path$' || true)

echo "Repository prepared successfully."
