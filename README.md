# evidence

[![swift-test](https://github.com/RiddimSoftware/evidence/actions/workflows/swift-test.yml/badge.svg?branch=main)](https://github.com/RiddimSoftware/evidence/actions/workflows/swift-test.yml)
[![Use on GitHub Marketplace](https://img.shields.io/badge/Marketplace-evidence-purple?logo=githubactions)](https://github.com/marketplace/actions/evidence)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

`evidence` captures repeatable proof that app changes work. It turns real app runs into screenshots, videos, manifests, and reviewer-facing reports that can travel with a pull request or release.

Evidence is a small Swift package, CLI, and GitHub Action. It is iOS-first, with a Playwright-backed web screenshot mode.

## What It Does

- Captures iOS screenshot flows from app-owned UI tests.
- Captures before/after pull request evidence with screenshots, optional videos, `manifest.json`, and `report.md`.
- Produces build-evidence screenshots and optional `.xcresult` summaries.
- Resizes screenshots, renders marketing images, encodes preview videos, and dry-runs App Store screenshot uploads.
- Runs as a reusable GitHub Action on GitHub-hosted runners.

Evidence is not a hosted service, a deployment bot, or a replacement for tests and QA. Your app owns its plans, fixtures, credentials, generated artifacts, and release decisions.

## Requirements

- macOS 14 or newer for iOS workflows
- Xcode and Swift Package Manager
- ImageMagick for `resize` and `render-marketing`
- ffmpeg for `record-preview`
- GitHub CLI (`gh`) for `capture-pr`
- Node.js with Playwright for local `capture-web`

```sh
brew install imagemagick ffmpeg
npm install playwright
```

## Quick Start

```sh
git clone https://github.com/RiddimSoftware/evidence.git
cd evidence
swift test
swift run evidence -- --help
```

Render the sample marketing scene:

```sh
swift run evidence -- render-marketing \
  --scene Examples/Marketing/scene.json \
  --svg /tmp/evidence-scene.svg \
  --output /tmp/evidence-scene.png
```

## Use in an App

Add the `Evidence` library to an app UI test target, then describe the screens that should be proven:

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
                ScreenshotPlan.Scene(name: "Home", anchors: [.staticText("Home")])
            ]
        )

        try plan.run()
    }
}
```

Create `.evidence.toml` in the app repository:

```toml
scheme = "ExampleApp"
bundle_id = "com.example.app"
simulator_udid = "YOUR-SIMULATOR-UDID"
evidence_dir = "docs/build-evidence"
screenshot_targets = ["6.9", "6.5", "6.1", "5.5", "ipad-13"]
device_matrix = ["iPhone 16 Pro Max"]
```

If the Xcode project lives below the repo root, set one of:

```toml
xcode_workspace = "ios/MyApp.xcworkspace"
# or
xcode_project = "ios/MyApp.xcodeproj"
```

## CLI Commands

```sh
evidence capture-screenshots
evidence capture-evidence --ticket APP-123
evidence capture-pr --repo ExampleOrg/ExampleApp --pr 123 --plan .evidence/pr-home.json --output docs/build-evidence/pr-123
evidence capture-web
evidence resize --input raw.png --target 6.9 --output app-store.png
evidence record-preview --input capture.mov --output preview.mp4
evidence render-marketing --scene scene.json --svg scene.svg --output scene.png
evidence upload-screenshots --dry-run
```

`capture-pr` supports two plan runners:

- `simctl` for launch, wait, screenshot, open URL, and start/stop video steps.
- `xctest` for app-specific UI actions through an app-side `EvidencePlanRunner` test harness.

See [`Examples/pr-change-evidence-plan.json`](Examples/pr-change-evidence-plan.json) for a reusable plan template.

## GitHub Action

Use the Action from an app repository:

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

More examples live in [`Examples/workflows`](Examples/workflows).

## Public Repo Safety

Evidence keeps app-specific plans and generated artifacts in the consuming app repository or CI artifact store. Before publishing artifacts, check for customer data, unreleased product details, credentials, private URLs, and local machine paths.

Use GitHub-hosted runners for public pull request workflows. Keep App Store Connect `.p8` files and API keys out of git.

## Links

- [Troubleshooting](docs/troubleshooting.md)
- [Versioning](docs/versioning.md)
- [Repository metadata guidance](docs/repository-metadata.md)
- [Contributing](CONTRIBUTING.md)
- [Security](SECURITY.md)
- [Launch materials](docs/launch/README.md)

## License

MIT. See [`LICENSE`](LICENSE).
