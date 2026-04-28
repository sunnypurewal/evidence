# Evidence Action Examples

This folder ships ready-to-copy GitHub Actions workflows that exercise the
[evidence GitHub Action](../action.yml) end-to-end.

## Workflows

- [`workflows/capture-evidence-on-pr.yml`](workflows/capture-evidence-on-pr.yml) —
  runs `evidence capture-evidence` on every pull request and posts a PR
  comment with the captured screenshot. Drop into
  `.github/workflows/capture-evidence.yml` in your iOS app repo.
- [`workflows/capture-screenshots-on-tag.yml`](workflows/capture-screenshots-on-tag.yml) —
  runs `evidence capture-screenshots` against the configured device matrix
  whenever a release tag is pushed, then uploads the screenshots as a build
  artifact ready for App Store Connect.

## Fixture project

The `fixture-project/` directory ships a minimal `.evidence.toml` against
which the Action's self-test workflow validates `actionlint`, the `--help`
surface of the CLI, and the input wiring. It is not a full Xcode project —
real CI users supply their own app.

## Marketplace listing

The Action is published to the GitHub Marketplace as
[`RiddimSoftware/evidence`](https://github.com/marketplace/actions/evidence).
Pin to a major version (`@v0`) for stability or to a SHA for reproducibility.
