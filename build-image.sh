#!/usr/bin/env bash

set -e

GIT_CHANGES=$(git status --porcelain | wc -l 2>/dev/null)

case "$GIT_CHANGES" in
  0)
    COMMIT_SHA=$(git show-ref --hash=7 --verify HEAD)
    ;;
  *)
    echo "Uncommitted changes found. Images will be tagged with -uncommitted"
    COMMIT_SHA="uncommitted"
    ;;
esac


RELEASE_DATE=$(date '+%Y-%m-%d')
TAG_ROOT="ghcr.io/flipstone/purescript-tools:debian-bookworm-purescript-0.15.10-$RELEASE_DATE-$COMMIT_SHA"
ARM_TAG="$TAG_ROOT"-arm64
AMD_TAG="$TAG_ROOT"-amd64
ARCH=$(uname -m)

case "$ARCH" in
  x86_64)
    ARCH_TAG="$AMD_TAG"
    ;;
  aarch64)
    ARCH_TAG="$ARM_TAG"
    ;;
  arm64)
    ARCH_TAG="$ARM_TAG"
    ;;
  *)
    echo "Unrecognized architecture: $ARCH"
    exit 1
    ;;
esac

COMMAND=$1

case $COMMAND in
  build-and-push-arch-tag)
    echo "Building $ARCH_TAG"
    docker buildx build . \
      --tag $ARCH_TAG \
      --cache-from type=gha,mode=max,ignore-error=true \
      --cache-to type=gha,mode=max,ignore-error=true \
      --push
    ;;

  push-manifest)
    echo "Both $AMD_TAG and $ARM_TAG must be pushed to Github Container Registry BEFORE running this step."
    docker buildx imagetools create --tag $TAG_ROOT $AMD_TAG $ARM_TAG
    ;;
  *)
    echo "usage: ./build-image.sh build-arch-tag|push-arch-tag|push-manifest"
    exit 1
esac;
