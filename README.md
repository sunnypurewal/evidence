# evidence

[![swift-test](https://github.com/RiddimSoftware/evidence/actions/workflows/swift-test.yml/badge.svg?branch=main)](https://github.com/RiddimSoftware/evidence/actions/workflows/swift-test.yml)
[![Use on GitHub Marketplace](https://img.shields.io/badge/Marketplace-evidence-purple?logo=githubactions)](https://github.com/marketplace/actions/evidence)

`evidence` captures repeatable proof that app flows work, using real iOS app runs instead of manual replay.

It is an open-source Swift package and companion CLI for screenshots, App Store assets, preview video sources, and build evidence from declarative plans.

## What It Does

- Describes screenshot flows as `ScreenshotPlan` scenes, anchors, launch hooks, and navigation actions.
- Writes captures to predictable output directories for review, release checks, and App Store source material.
- Provides CLI workflows for screenshot capture, build evidence, resizing, marketing renders, and preview video encoding.
- Uploads App Store screenshots from the same captured directory with dry-run planning and dimension checks.
- Keeps app-specific plans, copy, brand data, and generated artifacts in the consuming app repository.

## Requirements

- macOS 14 or newer
- Xcode and command line tools
- Swift Package Manager
- ImageMagick for `resize` and `render-marketing`
- ffmpeg for `record-preview`
- GitHub CLI (`gh`) for `capture-pr`
- Fastlane if a consuming app still uses Fastlane snapshot around the capture workflow

```sh
brew install imagemagick ffmpeg
```

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

For pull request comparisons, a UI test can load the same JSON evidence plan in both checked-out revisions instead of rebuilding the flow in Swift:

```swift
import Evidence
import XCTest

final class AppEvidenceTests: XCTestCase {
    func testEvidencePlan() throws {
        try EvidencePlanRunner.runFromEnvironment(on: XCUIApplication())
    }
}
```

Set `EVIDENCE_PLAN_PATH` to the JSON plan path, or pass `--evidence-plan <path>` to the test process. Set `EVIDENCE_OUTPUT_DIR` to control where screenshots are written. When `EVIDENCE_REVISION_ROLE` is set, for example to `before` or `after`, the runner executes matching phased steps and groups screenshots under that revision directory. The app-side XCTest runner supports launch, accessibility waits, screenshots, tap, type text, swipe, and open URL steps. Video capture and process orchestration remain CLI responsibilities. Historical revisions still need this UI test harness in the app test target; fallback capture for revisions without it is not part of the current package API.

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

### xcresult bundles

`evidence capture-evidence` can also produce the matching `.xcresult` bundle from `xcodebuild test`, plus a markdown summary suitable for inlining in a pull request comment. Enable it in `.evidence.toml`:

```toml
xcresult_enabled = true
xcresult_keep_full_bundle = true   # default; set false to ship only the summary
```

A run with `--ticket APP-123` then writes:

- `<evidence_dir>/APP-123-running.png` (the screenshot, as before)
- `<evidence_dir>/APP-123.xcresult`     (full bundle, openable in Xcode and `xcrun xcresulttool`)
- `<evidence_dir>/APP-123-tests.md`     (totals, first three failures with `file:line`, total duration)

When `xcresult_keep_full_bundle = false` (or the CLI flag `--xcresult-summary-only` is passed), the markdown summary stays in the evidence directory and the full bundle is moved to `~/.evidence/cache/APP-123.xcresult` so the bundle remains inspectable locally without bloating the repo.

If `xcodebuild test` fails before the bundle is produced (for example, a build error), `<KEY>-tests.md` still gets written with a `Build error` excerpt so the PR comment surfaces what went wrong. The CLI exits non-zero in that case so CI catches the failure.

> The conceptual `[xcresult]` table is exposed as flat keys (`xcresult_enabled`, `xcresult_keep_full_bundle`) because the project's TOML parser is intentionally lightweight. Behaviour is otherwise identical.

Run the command that matches the workflow:

```sh
evidence capture-screenshots
evidence capture-evidence --ticket APP-123
evidence capture-pr --repo RiddimSoftware/app --pr 123 --plan .evidence/pr-home.json --output docs/evidence/pr-123
evidence resize --input raw.png --target 6.9 --output app-store.png
evidence record-preview --input capture.mov --output preview.mp4 --trim-start 0 --trim-end 30
evidence render-marketing --scene scene.json --svg scene.svg --output scene.png
evidence upload-screenshots --dry-run
```

The CLI wraps Xcode simulator tooling, ImageMagick, and ffmpeg with explicit checks so missing local dependencies fail with actionable messages.

`capture-pr` resolves a pull request's before/after revisions and prepares two isolated worktrees under `<output>/worktrees/` without switching the root checkout. For open PRs it uses the current base and head SHAs; for merged PRs it uses the merge commit and its first parent when available. Pass `--before-ref` or `--after-ref` to override either side.

For iOS plans, `capture-pr` then builds each revision from its own worktree using the plan's `ios.workspace` or `ios.project`, `ios.scheme`, `ios.configuration`, `ios.destination`, and optional `ios.extra_xcodebuild_arguments`. DerivedData is isolated by revision under `<output>/derived-data/before` and `<output>/derived-data/after`, and build logs are written under `<output>/logs/`. The manifest records each build command, exit code, duration, stdout/stderr excerpts, app bundle path, DerivedData path, and log path.

Plan execution runs the same steps for the before and after revisions. For `runner = "xctest"`, Evidence invokes `xcodebuild test` once per revision with `EVIDENCE_PLAN_PATH`, `EVIDENCE_OUTPUT_DIR`, and `EVIDENCE_REVISION_ROLE` in the test process environment so the app-side `EvidencePlanRunner` can replay the JSON plan. Screenshots land under revision-specific paths such as `<output>/before/home.png` and `<output>/after/home.png`. Video steps are recorded by CLI-managed simulator recording around the XCTest run and manifest under revision-specific paths such as `<output>/before/flow.mov` and `<output>/after/flow.mov`.

For launch-only `runner = "simctl"` plans, Evidence resolves the configured `ios.simulator_udid` or `ios.simulator`, boots and waits for the device, applies stable UI settings when the local simulator supports them, uninstalls the app by default to clear container state, installs the built app, and launches it with the plan's launch arguments and environment. Launch environment is injected as `SIMCTL_CHILD_<KEY>` variables for local simulator compatibility. The simctl runner supports launch, wait-by-seconds, screenshot, openURL, startVideo, and stopVideo steps. Screenshots and videos are written under revision directories such as `<output>/before/home.png`, `<output>/after/home.png`, `<output>/before/flow.mov`, and `<output>/after/flow.mov`. Set `ios.preserve_simulator_state` to `true` only when the before/after comparison intentionally needs shared app container state.

The manifest includes build records, step results, artifact paths, revision roles, media types, file sizes when the artifact exists, capture timestamps, and failure summaries. If a capture step fails, the command exits non-zero after writing the partial manifest so a report can still explain which revision and step failed.

Use raw capture when the screenshot should show the app exactly as it runs. Use `render-marketing` when the App Store asset needs a composed layout with headlines, badges, metrics, timelines, device framing, or source text around app imagery.

Marketing scenes are JSON files with app-owned copy and brand values. See `Examples/Marketing/scene.json` for a complete example using the supported row kinds: `left`, `right`, `badge`, `metric`, `timeline`, `stage`, `row`, and `compose`.

### Upload to App Store Connect

`evidence upload-screenshots` closes the loop from captured screenshots to App Store Connect screenshot slots. It scans PNGs under `evidence_dir`, validates their dimensions against the device target directory, plans create/replace/skip actions, and uploads changed screenshots through App Store Connect's resumable upload operations.

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

The plan lists every slot, whether the content hash already matches (`✓`) or would change (`✗`), and the action (`create`, `replace`, or `skip`). A real upload deletes replaced screenshots, creates new screenshot resources, uploads the PNG bytes through the returned upload operations, and marks each screenshot uploaded.

GitHub Actions example:

```yaml
jobs:
  upload-screenshots:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Write App Store Connect key
        shell: bash
        env:
          ASC_PRIVATE_KEY: ${{ secrets.ASC_PRIVATE_KEY }}
        run: |
          mkdir -p .secrets
          printf '%s' "$ASC_PRIVATE_KEY" > .secrets/AuthKey_ABC123DEFG.p8
      - uses: RiddimSoftware/evidence@v0
        with:
          subcommand: upload-screenshots
          extra-args: '--dry-run'
```

## Use in CI

`evidence` ships a reusable GitHub Action so any iOS app repo can run the CLI on a hosted macOS runner without bootstrapping Xcode tooling, ImageMagick, or ffmpeg by hand. Pin to a major version for stability, or to a SHA for full reproducibility.

**iOS — capture build evidence on every PR:**

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

**Web — capture Playwright screenshots on every PR:**

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

The Action accepts a `subcommand` input matching the CLI verb (`capture-screenshots`, `capture-evidence`, `capture-pr`, `capture-web`, `resize`, `render-marketing`, `record-preview`, `upload-screenshots`) along with passthrough inputs for `config`, `ticket`, `output-dir`, and `extra-args`. For `capture-pr`, use `plan` plus optional `pr`, `before-ref`, `after-ref`, `keep-worktrees`, and `summary-only`; pull request workflows default `pr`, `before-ref`, and `after-ref` from the GitHub event. Set `comment-on-pr: 'true'` and pass `github-token` to have the Action post a PR comment: standard captures list artifacts, while `capture-pr` summarizes `report.md` with status, before/after SHAs, artifact count, and the report path. The comment step is automatically skipped when no token is supplied or when the workflow does not run on a `pull_request` event.

The `platform` input selects the capture mode: `ios` (default) for iOS simulator captures on macOS runners, or `web` for Playwright Chromium screenshots on any runner (including `ubuntu-latest`). When `platform: web`, Node.js 20 and the Playwright Chromium browser are installed and cached automatically.

ImageMagick and ffmpeg are installed and cached the first time the Action runs on an iOS runner, so warm runs reuse the formula tarballs. The `evidence` CLI itself is built once per release ref and cached under `~/runner.temp/evidence-build/.build`.

Four ready-to-copy workflows live under [`Examples/workflows/`](Examples/workflows/):

- `capture-evidence-on-pr.yml` — captures a screenshot per pull request, posts it as a PR comment, and uploads it as an artifact.
- `capture-pr-on-pr.yml` — captures before/after PR evidence, posts a concise report comment, and uploads the evidence bundle as an artifact.
- `capture-screenshots-on-tag.yml` — captures the full App Store screenshot matrix when you push a release tag.
- `capture-web-on-pr.yml` — starts a local HTTP server and captures Playwright web screenshots on every PR, posting a comment with the results.

Marketplace listing: <https://github.com/marketplace/actions/evidence>. The iOS platform requires `macos-14` or newer; the web platform runs on any runner with Node.js available (including `ubuntu-latest`).

## Documentation

- `docs/troubleshooting.md` covers common simulator, permissions, dependency, and output-path problems.
- `docs/versioning.md` describes the v0.x stability policy and release-note expectations.
- `docs/launch/README.md` contains public launch materials: blog draft, social posts, demo script, HN draft, and checklist.
- `CONTRIBUTING.md` explains how to report issues and open pull requests safely in a public repository.
- `Examples/README.md` describes the shipped GitHub Action examples and fixture project.

## Development

```sh
swift test
swift run evidence -- --help
```

## License

MIT. See `LICENSE`.
