# Repeatable app proof artifacts with Evidence

Manual walkthroughs are still part of a lot of app release processes. Even with a healthy test suite, someone usually launches the app before a release and checks the flow that matters: onboarding, subscription, import, checkout, settings, or whatever changed in the last pull request.

That check is useful. The fragile part is that the proof often disappears. It lives in a local screenshot, a short recording, or a chat message instead of the repository.

[`evidence`](https://github.com/RiddimSoftware/evidence) is an open-source Swift package and CLI for making that proof repeatable. It uses real app runs and writes screenshots, videos, manifests, and reports to predictable paths.

## Describe the app state, then capture it

The package adds a small declarative layer on top of UI tests:

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

Anchors are the important part. A capture only happens after the expected UI appears, so the screenshot proves the app reached the intended state.

## Run it from the app repo

The CLI reads `.evidence.toml` from the consuming app:

```toml
scheme = "ExampleApp"
bundle_id = "com.example.app"
simulator_udid = "YOUR-SIMULATOR-UDID"
evidence_dir = "docs/build-evidence"
screenshot_targets = ["6.9", "6.5", "6.1", "5.5", "ipad-13"]
device_matrix = ["iPhone 16 Pro Max"]
```

Then the app can run:

```sh
evidence capture-screenshots
evidence capture-evidence --ticket APP-123
evidence capture-pr --repo ExampleOrg/ExampleApp --pr 123 --plan .evidence/pr-home.json --output docs/build-evidence/pr-123
evidence upload-screenshots --dry-run
```

The same output directory can feed pull request comments, release checks, and App Store screenshot upload plans.

## GitHub Actions

Evidence ships as a composite GitHub Action:

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

The action handles the CLI build, runner checks, ImageMagick/ffmpeg setup, Playwright setup for web captures, and optional pull request comments.

## Where it fits

Evidence is not meant to replace unit tests, snapshot-testing libraries, or human QA. It is a release-proof layer: the thing that turns "I tapped through it locally" into reproducible artifacts that can live with the code change.

Use it when a reviewer or release owner needs to see that a real app flow still works.

Repo: <https://github.com/RiddimSoftware/evidence>

Suggested tags: `swift`, `ios`, `testing`, `automation`, `github-actions`
