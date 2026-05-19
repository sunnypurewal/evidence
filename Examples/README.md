# Evidence Action Examples

This folder ships ready-to-copy GitHub Actions workflows that exercise the
[evidence GitHub Action](../action.yml) end-to-end.

## Workflows

- [`workflows/capture-evidence-on-pr.yml`](workflows/capture-evidence-on-pr.yml) —
  runs `evidence capture-evidence` on every pull request and posts a PR
  comment with the captured screenshot. Drop into
  `.github/workflows/capture-evidence.yml` in your iOS app repo.
- [`workflows/capture-pr-on-pr.yml`](workflows/capture-pr-on-pr.yml) —
  runs `evidence capture-pr` on every pull request, posts a concise report
  comment with the before/after SHAs and status, and uploads the generated
  evidence bundle. Drop into `.github/workflows/capture-pr-on-pr.yml` in your
  iOS app repo.
- [`workflows/capture-screenshots-on-tag.yml`](workflows/capture-screenshots-on-tag.yml) —
  runs `evidence capture-screenshots` against the configured device matrix
  whenever a release tag is pushed, then uploads the screenshots as a build
  artifact ready for App Store Connect.
- [`workflows/capture-web-on-pr.yml`](workflows/capture-web-on-pr.yml) —
  starts a local web server, runs `evidence capture-web` on every pull request,
  and posts the captured viewport screenshots as a PR comment.

## PR evidence plan

[`pr-change-evidence-plan.json`](pr-change-evidence-plan.json) is a generic
`capture-pr` plan fixture. Copy it into an app repository, replace the sample
repo, PR number, scheme, bundle ID, project/workspace, simulator, and URL
values, then point the workflow `plan:` input at that app-owned copy.
The sample uses the launch-only `simctl` runner so it avoids app-specific XCTest
targets; richer taps, typing, swipes, or accessibility waits require an
app-side XCTest Evidence harness.

## Marketplace listing

The Action is published to the GitHub Marketplace as
[`RiddimSoftware/evidence`](https://github.com/marketplace/actions/evidence).
Pin to a major version (`@v0`) for stability or to a SHA for reproducibility.
