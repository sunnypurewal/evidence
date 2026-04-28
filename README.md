# evidence

[![swift-test](https://github.com/sunnypurewal/evidence/actions/workflows/swift-test.yml/badge.svg?branch=main)](https://github.com/sunnypurewal/evidence/actions/workflows/swift-test.yml)
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

### Visual regression

`evidence diff` compares the latest screenshot run against a directory of committed baselines and fails CI when a screen drifts unexpectedly. It reuses the same `device_matrix` and `evidence_dir` your screenshot capture already emits — there is no separate snapshot-testing pipeline to maintain.

The minimum `.evidence.toml`:

```toml
diff_threshold = 0.001                              # 0.1% of pixels may differ
diff_baseline_dir = "docs/baselines"                # default
diff_ignore_regions = ["0,0,1290x60", "0,2700,1290x96"]
diff_fuzz_percent = 0                               # forwarded to `magick compare -fuzz`
diff_accept_allow_dirty = false                     # accept-baseline refuses dirty trees
```

Workflow:

```sh
# 1. capture the screen as usual
evidence capture-screenshots

# 2. compare against committed baselines
evidence diff --markdown docs/build-evidence/diff.md

# 3. once you've eyeballed the report and the drift is intentional:
evidence accept-baseline
git add docs/baselines && git commit -m "Lock in new baselines"
```

Per-device baselines fall out of relative-path matching: a current capture at `docs/build-evidence/iPhone 16/home.png` compares against `docs/baselines/iPhone 16/home.png`. Devices missing entirely from the baseline tree surface as `missing baseline` for every scene under that subtree.

Ignore regions are rectangles in pixel coordinates of the captured image, in the form `"X,Y,WxH"`. Both the baseline and the actual capture are masked black on those rectangles before comparison, so clocks, timestamps, and any deliberately non-deterministic UI element never trigger a false regression.

Exit codes:

| Code | Meaning |
| ---: | --- |
| 0 | every scene matched within `diff_threshold` |
| 1 | one or more scenes exceeded the threshold (regression) |
| 2 | one or more expected scenes had no baseline image |

The `--markdown` flag (or piping stdout through your CI's PR-comment step) emits a table that GitHub renders inline:

```markdown
## Visual regression report

**1 regression(s)** above the 0.100% threshold.

| Scene | Status | Differing pixels | Diff |
| --- | --- | ---: | --- |
| `iPhone 16/home` | regression | 5000 | ![diff](https://raw.githubusercontent.com/example/app/main/docs/build-evidence/diff/iPhone 16/home.png) |
| `iPhone 16/settings` | match | 0 | `docs/build-evidence/diff/iPhone 16/settings.png` |
```

The `diff-report.json` written next to the per-scene PNGs is the same data in machine-readable form. Use it to feed downstream dashboards or to gate non-PR workflows.

`evidence accept-baseline` refuses to run when `git status --porcelain` reports uncommitted changes, since baselines are committed alongside the consumer's code and a stray local edit silently flowing into `git add` would be the worst-case bug. Pass `--force` (or set `diff_accept_allow_dirty = true`) when you actually want to accept on a dirty tree.

Run the command that matches the workflow:

```sh
evidence capture-screenshots
evidence capture-evidence --ticket APP-123
evidence resize --input raw.png --target 6.9 --output app-store.png
evidence record-preview --input capture.mov --output preview.mp4 --trim-start 0 --trim-end 30
evidence render-marketing --scene scene.json --svg scene.svg --output scene.png
evidence diff --baseline docs/baselines --markdown docs/build-evidence/diff.md
evidence accept-baseline
evidence upload-screenshots --dry-run
```

The CLI wraps Xcode simulator tooling, ImageMagick, and ffmpeg with explicit checks so missing local dependencies fail with actionable messages.

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
      - uses: sunnypurewal/evidence@v0
        with:
          subcommand: upload-screenshots
          extra-args: '--dry-run'
```

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

The Action accepts a `subcommand` input matching the CLI verb (`capture-screenshots`, `capture-evidence`, `resize`, `render-marketing`, `record-preview`, `diff`, `upload-screenshots`) along with passthrough inputs for `config`, `ticket`, `baseline-dir`, `output-dir`, and `extra-args`. Set `comment-on-pr: 'true'` and pass `github-token` to have the Action post a PR comment listing every artifact produced by the run; the comment step is automatically skipped when no token is supplied or when the workflow does not run on a `pull_request` event.

ImageMagick and ffmpeg are installed and cached the first time the Action runs on a given runner, so warm runs reuse the formula tarballs. The `evidence` CLI itself is built once per release ref and cached under `~/runner.temp/evidence-build/.build`.

Two ready-to-copy workflows live under [`Examples/workflows/`](Examples/workflows/):

- `capture-evidence-on-pr.yml` — captures a screenshot per pull request, posts it as a PR comment, and uploads it as an artifact.
- `capture-screenshots-on-tag.yml` — captures the full App Store screenshot matrix when you push a release tag.

Marketplace listing: <https://github.com/marketplace/actions/evidence>. The Action only supports `macos-14` and newer hosted runners; self-hosted macOS runners and non-macOS runners are out of scope for v1.

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
