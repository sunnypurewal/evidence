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
      upload-screenshots    Upload screenshots to App Store Connect.
      capture-web           Capture full-page Playwright screenshots at configured viewport sizes.

    Configuration:
      Commands read .evidence.toml from the current directory. Required fields:
      scheme, bundle_id, simulator_udid.

    Examples:
      evidence capture-evidence --ticket APP-123
      evidence resize --input raw.png --target 6.9 --output app-store.png
      evidence upload-screenshots --dry-run
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

    public static let uploadScreenshots = """
    evidence upload-screenshots [--dry-run] [--locale en-US]

    Uploads PNG screenshots from evidence_dir to App Store Connect screenshot
    slots for the configured app. The command accepts either the default
    layout:

      <evidence_dir>/<device-target>/<index>.png

    or a per-locale layout:

      <evidence_dir>/<locale>/<device-target>/<index>.png

    Required .evidence.toml table:

      [app_store_connect]
      key_id = "ABC123DEFG"
      issuer_id = "00000000-0000-0000-0000-000000000000"
      p8_path = ".secrets/AuthKey_ABC123DEFG.p8"
      app_id = "1234567890"

    `--dry-run` validates dimensions and prints every slot that would be
    created, replaced, or skipped without mutating App Store Connect.

    Example:
      evidence upload-screenshots --dry-run
      evidence upload-screenshots --locale en-US
    """

    public static let captureWeb = """
    evidence capture-web [--comment-on-pr true] [--github-token <token>]

    Captures full-page web screenshots at each configured viewport using Playwright.

    Requires platform = "web" in .evidence.toml plus:
      web_url          = "https://example.com"
      web_viewports    = ["desktop-1440", "mobile-390"]

    Named viewport presets:
      desktop-1440  -> 1440x900
      mobile-390    -> 390x844
      Custom WxH strings (e.g. "1280x800") are also accepted.

    Optional:
      web_full_page   = true           (default true)
      web_wait_until  = "networkidle"  (default networkidle)

    Output: <evidence_dir>/<viewport-name>/<page-slug>.png

    PR comment flags:
      --comment-on-pr true   Post a markdown comment with inline viewport screenshots
                             to the open GitHub PR. Requires GITHUB_TOKEN env var or
                             --github-token. When omitted, the comment body is printed
                             to stdout (dry-run mode).
      --github-token <token> GitHub token to use instead of GITHUB_TOKEN env var.

    Requires:
      node (with playwright installed: npm install playwright)

    Example:
      evidence capture-web
      evidence capture-web --comment-on-pr true
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
        case "upload-screenshots":
            uploadScreenshots
        case "capture-web":
            captureWeb
        default:
            throw CLIError.usage("Unknown command '\(command)'. Run `evidence --help`.")
        }
    }
}
