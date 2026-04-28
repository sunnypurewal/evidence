public enum Help {
    public static let root = """
    evidence

    Capture repeatable app evidence from real iOS app flows.

    Usage:
      evidence <command> [options]

    Commands:
      capture-screenshots   Run the configured UI test screenshot workflow.
      resize                Resize screenshots to App Store target dimensions.
      render-marketing      Render a marketing screenshot from a scene file.
      record-preview        Encode an App Preview-compatible video.
      capture-evidence      Capture a one-shot build evidence screenshot.
      diff                  Compare current captures against committed baselines.
      accept-baseline       Promote the latest run into the baseline directory.

    Configuration:
      Commands read .evidence.toml from the current directory. Required fields:
      scheme, bundle_id, simulator_udid.

    Examples:
      evidence capture-evidence --ticket APP-123
      evidence resize --input raw.png --target 6.9 --output app-store.png
      evidence diff --baseline docs/baselines --markdown docs/build-evidence/diff.md
    """

    public static let captureScreenshots = """
    evidence capture-screenshots

    Runs the configured UI test workflow using Xcode simulator tooling.

    Requires .evidence.toml fields:
      scheme, bundle_id, simulator_udid

    Optional .evidence.toml fields for apps whose Xcode workspace or project is
    not at the directory where `evidence` runs:
      xcode_workspace = "ios/MyApp.xcworkspace"
      xcode_project   = "ios/MyApp.xcodeproj"

    Set at most one of the two — the value is forwarded to `xcodebuild` as
    `-workspace` or `-project`.

    Example:
      evidence capture-screenshots
    """

    public static let resize = """
    evidence resize --input <png> --target <size> --output <png>

    Resizes a screenshot to a known App Store target.

    Targets:
      6.9, 6.5, 6.1, 5.5, ipad-13, ipad-12.9, ipad-11

    Requires:
      ImageMagick `magick`

    Example:
      evidence resize --input raw.png --target 6.9 --output 6-9.png
    """

    public static let renderMarketing = """
    evidence render-marketing --scene <scene.json> --output <png> [--svg <svg>] [--target 6.9]

    Renders a marketing screenshot from a structured JSON scene file and writes
    both an intermediate SVG and final PNG.

    Requires:
      ImageMagick `magick`

    Example:
      evidence render-marketing --scene scene.json --svg scene.svg --output scene.png --target 6.9
    """

    public static let recordPreview = """
    evidence record-preview --input <mov> --output <mp4> [--trim-start 0] [--trim-end 30] [--duration 30] [--fps 30] [--width 886] [--height 1920]

    Encodes an App Preview-compatible H.264 MP4 with no audio.

    Defaults:
      886x1920, 30fps, <=30s

    Requires:
      ffmpeg

    Example:
      evidence record-preview --input capture.mov --output preview.mp4
    """

    public static let captureEvidence = """
    evidence capture-evidence --ticket <KEY> [--xcresult-summary-only]

    Captures a one-shot simulator screenshot into the configured evidence_dir.

    When `xcresult_enabled = true` is set in .evidence.toml, also runs
    `xcodebuild test` with `-resultBundlePath` and writes:

      <evidence_dir>/<KEY>.xcresult       (full structured test result)
      <evidence_dir>/<KEY>-tests.md       (markdown summary suitable for PR)

    Set `xcresult_keep_full_bundle = false` (or pass `--xcresult-summary-only`)
    to keep only the markdown summary in the evidence directory; the bundle is
    moved to `~/.evidence/cache/<KEY>.xcresult` for local inspection without
    bloating the repo.

    Output (default):
      docs/build-evidence/<KEY>-running.png unless evidence_dir is configured.

    Requires .evidence.toml fields:
      scheme, bundle_id, simulator_udid

    Example:
      evidence capture-evidence --ticket APP-123
      evidence capture-evidence --ticket APP-123 --xcresult-summary-only
    """

    public static let diff = """
    evidence diff [--baseline <dir>] [--current <dir>] [--output <dir>] [--report <path>] [--markdown <path>] [--threshold <number>]

    Compares the latest screenshot run against a directory of committed
    baselines and writes:

      <output>/<scene>.png            (per-scene diff PNG)
      <output>/diff-report.json       (structured report)

    Per-device baselines are matched by relative path: a current capture at
    `<evidence_dir>/iPhone 16/home.png` is compared against
    `<baseline>/iPhone 16/home.png`.

    Tolerance is read from `.evidence.toml` (`diff_threshold`, expressed as a
    fraction 0.0–1.0) and may be overridden with `--threshold`. Values >1 are
    treated as percent-style (e.g. `--threshold 5` => 0.05).

    Ignore regions are read from `.evidence.toml`:
      diff_ignore_regions = ["0,0,300x60", "0,2700,1290x96"]

    Each entry is `X,Y,WxH` in pixel units. Both the baseline and the current
    capture are masked black on those rectangles before comparison.

    Exit codes:
      0   every scene matched within threshold
      1   one or more scenes exceeded the threshold (regression)
      2   one or more expected scenes had no baseline image

    Requires:
      ImageMagick `magick`

    Example:
      evidence diff --baseline docs/baselines --markdown docs/build-evidence/diff.md
    """

    public static let acceptBaseline = """
    evidence accept-baseline [--source <dir>] [--baseline <dir>] [--force]

    Copies every PNG from the latest screenshot run into the baseline
    directory, replacing any existing image. Use this after intentional UI
    changes ship.

    Refuses to run when `git status --porcelain` reports uncommitted changes,
    since baselines are committed alongside the consumer's code. Override with
    `--force` or set `diff_accept_allow_dirty = true` in .evidence.toml.

    Defaults:
      --source     evidence_dir from .evidence.toml
      --baseline   diff_baseline_dir from .evidence.toml (default docs/baselines)

    Example:
      evidence accept-baseline
    """

    public static func text(for command: String) throws -> String {
        switch command {
        case "capture-screenshots":
            captureScreenshots
        case "resize":
            resize
        case "render-marketing":
            renderMarketing
        case "record-preview":
            recordPreview
        case "capture-evidence":
            captureEvidence
        case "diff":
            diff
        case "accept-baseline":
            acceptBaseline
        default:
            throw CLIError.usage("Unknown command '\(command)'. Run `evidence --help`.")
        }
    }
}
