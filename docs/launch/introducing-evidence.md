# Introducing evidence: repeatable proof for iOS app flows

Every iOS team has a version of the same release ritual. The build is green, the code has been reviewed, and someone still opens the app on a simulator to make sure the checkout screen, onboarding path, subscription wall, or settings flow actually appears the way reviewers expect.

That last manual pass is valuable. It catches broken launch state, stale fixtures, missing permissions, accidental copy regressions, and the subtle UI problems that pure unit tests do not see. The problem is that it is usually performed from memory. One engineer taps through the app before a release, another engineer records a short clip for a pull request, and someone else re-runs a screenshot script after copy changes. The evidence exists for a moment, then disappears into a local Downloads folder or a chat thread.

`evidence` is an open-source Swift package and CLI that turns that release ritual into a repeatable workflow. It lets you describe real app flows as declarative scenes, run them through XCUITest, and write proof artifacts into predictable directories. The output can be screenshots, App Store source material, preview-video inputs, visual regression reports, build evidence, or App Store Connect upload plans.

The goal is simple: when a pull request or release says "this flow works," the repository should contain fresh proof from a real app run.

## What evidence does

At the package layer, evidence gives UI tests a small vocabulary for screenshot plans:

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

The plan stays close to the UI test because that is where release proof belongs. A consuming app can decide how to seed state, which fake services to use, which launch arguments disable animation, and which screens should become part of the release record. Evidence does not need to know the app's domain model. It only needs to know how to launch, wait for visible anchors, navigate, and write the capture.

That keeps adoption incremental. You do not have to redesign a test suite to try it. Start with one UI test target, add the package, describe the one flow your team already verifies by hand, and commit the output directory convention. If the flow is useful, add more scenes. If it is not, the app has not taken on a permanent service dependency or a separate screenshot platform.

At the CLI layer, evidence wraps the release chores around those plans:

```sh
evidence capture-screenshots
evidence capture-evidence --ticket APP-123
evidence diff --markdown docs/build-evidence/diff.md
evidence resize --input raw.png --target 6.9 --output app-store.png
evidence render-marketing --scene scene.json --svg scene.svg --output scene.png
evidence record-preview --input capture.mov --output preview.mp4
evidence upload-screenshots --dry-run
```

The CLI reads `.evidence.toml` from the app repository. That keeps app-specific details, generated artifacts, launch flags, screenshots, baselines, and brand copy in the consuming app instead of baking them into a shared tool.

```toml
scheme = "ExampleApp"
bundle_id = "com.example.app"
simulator_udid = "YOUR-SIMULATOR-UDID"
evidence_dir = "docs/build-evidence"
screenshot_targets = ["6.9", "6.5", "6.1", "5.5", "ipad-13"]
device_matrix = ["ExampleUITests/AppEvidenceTests/testCaptureScreenshots"]
```

The configuration is intentionally plain. It is meant to live beside the app code, be reviewed like any other release workflow, and be understandable without a dashboard. A reviewer can see the scheme, bundle identifier, simulator, evidence directory, screenshot targets, and test entry point in one file.

## Why not just use screenshots?

Screenshots by themselves are not the hard part. The hard part is making screenshots trustworthy enough to use in a release process.

A screenshot workflow needs to answer practical questions:

- Which app state produced this image?
- Which launch flags and fake services were used?
- Did the UI reach the expected screen before capture?
- Is the output path stable enough for CI and pull request comments?
- Can a visual change be compared against a committed baseline?
- Can the same captures become App Store assets without a separate script?

Evidence is designed around those questions. A `ScreenshotPlan` names the intended scenes and anchors. `evidence diff` compares the latest run to committed baselines and writes both diff images and a machine-readable report. `capture-evidence` can pair a simulator screenshot with an `.xcresult` summary so build or test failures produce something a reviewer can read. `upload-screenshots --dry-run` validates App Store dimensions and prints the slot changes before touching App Store Connect.

That last part is important for release work. A failed UI test already blocks a merge, but a reviewer often needs to know what changed visually and whether the failing state is useful. Evidence tries to make the artifact readable even when the run is not green. A build error can become a short markdown summary. A visual regression can become a table with a diff image. A screenshot upload can become a dry-run plan instead of a risky final step.

It also avoids another common problem: every app growing its own folder of one-off shell scripts. Those scripts usually start small, then learn about simulator booting, output paths, ImageMagick, preview video settings, baseline copies, and App Store dimensions. Evidence packages those generic mechanics while leaving app-specific choices in the app repository.

## Use it in CI

Evidence ships as a GitHub Action for macOS runners:

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

There are ready-to-copy workflows in `Examples/workflows/` for pull request evidence and release-tag screenshot capture. The action builds the CLI, checks runner compatibility, installs ImageMagick and ffmpeg when needed, and can post pull request comments with produced artifacts.

The same commands run locally. That is deliberate. CI should not be a special environment where the only way to debug a screenshot workflow is to push another commit and wait. If a pull request comment shows a bad capture, a developer should be able to run the same command on a Mac, inspect the files under `evidence_dir`, adjust the app state or anchors, and push a small fix.

The GitHub Action is therefore a convenience wrapper, not the only supported path. Teams that use another CI system can call the CLI directly from a macOS worker. Teams that prefer local release builds can keep the workflow entirely on a release machine.

## App Store assets without a separate toolchain

Evidence does not try to replace your whole release system. It focuses on proof artifacts and screenshots. But once a tool already knows where screenshots live and which dimensions each App Store target requires, the next useful step is a dry-run upload plan.

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

This does not mean every team should upload screenshots automatically on the first day. The dry-run is the safer default. It lets you confirm the directory layout, device mapping, dimensions, locale folders, and content-hash behavior before replacing anything. Once the plan is boring, the same command can perform the upload.

Evidence supports both a simple layout such as `docs/build-evidence/6.9/01-home.png` and a localized layout such as `docs/build-evidence/en-US/6.9/01-home.png`. That keeps the path from a single-locale app to a localized release manageable without changing the core command shape.

## What is intentionally out of scope

Evidence is not a hosted service. It does not store your app screenshots, require an inbound webhook server, or ask you to move app-specific release knowledge into a central dashboard.

It is also not a replacement for product analytics, unit tests, snapshot-testing frameworks, or human QA. Evidence is the small missing piece between "the test passed" and "here is visible proof of the flow that changed."

The current package is iOS-first and practical rather than universal. It assumes Xcode, XCTest, macOS runners, and a team that is comfortable keeping release artifacts in the repo or CI artifacts. That narrower scope is a feature for now. It keeps the tool small enough to audit and easy enough to adapt.

## Getting started

Clone the repo and run the tests:

```sh
git clone https://github.com/sunnypurewal/evidence.git
cd evidence
swift test
swift run evidence -- --help
```

Then add the `Evidence` package to an app's UI test target, create a `.evidence.toml`, and start with one flow that is painful to verify manually. Good candidates are onboarding, purchase, settings, import/export, or any flow whose screenshot usually ends up in release notes or App Store assets.

The project is MIT licensed and open to issues and pull requests. The best first contributions are small adapters, clearer docs for real app setups, and examples that make repeatable visual proof easier for iOS teams to adopt.
