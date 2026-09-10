# Purescript Tools

This repository has a workflow defined that will build and push amd64 and arm64
images to GitHub Container Registry.

Repository layout:

- `Dockerfile` — the tooling image definition
- `package.json` and `package-lock.json` — the toolchain baked into the image
  (npm itself, spago, purescript, purescript-psa, grunt-cli, esbuild,
  purs-tidy); `package.json` is the single source of truth for every tool
  version
- `scripts/` — scripts run on the host (`build-image.sh`)
- `compose.yaml` — containerized dev tooling (trivy, hadolint), so nothing
  needs to be installed on the host

# Getting started

Building the image locally requires a one-time `docker login dhi.io` (your
Docker Hub credentials work). The base image is Docker Hardened Images' `node`
(free Community tier), which requires authentication to pull. It is pinned to
an exact node version and digest, and dependabot bumps both together.

# How to build this using docker to test locally

Run `./scripts/build-image.sh build-local-beta` to build a local image tagged as
`purescript-tools-beta`. You can then use that image locally to test on other
repos before building an official image.

# How tool versions are managed

Every tool version lives in `package.json`, as an exact pin, and nowhere else.
The image installs that manifest with `npm ci` and puts its `node_modules/.bin`
first on `PATH`, so the pinned `npm` shadows the one bundled with node.

To change a version, edit `package.json` and regenerate the lockfile inside the
base image (no node is needed on the host; the image reference is read from the
Dockerfile so it is never out of step with the build):

```
docker run --rm -v "$PWD":/w -w /w -e HOME=/tmp \
  "$(sed -n 's/^FROM \(.*\)@sha256.*/\1/p' Dockerfile)" \
  npm install --package-lock-only --ignore-scripts
```

`--package-lock-only` matters: a lockfile written without a `node_modules` tree
records every platform's optional packages (esbuild's per-arch binaries), which
the arm64 build needs.

`package.json` also carries an `overrides` block. That is not a tool version:
it forces a floor on a transitive dependency whose vulnerable release a tool
still asks for (currently `tar`, which the `purescript` package's installer
uses only to unpack the compiler at install time). Overrides are not bumped
by Dependabot, so revisit the block when a Trivy scan stops listing the
package it works around, or when the tool that needed it is upgraded.

The PureScript version is also embedded in every image tag.
`scripts/build-image.sh` reads it from `package.json` and passes it to the
build, where the Dockerfile refuses to build if `purs --version` disagrees, so
the tag can never drift from what is actually installed.

# How to scan images for vulnerabilities

Run `./scripts/build-image.sh scan-local-beta` to scan a locally built beta
image with [Trivy](https://trivy.dev), or `docker compose run --rm trivy image
IMAGE` to scan any other image reference. Trivy runs from its official Docker
image via the `trivy` service in `compose.yaml`, so no host install is
required.

Scan behaviour is controlled with environment variables, with defaults set in
`compose.yaml`: `TRIVY_SEVERITY` (default `HIGH,CRITICAL`), `TRIVY_EXIT_CODE`
(default `0`, report only; `1` fails on findings), and `TRIVY_IGNORE_UNFIXED`
(default `true`, so reports only contain findings that have a released fix
and are therefore actionable; set to `false` to see everything).

The `scan-local-beta` and `scan-sha-tag` commands also write each report to
the (gitignored) `trivy-reports/` directory.

The CI workflow runs the same scan against the amd64 image after it is pushed.
The results appear in the job summary on the workflow run page and are
uploaded as a downloadable `trivy-reports` artifact. The scan is report-only;
set `TRIVY_EXIT_CODE: '1'` on the workflow's scan step to make HIGH/CRITICAL
findings block the release tag.

# How to lint this repository

CI lints the Dockerfile on every push. To run the same check locally:

```
docker compose run --rm hadolint hadolint Dockerfile
```

Hadolint configuration (ignored rules) lives in `.hadolint.yaml`.

# Dependabot

Dependabot bumps the base image (node version and digest), the toolchain in
`package.json`, the tooling images in `compose.yaml`, and the GitHub Actions
versions weekly, each after a cooldown (7 days for a major, 14 for a minor or
patch). Toolchain minor and patch bumps arrive as one grouped PR; a major
arrives on its own. CI runs on Dependabot branches verify that the image still
builds but publish nothing: the image push, scan, and release steps are
skipped.

Workflows triggered by Dependabot read secrets from the separate Dependabot
secrets store (repo or organization Settings > Secrets and variables >
Dependabot), so `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` must be configured
there as well as in Actions secrets — otherwise the Docker Hub and dhi.io
logins fail on every Dependabot PR. The same two secrets also let Dependabot
authenticate to dhi.io for base image updates (see `.github/dependabot.yaml`).

A purescript bump changes the published tag prefix (see below), so after
merging one, each downstream repository needs a one-time manual repin.

# Image tags and releases

Once you push to GitHub (either on a branch or main), the GitHub workflow
will build a multi-architecture version of the image and publish it to the
GitHub Container Registry.

The registry holds two kinds of tags:

- `debian-purescript-X.Y.Z-<sha7>` — per-commit tags, published for every
  push on every branch. Use these to try out a not-yet-merged image.
- `debian-purescript-X.Y.Z-build-YYYY.M.D.N` — release tags, minted
  automatically from main whenever a push changed the image or how it is built
  (`Dockerfile`, `package.json`, `package-lock.json`, `.npmrc`, or
  `scripts/build-image.sh`). Docs- and CI-only merges don't mint one. These
  are the tags downstream repositories should pin. The date is the commit date
  and `N` is the workflow run number; month and day are unpadded (`2026.9.10`,
  not `2026.09.10`) because Dependabot compares version segments numerically.

A release tag is a digest-identical re-tag of the same commit's sha tag,
created after the Trivy scan (so a blocking scan configuration also blocks
releases). The tag is derived from the commit date and run number, so
re-running a main workflow recreates the same tag rather than minting a new
one.

To try a candidate image downstream before merging: push your purescript-tools
branch, pin the resulting `debian-purescript-X.Y.Z-<sha7>` tag on a branch of
the downstream repository, and iterate. Once your change merges here,
Dependabot opens the release-tag bump PR in each downstream repository that
tracks its compose file — discard the sha-tag test pin rather than merging it.

# For Flipstone Developers

Repositories that use this image should pin a release tag
(`debian-purescript-X.Y.Z-build-YYYY.M.D.N`) and carry a
`.github/dependabot.yaml` with a `docker-compose` (or `docker`) entry so new
releases arrive as bump PRs automatically. Dependabot only proposes updates
within the currently pinned PureScript version: that version sits in the part
of the tag Dependabot treats as an opaque prefix, so a PureScript upgrade is a
deliberate, one-time manual pin edit in each downstream repository, made
alongside the code changes the upgrade requires anyway.
