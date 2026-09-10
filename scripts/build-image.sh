#!/usr/bin/env bash

set -e -o pipefail

cd "$(dirname "$0")/.."

IMAGE="ghcr.io/flipstone/purescript-tools"

# package.json is the single place a tool version is written. The PureScript
# version is embedded in every image tag, so it is read from there and also
# handed to the Dockerfile, which refuses to build if the installed compiler
# does not match. No node on the host is assumed, hence sed rather than npm.
set_purs_version() {
  PURS_VERSION=$(sed -n 's/^ *"purescript": *"\([^"]*\)".*/\1/p' package.json)
  if ! [[ "$PURS_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Could not read an exact purescript version from package.json (got '$PURS_VERSION')"
    exit 1
  fi
}

set_tag_variables() {
  set_purs_version
  if [ -n "$(git status --porcelain)" ]; then
    echo "Uncommitted changes found. Images will be tagged with -uncommitted"
    COMMIT_SHA="uncommitted"
  else
    COMMIT_SHA=$(git show-ref --hash=7 --verify HEAD)
  fi

  SHA_TAG="$IMAGE:debian-purescript-$PURS_VERSION-$COMMIT_SHA"
}

# Both architectures are built on one runner via buildx (emulated for the
# non-native one); the toolchain is prebuilt npm packages, so this is cheap
# enough not to need per-arch runners. buildx pushes the manifest list itself.
buildx_build() {
  docker buildx build . \
    --build-arg PURS_VERSION="$PURS_VERSION" \
    --platform linux/amd64,linux/arm64 \
    --tag "$SHA_TAG" \
    --cache-from type=gha,ignore-error=true \
    --cache-to type=gha,mode=max,ignore-error=true \
    --provenance false \
    "$@"
}

COMMAND=$1

case $COMMAND in
  build-local-beta)
    set_purs_version
    echo "Building purescript-tools-beta image"
    docker build . --build-arg PURS_VERSION="$PURS_VERSION" --tag purescript-tools-beta
    ;;

  build-and-push-sha-tag)
    set_tag_variables
    echo "Building and pushing $SHA_TAG"
    buildx_build --push
    ;;

  build-sha-tag)
    set_tag_variables
    echo "Building $SHA_TAG without pushing (verification only)"
    buildx_build
    ;;

  push-release-tag)
    set_tag_variables
    if [ -z "$GITHUB_RUN_NUMBER" ]; then
      echo "GITHUB_RUN_NUMBER must be set (this command is meant to run in CI)"
      exit 1
    fi
    if [ "$COMMIT_SHA" = "uncommitted" ]; then
      echo "Refusing to publish a release tag from a dirty tree"
      exit 1
    fi
    # Release tags are what downstream Dependabot configs watch, so the
    # version must stay within a single dependabot-core tag format class.
    # A bare run number breaks at 1000 (dependabot-core#11198); leading
    # with the 4-digit year avoids that for good. Month and day are
    # unpadded on purpose: Dependabot compares segments numerically.
    #
    # The date is the commit's, not today's: a wall-clock date would let a
    # re-run of an old workflow mint a tag that sorts above newer releases
    # while pointing at an older image. With the commit date, a re-run
    # recreates the identical tag.
    COMMIT_DATE=$(TZ=UTC git show -s --format=%cd --date=format-local:%Y.%-m.%-d HEAD)
    RELEASE_TAG="$IMAGE:debian-purescript-$PURS_VERSION-build-$COMMIT_DATE.$GITHUB_RUN_NUMBER"
    echo "Publishing release tag $RELEASE_TAG (re-tag of $SHA_TAG)"
    docker buildx imagetools create --tag "$RELEASE_TAG" "$SHA_TAG"
    ;;

  scan-local-beta)
    # A local image is handed to trivy as a saved tarball rather than through
    # the docker socket, so the scan works regardless of where the daemon's
    # socket lives (rootless docker and Docker Desktop put it elsewhere).
    mkdir -p trivy-reports
    docker save purescript-tools-beta -o trivy-reports/purescript-tools-beta.tar
    docker compose run --rm -v "$PWD/trivy-reports:/reports" trivy \
      image --input /reports/purescript-tools-beta.tar | tee trivy-reports/purescript-tools-beta.txt
    rm -f trivy-reports/purescript-tools-beta.tar
    ;;

  scan-sha-tag)
    set_tag_variables
    echo "$SHA_TAG must be pushed to GitHub Container Registry BEFORE running this step."
    # The sha tag is a multi-arch manifest list; scan the amd64 image (the
    # arm64 contents match closely enough that scanning it too adds no signal).
    mkdir -p trivy-reports
    TRIVY_PLATFORM=linux/amd64 docker compose run --rm trivy image "$SHA_TAG" | tee trivy-reports/amd64.txt
    ;;

  *)
    echo "usage: ./scripts/build-image.sh build-local-beta|build-sha-tag|build-and-push-sha-tag|push-release-tag|scan-local-beta|scan-sha-tag"
    exit 1
esac;
