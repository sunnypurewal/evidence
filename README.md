# evidence

`evidence` helps teams capture repeatable proof that app flows work, using real iOS app runs instead of manual replay.

It is an open-source Swift package and companion CLI for generating screenshots, App Store assets, preview video sources, and build evidence from declarative plans.

## Package

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

The `evidence` executable target is included as the home for the companion CLI. Capture, resizing, rendering, recording, and build-evidence subcommands will build on the package API.

## Development

```sh
swift test
swift run evidence
```
