# evidence

[![swift-test](https://github.com/RiddimSoftware/evidence/actions/workflows/swift-test.yml/badge.svg?branch=main)](https://github.com/RiddimSoftware/evidence/actions/workflows/swift-test.yml)
[![Use on GitHub Marketplace](https://img.shields.io/badge/Marketplace-evidence-purple?logo=githubactions)](https://github.com/marketplace/actions/evidence)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

`evidence` captures repeatable proof that app changes work. It turns real app runs into screenshots, videos, manifests, and reviewer-facing reports so a pull request can show generated artifacts instead of asking reviewers to trust a black-box coding loop.

Evidence is an open-source Swift package, CLI, and reusable GitHub Action. It is currently iOS-first, with a web screenshot mode for Playwright-backed captures.

## What Evidence Does Today

- Describes iOS screenshot flows with `ScreenshotPlan` scenes, anchors, launch hooks, and navigation actions.
- Runs screenshot, build-evidence, App Store screenshot, preview-video, marketing-render, web-capture, and before/after pull request evidence workflows from the CLI.
- Writes artifacts to predictable directories that can be reviewed locally, uploaded as CI artifacts, or summarized in pull request comments.
- Keeps app-specific plans, fixtures, credentials, copy, brand data, and generated artifacts in the consuming app repository.
- Provides ready-to-copy GitHub Actions examples under [`Examples/workflows`](Examples/workflows).

Evidence is not a hosted service, a release bot, a production deployment system, or a replacement for unit tests, UI tests, snapshot tests, human QA, or App Store review. It produces evidence artifacts; your app still owns the test data, launch state, simulator/device setup, and release decisions.

## Requirements

- macOS 14 or newer for iOS capture workflows
- Xcode and command line tools
- Swift Package Manager
- ImageMagick for `resize` and `render-marketing`
- ffmpeg for `record-preview`
- GitHub CLI (`gh`) for `capture-pr`
- Node.js with Playwright for local `capture-web` runs

```sh
brew install imagemagick ffmpeg
npm install playwright
```

`capture-web` installs Playwright Chromium automatically when you use the bundled GitHub Action with `platform: web`.

## Quick Start

Clone and verify the package:

```sh
git clone https://github.com/RiddimSoftware/evidence.git
cd evidence
swift test
swift run evidence -- --help
```

Render the sample marketing scene:

```sh
cd Examples
swift run --package-path .. evidence -- render-marketing \
  --scene Marketing/scene.json \
  --svg /tmp/evidence-scene.svg \
  --output /tmp/evidence-scene.png
```

## Package Usage

Add the `Evidence` library to an app's UI test target, then describe the scenes that should be proven and captured:

```swift
import Evidence
import XCTest

final class AppEvidenceTests: XCTestCase {
    func testCaptureScreenshots() throws {
        let plan = ScreenshotPlan(
            name: "App Store Screenshots",
            launchHook: LaunchHook(
                launchArguments: ["--ui-testing"],
                launchEnvironment: ["EVIDENCE_MODE": "1"]
            ),
            scenes: [
                ScreenshotPlan.Scene(
                    name: "Home",
                    anchors: [.staticText("Home")],
                    navigation: [.tap(label: "Search")]
                ),
                ScreenshotPlan.Scene(
                    name: "Search",
                    anchors: [.button("Cancel")]
                )
            ]
        )

        try plan.run()
    }
}
```

Screenshots are written to `EVIDENCE_OUTPUT_DIR`, `APPSTORE_SCREENSHOT_DIR`, or `EvidenceOutput` in the current directory.

For pull request comparisons, a UI test can load the same JSON evidence plan in both checked-out revisions:

```swift
import Evidence
import XCTest

final class AppEvidenceTests: XCTestCase {
    func testEvidencePlan() throws {
        try EvidencePlanRunner.runFromEnvironment(on: XCUIApplication())
    }
}
```

Set `EVIDENCE_PLAN_PATH` to the JSON plan path, or pass `--evidence-plan <path>` to the test process. Set `EVIDENCE_OUTPUT_DIR` to control where screenshots are written. When `EVIDENCE_REVISION_ROLE` is set to `before` or `after`, the runner executes matching phased steps and groups screenshots under that revision directory.

The XCTest runner supports launch, accessibility waits, screenshots, tap, type text, swipe, and open URL steps. Video capture and process orchestration remain CLI responsibilities. Historical revisions still need this UI test harness in the app test target; fallback UI automation for revisions without a harness is not part of the current package API.

## CLI Usage

Create a `.evidence.toml` file in the app repository that will run Evidence workflows:

```toml
scheme = "ExampleApp"
bundle_id = "com.example.app"
simulator_udid = "YOUR-SIMULATOR-UDID"
evidence_dir = "docs/build-evidence"
screenshot_targets = ["6.9", "6.5", "6.1", "5.5", "ipad-13"]
preview_targets = ["app-preview"]
device_matrix = ["iPhone 16 Pro Max"]
```

If the Xcode workspace or project that owns the screenshot UI tests is not at the directory where `evidence capture-screenshots` runs, set one of these optional fields:

```toml
xcode_workspace = "ios/MyApp.xcworkspace"
# or
xcode_project = "ios/MyApp.xcodeproj"
```

Set at most one. The value is forwarded to `xcodebuild` as `-workspace` or `-project`.

Current CLI commands:

```sh
evidence capture-screenshots
evidence capture-evidence --ticket APP-123
evidence capture-pr --repo ExampleOrg/ExampleApp --pr 123 --plan .evidence/pr-home.json --output docs/build-evidence/pr-123
evidence capture-web
evidence resize --input raw.png --target 6.9 --output app-store.png
evidence record-preview --input capture.mov --output preview.mp4 --trim-start 0 --trim-end 30
evidence render-marketing --scene scene.json --svg scene.svg --output scene.png
evidence upload-screenshots --dry-run
```

The CLI wraps Xcode simulator tooling, ImageMagick, ffmpeg, Playwright, and App Store Connect APIs with explicit checks so missing local dependencies fail with actionable messages.

### Build Evidence and xcresult Summaries

`evidence capture-evidence` captures a one-shot simulator screenshot into the configured `evidence_dir`.

When `xcresult_enabled = true` is set in `.evidence.toml`, the command also runs `xcodebuild test` with `-resultBundlePath` and writes:

- `<evidence_dir>/<KEY>.xcresult`
- `<evidence_dir>/<KEY>-tests.md`

Set `xcresult_keep_full_bundle = false` or pass `--xcresult-summary-only` to keep only the markdown summary in the evidence directory. The full bundle is moved to `~/.evidence/cache/<KEY>.xcresult` for local inspection without bloating the app repository.

### Pull Request Change Evidence

Use `capture-pr` when a reviewer needs to see what a pull request changed. The command compares before and after revisions, runs the same evidence plan against both, and writes:

- before/after screenshots under `<output>/before/` and `<output>/after/`
- optional before/after simulator videos
- `manifest.json` with selected SHAs, build commands, step results, artifact paths, and failures
- `report.md` with a reviewer-oriented summary

```sh
evidence capture-pr \
  --repo ExampleOrg/ExampleApp \
  --pr 123 \
  --plan .evidence/pr-home.json \
  --output docs/build-evidence/pr-123
```

The reusable sample plan lives at [`Examples/pr-change-evidence-plan.json`](Examples/pr-change-evidence-plan.json). Copy it into the consuming app repository and replace the sample repo, PR number, Xcode project or workspace, scheme, bundle ID, simulator, and URL values. Keep generated evidence output in the consuming app repository or CI artifact store, not in this repository.

`capture-pr` has two runner modes:

- `runner = "simctl"` can launch the built app, open URLs, wait by seconds, take screenshots, and record start/stop video steps.
- `runner = "xctest"` runs an app-side XCTest Evidence harness. Use it for taps, typing, swipes, and accessibility waits.

### Web Capture

Set `platform = "web"` in `.evidence.toml`:

```toml
platform = "web"
web_url = "https://example.com"
web_viewports = ["desktop-1440", "mobile-390"]
web_full_page = true
web_wait_until = "networkidle"
evidence_dir = "docs/build-evidence/web"
```

Then run:

```sh
evidence capture-web
```

Named viewport presets include `desktop-1440` and `mobile-390`. Custom `WIDTHxHEIGHT` strings are also accepted.

### Marketing Renders and Preview Videos

Use raw capture when the screenshot should show the app exactly as it runs. Use `render-marketing` when the App Store asset needs a composed layout with headlines, badges, metrics, timelines, device framing, or source text around app imagery.

Marketing scenes are JSON files with app-owned copy and brand values. See [`Examples/Marketing/scene.json`](Examples/Marketing/scene.json) for a complete example.

Use `record-preview` to encode a captured `.mov` into an App Preview-compatible H.264 `.mp4` with no audio:

```sh
evidence record-preview --input capture.mov --output preview.mp4
```

### Upload to App Store Connect

`evidence upload-screenshots` scans PNGs under `evidence_dir`, validates their dimensions against the device target directory, plans create/replace/skip actions, and uploads changed screenshots through App Store Connect's resumable upload operations.

Add App Store Connect API credentials to `.evidence.toml`:

```toml
[app_store_connect]
key_id = "ABC123DEFG"
issuer_id = "00000000-0000-0000-0000-000000000000"
p8_path = ".secrets/AuthKey_ABC123DEFG.p8"
app_id = "1234567890"
```

The private `.p8` file should stay outside git. In CI, write it from a secret before running the command.

Supported screenshot layouts:

```text
docs/build-evidence/6.9/01-home.png
docs/build-evidence/ipad-13/01-home.png
docs/build-evidence/en-US/6.9/01-home.png
docs/build-evidence/fr-FR/6.9/01-home.png
```

Use dry-run first:

```sh
evidence upload-screenshots --dry-run
evidence upload-screenshots --dry-run --locale en-US
```

## Use in CI

Evidence ships a reusable GitHub Action so app repositories can run the CLI on public GitHub-hosted runners. Pin to a major version for stability, or to a SHA for full reproducibility.

**iOS build evidence on every PR:**

```yaml
jobs:
  capture-evidence:
    runs-on: macos-14
    permissions:
      pull-requests: write
      contents: read
    steps:
      - uses: actions/checkout@v4
      - uses: RiddimSoftware/evidence@v0
        with:
          subcommand: capture-evidence
          ticket: ${{ github.event.pull_request.title }}
          comment-on-pr: 'true'
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

**iOS before/after PR evidence:**

```yaml
jobs:
  capture-pr:
    runs-on: macos-14
    permissions:
      pull-requests: write
      contents: read
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: RiddimSoftware/evidence@v0
        with:
          subcommand: capture-pr
          plan: .evidence/pr-home.json
          output-dir: docs/build-evidence/pr-${{ github.event.pull_request.number }}
          comment-on-pr: 'true'
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

**Web screenshots on every PR:**

```yaml
jobs:
  capture-web:
    runs-on: ubuntu-latest
    permissions:
      pull-requests: write
      contents: read
    steps:
      - uses: actions/checkout@v4
      - name: Start local HTTP server
        run: python3 -m http.server 8765 &
      - uses: RiddimSoftware/evidence@v0
        with:
          subcommand: capture-web
          platform: web
          comment-on-pr: 'true'
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

The Action accepts a `subcommand` input matching the CLI verb (`capture-screenshots`, `capture-evidence`, `capture-pr`, `capture-web`, `resize`, `render-marketing`, `record-preview`, `upload-screenshots`) along with passthrough inputs for `config`, `ticket`, `output-dir`, and `extra-args`. For `capture-pr`, use `plan` plus optional `pr`, `before-ref`, `after-ref`, `keep-worktrees`, and `summary-only`.

Set `comment-on-pr: 'true'` and pass `github-token` to post a PR comment. Standard captures list produced artifacts; `capture-pr` summarizes `report.md` with status, before/after SHAs, artifact count, and the report path. The comment step is skipped when no token is supplied or when the workflow does not run on a `pull_request` event.

Four ready-to-copy workflows live under [`Examples/workflows`](Examples/workflows):

- `capture-evidence-on-pr.yml`
- `capture-pr-on-pr.yml`
- `capture-screenshots-on-tag.yml`
- `capture-web-on-pr.yml`

## Privacy and Security

Evidence intentionally keeps app-specific plans and generated artifacts in the consuming repository or CI artifact store. Before publishing artifacts, review them for customer data, unreleased product details, credentials, private URLs, and environment-specific paths.

Recommended defaults:

- Keep `.p8` files, API keys, fixture databases, and generated evidence bundles out of git unless they are intentionally sanitized examples.
- Use `upload-screenshots --dry-run` before mutating App Store Connect.
- Use GitHub-hosted runners for public pull request workflows.
- Treat PR comments and uploaded artifacts as public when the repository is public.
- Report vulnerabilities privately; see [`SECURITY.md`](SECURITY.md).

## Riddim Software Factory Context

Evidence is the artifact layer in the Riddim Software Factory narrative. Autonomous coding can change an app, but reviewers still need concrete proof that the app satisfies the requirement. Evidence produces that proof as generated artifacts: screenshots, videos, manifests, and reports tied to the pull request or release flow.

The goal is modest and auditable: make claims about app behavior traceable to repeatable captures that another builder can inspect.

## Repository Metadata

The repository metadata that requires the GitHub UI is tracked separately from code changes:

- Description: `Repeatable proof artifacts for app changes: screenshots, videos, manifests, and reports from real app runs.`
- Topics: `swift`, `ios`, `xctest`, `github-actions`, `app-store`, `visual-testing`, `automation`
- Homepage: GitHub Marketplace listing or the public launch article once available
- License: MIT

These settings should be verified after the repository visibility is changed to public. See [`docs/repository-metadata.md`](docs/repository-metadata.md).

## Documentation

- [`Examples/README.md`](Examples/README.md) explains the Action examples and PR evidence plan fixture.
- [`docs/troubleshooting.md`](docs/troubleshooting.md) covers simulator, permissions, dependency, and output-path problems.
- [`docs/versioning.md`](docs/versioning.md) describes the v0.x stability policy.
- [`docs/launch/README.md`](docs/launch/README.md) contains public launch materials aligned with the current CLI.
- [`CONTRIBUTING.md`](CONTRIBUTING.md) explains safe contribution guidelines.

## Development

```sh
swift test
swift run evidence -- --help
actionlint .github/workflows/*.yml Examples/workflows/*.yml
```

## License

MIT. See [`LICENSE`](LICENSE).
