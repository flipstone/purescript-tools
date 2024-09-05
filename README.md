# Purescript Tools

This repository has a workflow defined that will build and push amd64 and arm64
images to Github Container Registry.

# How to build and test locally

* Run `docker build -t purescript-tools:beta .` to create a local image with the tag of beta
* Use `'purescript-tools:beta` in an app that uses purescript-tools to try it out.
