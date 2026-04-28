# evidence

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

## Documentation

- `docs/troubleshooting.md` covers common simulator, permissions, dependency, and output-path problems.
- `docs/versioning.md` describes the v0.x stability policy and release-note expectations.
- `CONTRIBUTING.md` explains how to report issues and open pull requests safely in a public repository.

## Development

```sh
swift test
swift run evidence -- --help
```

## License

MIT. See `LICENSE`.
