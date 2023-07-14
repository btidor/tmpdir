#!/bin/bash

set -eufx -o pipefail

# Find the latest (annotated) tag and check that it's well-formed.
RELEASE_TAG=$(git describe --abbrev=0)
if [[ ! "$(git show $RELEASE_TAG)" =~ "tmpdir@$RELEASE_TAG" ]]; then
    echo "error: tag is missing repository and version"
    exit 1
fi

curl https://github.com/btidor.gpg | gpg --import
git verify-tag "$RELEASE_TAG"

# Query Cirrus CI to find the build that was triggered by this tag being
# created. Note that the build triggered by the corresponding commit will *not*
# work since those artifacts don't contain the correct version number.
BUILD_QUERY='
query ($platform: String!, $owner: String!, $repo: String!, $tag: String!) {
  ownerRepository(platform: $platform, owner: $owner, name: $repo) {
    builds(branch: $tag) {
      edges {
         node {
          id,
          tag,
          senderUserPermissions,
          status
        }
      }
    }
  }
}'

RESPONSE=$(curl https://api.cirrus-ci.com/graphql --data @- <<EOF
{
    "query": "$BUILD_QUERY",
    "variables": {
        "platform": "github",
        "owner": "btidor",
        "repo": "tmpdir",
        "tag": "$RELEASE_TAG"
    }
}
EOF
)

EDGES="$(echo "$RESPONSE" | jq -e '.data.ownerRepository.builds.edges')"
if [ "$(echo "$EDGES" | jq -e '.|length')" != "1" ]; then
    echo "error: multiple builds found for $CURRENT_TAG"
    exit 1
fi

BUILD="$(echo "$EDGES" | jq -e '.[0].node')"
echo "BBB"
if [ "$(echo "$NODE" | jq -e '.tag')" != "$CURRENT_TAG" ]; then
    echo "error: tag did not match $CURRENT_TAG"
    exit 1
fi
echo "CCC"

if [ "$(echo "$NODE" | jq -e '.senderUserPermissions')" != "admin" ]; then
    echo "error: build not initiated by an admin"
    exit 1
fi
echo "DDD"

if [ "$(echo "$NODE" | jq -e '.status')" != "COMPLETED" ]; then
    echo "error: build not in COMPLETED"
    exit 1
fi
echo "EEE"

gh release create "$RELEASE_TAG" --draft --generate-notes --verify-tag

curl --output wheels.zip https://api.cirrus-ci.com/v1/artifact/build/6420014010466304/wheels.zip
unzip wheels.zip
cd wheelhouse
for file in "*"; do
    gh api --method POST \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -f "\@$file" \
        "/repos/btidor/tmpdir/releases/$RELEASE_TAG/assets?name=$file"
done
