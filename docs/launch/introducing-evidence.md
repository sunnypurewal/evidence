# Introducing Evidence: repeatable proof for app changes

Every app team has a version of the same release ritual. The build is green, the code has been reviewed, and someone still opens the app to make sure the checkout screen, onboarding path, subscription wall, or settings flow appears the way reviewers expect.

That final pass is valuable. It catches broken launch state, stale fixtures, missing permissions, accidental copy regressions, and subtle UI problems that pure unit tests do not see. The problem is that it is usually performed from memory. One engineer taps through the app before a release, another records a short clip for a pull request, and someone else re-runs a screenshot script after copy changes. The evidence exists for a moment, then disappears into a local folder or chat thread.

`evidence` is an open-source Swift package and CLI that turns that release ritual into a repeatable workflow. It lets you describe real app flows, run them through app-owned tests or simulator automation, and write proof artifacts into predictable directories. The output can be screenshots, videos, manifests, pull request evidence reports, preview-video sources, marketing renders, or App Store Connect upload plans.

The goal is simple: when a pull request or release says "this flow works," reviewers should have fresh artifacts from a real app run.

## What Evidence does

At the package layer, Evidence gives UI tests a small vocabulary for screenshot plans:

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

Each scene has anchors that must appear before capture. That matters because screenshots are only useful if they prove the app reached the intended state. If an anchor does not appear, the test fails before writing misleading output.

At the CLI layer, Evidence wraps the release chores around those plans:

```sh
evidence capture-screenshots
evidence capture-evidence --ticket APP-123
evidence capture-pr --repo ExampleOrg/ExampleApp --pr 123 --plan .evidence/pr-home.json --output docs/build-evidence/pr-123
evidence capture-web
evidence resize --input raw.png --target 6.9 --output app-store.png
evidence render-marketing --scene scene.json --svg scene.svg --output scene.png
evidence record-preview --input capture.mov --output preview.mp4
evidence upload-screenshots --dry-run
```

The CLI reads `.evidence.toml` from the app repository. That keeps app-specific details, generated artifacts, launch flags, screenshots, and brand copy in the consuming app instead of baking them into a shared tool.

```toml
scheme = "ExampleApp"
bundle_id = "com.example.app"
simulator_udid = "YOUR-SIMULATOR-UDID"
evidence_dir = "docs/build-evidence"
screenshot_targets = ["6.9", "6.5", "6.1", "5.5", "ipad-13"]
device_matrix = ["iPhone 16 Pro Max"]
```

## Pull request evidence

`capture-pr` is the review-focused workflow. It resolves before and after revisions for a pull request, prepares isolated worktrees, builds each revision, runs the same evidence plan, and writes:

- before/after screenshots
- optional before/after videos
- `manifest.json` with selected SHAs, commands, artifacts, and failures
- `report.md` for reviewers

There are two runner modes. `runner = "simctl"` covers launch-only flows such as opening a URL, waiting, taking screenshots, and recording videos. `runner = "xctest"` uses an app-side XCTest Evidence harness for richer UI actions such as taps, typing, swipes, and accessibility waits.

That boundary is intentional. Evidence should not know how to log into your app, seed your fixtures, or navigate domain-specific flows. The consuming app owns that knowledge; Evidence owns the repeatable artifact mechanics.

## CI adoption

Evidence ships as a GitHub Action for GitHub-hosted runners:

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

The same commands run locally. That is deliberate. CI should not be a special environment where the only way to debug a screenshot workflow is to push another commit and wait. If a pull request comment shows a bad capture, a developer should be able to run the same command on a Mac, inspect the files under `evidence_dir`, adjust the app state or anchors, and push a small fix.

## App Store assets without a separate toolchain

Once a tool knows where screenshots live and which dimensions each App Store target requires, the next useful step is a dry-run upload plan.

With App Store Connect configuration:

```toml
[app_store_connect]
key_id = "ABC123DEFG"
issuer_id = "00000000-0000-0000-0000-000000000000"
p8_path = ".secrets/AuthKey_ABC123DEFG.p8"
app_id = "1234567890"
```

you can run:

```sh
evidence upload-screenshots --dry-run
```

The command scans `evidence_dir`, validates dimensions, lists which slots would be created or replaced, and skips screenshots whose content hash already matches. A real upload uses App Store Connect API upload operations for the PNG bytes.

The dry-run is the safer default. It lets you confirm the directory layout, device mapping, dimensions, locale folders, and content-hash behavior before replacing anything.

## What is intentionally out of scope

Evidence is not a hosted service. It does not store your screenshots, require an inbound webhook server, or ask you to move app-specific release knowledge into a central dashboard.

It is also not a replacement for product analytics, unit tests, snapshot-testing frameworks, App Store review, or human QA. Evidence is the small missing piece between "the test passed" and "here is visible proof of the flow that changed."

The current package is iOS-first and practical rather than universal. It assumes Xcode, XCTest, macOS runners for iOS workflows, and a team that is comfortable keeping release artifacts in the repository or CI artifact store. The narrower scope keeps the tool small enough to audit and easy enough to adapt.

## Getting started

Clone the repo and run the tests:

```sh
git clone https://github.com/RiddimSoftware/evidence.git
cd evidence
swift test
swift run evidence -- --help
```

Then add the `Evidence` package to an app's UI test target, create a `.evidence.toml`, and start with one flow that is painful to verify manually. Good candidates are onboarding, purchase, settings, import/export, or any flow whose screenshot usually ends up in release notes or App Store assets.

The project is MIT licensed and open to issues and pull requests. The best first contributions are small adapters, clearer docs for real app setups, and examples that make repeatable visual proof easier for app teams to adopt.
