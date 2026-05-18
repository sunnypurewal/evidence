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

## Fixture project

The `fixture-project/` directory ships a minimal `.evidence.toml` against
which the Action's self-test workflow validates `actionlint`, the `--help`
surface of the CLI, and the input wiring. It is not a full Xcode project —
real CI users supply their own app.

## Marketplace listing

The Action is published to the GitHub Marketplace as
[`RiddimSoftware/evidence`](https://github.com/marketplace/actions/evidence).
Pin to a major version (`@v0`) for stability or to a SHA for reproducibility.
