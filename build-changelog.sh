#!/bin/bash

set -e

OWNER="${GITHUB_REPOSITORY_OWNER:-StochasticEagle}"

REPOS=(
    pspdev
    pspsdk
    psp-toolchain
    psp-toolchain-allegrex
    psp-packages
    psp-linkusb
    psp-pacman
    psp-ebootsigner
)

OUTPUT_FILE="$(mktemp)"
trap 'rm -f "${OUTPUT_FILE}"' EXIT

# Get the timestamp and name of the latest release of pspdev/pspdev
LAST_RELEASE="$(
curl -sfL
-H "Accept: application/vnd.github+json"
-H "X-GitHub-Api-Version: 2022-11-28"
"https://api.github.com/repos/${OWNER}/pspdev/releases/latest"
)"

LAST_RELEASE_DATE="$(jq -r '.published_at' <<< "${LAST_RELEASE}")"
LAST_RELEASE_NAME="$(jq -r '.name' <<< "${LAST_RELEASE}")"

echo "## Pull Requests Included" > "${OUTPUT_FILE}"
echo "" >> "${OUTPUT_FILE}"
echo "Below are the pull requests that were merged since the ${LAST_RELEASE_NAME} release." >> "${OUTPUT_FILE}"

for REPO in "${REPOS[@]}"; do
TMP_FILE="$(mktemp)"
echo '[]' > "${TMP_FILE}"

PAGE=1

while true; do
    PRS="$(
        curl -sfL \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "https://api.github.com/repos/${OWNER}/${REPO}/pulls?state=closed&per_page=100&page=${PAGE}"
    )"

    if [ "$(jq 'length' <<< "${PRS}")" -eq 0 ]; then
        break
    fi

    jq \
        --arg release_date "${LAST_RELEASE_DATE}" \
        '
        [
            .[]
            | select(
                (.merged_at != null) and
                (.merged_at >= $release_date)
            )
            | {
                merged_at,
                title,
                user: .user.login,
                pr_url: .html_url
            }
        ]
        ' <<< "${PRS}" |
    jq -s 'add' "${TMP_FILE}" - > "${TMP_FILE}.new"

    mv "${TMP_FILE}.new" "${TMP_FILE}"
    PAGE=$((PAGE + 1))
done

if [ "$(jq 'length' "${TMP_FILE}")" -gt 0 ]; then
    echo "" >> "${OUTPUT_FILE}"
    echo "### ${REPO}" >> "${OUTPUT_FILE}"
    echo "" >> "${OUTPUT_FILE}"

    jq -r \
        'sort_by(.merged_at)[] | "[\(.title)](\(.pr_url)) by @\(.user)"' \
        "${TMP_FILE}" >> "${OUTPUT_FILE}"
fi

rm -f "${TMP_FILE}"

done

cat "${OUTPUT_FILE}"
