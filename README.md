# evidence

[![Use on GitHub Marketplace](https://img.shields.io/badge/Marketplace-evidence-purple?logo=githubactions)](https://github.com/marketplace/actions/evidence)

`evidence` captures repeatable proof that app flows work, using real iOS app runs instead of manual replay.

It is an open-source Swift package and companion CLI for screenshots, App Store assets, preview video sources, and build evidence from declarative plans.

## What It Does

- Describes screenshot flows as `ScreenshotPlan` scenes, anchors, launch hooks, and navigation actions.
- Writes captures to predictable output directories for review, release checks, and App Store source material.
- Provides CLI workflows for screenshot capture, build evidence, resizing, marketing renders, and preview video encoding.
- Keeps app-specific plans, copy, brand data, and generated artifacts in the consuming app repository.

## Requirements

- macOS 14 or newer
- Xcode and command line tools
- Swift Package Manager
- ImageMagick for `resize` and `render-marketing`
- ffmpeg for `record-preview`
- Fastlane if a consuming app still uses Fastlane snapshot around the capture workflow

```sh
brew install imagemagick ffmpeg
```

## Quick Start

Clone and verify the package:

```sh
git clone https://github.com/sunnypurewal/evidence.git
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

## CLI Usage

Create a `.evidence.toml` file in the project that will run evidence workflows:

```toml
scheme = "ExampleApp"
bundle_id = "com.example.app"
simulator_udid = "YOUR-SIMULATOR-UDID"
evidence_dir = "docs/build-evidence"
screenshot_targets = ["6.9", "6.5", "6.1", "5.5", "ipad-13"]
preview_targets = ["app-preview"]
device_matrix = ["iPhone 16 Pro Max"]
```

If the Xcode workspace or project that owns the screenshot UI tests is not at the directory where `evidence capture-screenshots` runs (for example, the iOS project lives in `ios/` while `.evidence.toml` lives at the repo root), set one of the optional fields below. The value is forwarded to `xcodebuild` as `-workspace` or `-project`. Set at most one:

```toml
# Either:
xcode_workspace = "ios/MyApp.xcworkspace"
# Or:
xcode_project = "ios/MyApp.xcodeproj"
```

Run the command that matches the workflow:

```sh
evidence capture-screenshots
evidence capture-evidence --ticket APP-123
evidence resize --input raw.png --target 6.9 --output app-store.png
evidence record-preview --input capture.mov --output preview.mp4 --trim-start 0 --trim-end 30
evidence render-marketing --scene scene.json --svg scene.svg --output scene.png
```

The CLI wraps Xcode simulator tooling, ImageMagick, and ffmpeg with explicit checks so missing local dependencies fail with actionable messages.

Use raw capture when the screenshot should show the app exactly as it runs. Use `render-marketing` when the App Store asset needs a composed layout with headlines, badges, metrics, timelines, device framing, or source text around app imagery.

Marketing scenes are JSON files with app-owned copy and brand values. See `Examples/Marketing/scene.json` for a complete example using the supported row kinds: `left`, `right`, `badge`, `metric`, `timeline`, `stage`, `row`, and `compose`.

## Use in CI

`evidence` ships a reusable GitHub Action so any iOS app repo can run the CLI on a hosted macOS runner without bootstrapping Xcode tooling, ImageMagick, or ffmpeg by hand. Pin to a major version for stability, or to a SHA for full reproducibility.

```yaml
jobs:
  capture-evidence:
    runs-on: macos-14
    permissions:
      pull-requests: write
      contents: read
    steps:
      - uses: actions/checkout@v4
      - uses: sunnypurewal/evidence@v0
        with:
          subcommand: capture-evidence
          ticket: ${{ github.event.pull_request.title }}
          comment-on-pr: 'true'
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

The Action accepts a `subcommand` input matching the CLI verb (`capture-screenshots`, `capture-evidence`, `resize`, `render-marketing`, `record-preview`, `diff`) along with passthrough inputs for `config`, `ticket`, `baseline-dir`, `output-dir`, and `extra-args`. Set `comment-on-pr: 'true'` and pass `github-token` to have the Action post a PR comment listing every artifact produced by the run; the comment step is automatically skipped when no token is supplied or when the workflow does not run on a `pull_request` event.

ImageMagick and ffmpeg are installed and cached the first time the Action runs on a given runner, so warm runs reuse the formula tarballs. The `evidence` CLI itself is built once per release ref and cached under `~/runner.temp/evidence-build/.build`.

Two ready-to-copy workflows live under [`Examples/workflows/`](Examples/workflows/):

- `capture-evidence-on-pr.yml` — captures a screenshot per pull request, posts it as a PR comment, and uploads it as an artifact.
- `capture-screenshots-on-tag.yml` — captures the full App Store screenshot matrix when you push a release tag.

Marketplace listing: <https://github.com/marketplace/actions/evidence>. The Action only supports `macos-14` and newer hosted runners; self-hosted macOS runners and non-macOS runners are out of scope for v1.

## Documentation

- `docs/troubleshooting.md` covers common simulator, permissions, dependency, and output-path problems.
- `docs/versioning.md` describes the v0.x stability policy and release-note expectations.
- `CONTRIBUTING.md` explains how to report issues and open pull requests safely in a public repository.
- `Examples/README.md` describes the shipped GitHub Action examples and fixture project.

## Development

```sh
swift test
swift run evidence -- --help
```

## License

MIT. See `LICENSE`.
