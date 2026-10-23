#!/usr/bin/env bash
# A compiler still being built is a dependency to wait for, not a build error.
set -euo pipefail

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
: "${GH_TOKEN:?GH_TOKEN is required}"

expected="$(git rev-parse HEAD:components/psp-toolchain)"
[[ "$expected" =~ ^[0-9a-f]{40}$ ]] || {
    echo "::error::The pinned PSP toolchain commit is invalid: $expected"
    exit 1
}
workflow='repos/StochasticEagle/psp-toolchain/actions/workflows/gcc16-artifact.yml/runs?branch=gcc-16.2&per_page=100'
artifact='gcc16-toolchain-ubuntu-x86_64'
max_attempts="${GCC16_ARTIFACT_WAIT_ATTEMPTS:-120}"
interval="${GCC16_ARTIFACT_POLL_SECONDS:-60}"

for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    runs="$(gh api "$workflow")"
    record="$(jq -c --arg sha "$expected" \
      '[.workflow_runs[] | select(.head_sha == $sha)] | sort_by(.created_at, .run_attempt) | last // empty' \
      <<< "$runs")"

    if [[ -z "$record" ]]; then
        echo "::error::No GCC 16.2 source-build run exists for pinned toolchain commit $expected"
        exit 1
    fi

    run_id="$(jq -r '.id' <<< "$record")"
    status="$(jq -r '.status' <<< "$record")"
    conclusion="$(jq -r '.conclusion // ""' <<< "$record")"

    if [[ "$status" == "completed" && "$conclusion" != "success" ]]; then
        echo "::error::Pinned GCC 16.2 compiler run $run_id completed: $conclusion"
        echo "::error::https://github.com/StochasticEagle/psp-toolchain/actions/runs/$run_id"
        exit 1
    fi

    if [[ "$status" == "completed" && "$conclusion" == "success" ]]; then
        listing="$(gh api "repos/StochasticEagle/psp-toolchain/actions/runs/$run_id/artifacts?per_page=100")"
        if jq -e --arg name "$artifact" \
          '[.artifacts[] | select(.name == $name and .expired == false)] | length > 0' \
          <<< "$listing" >/dev/null; then
            printf 'run_id=%s\nsha=%s\n' "$run_id" "$expected" >> "$GITHUB_OUTPUT"
            echo "Validated GCC 16.2 compiler artifact: $run_id ($expected)"
            exit 0
        fi
        echo "Successful compiler run $run_id is still publishing its artifact."
    else
        echo "Waiting for pinned GCC 16.2 source build $run_id: $status (poll $attempt/$max_attempts)"
    fi
    if (( attempt < max_attempts )); then sleep "$interval"; fi
done
echo "::error::Timed out waiting for pinned GCC 16.2 compiler artifact $expected"
exit 1
