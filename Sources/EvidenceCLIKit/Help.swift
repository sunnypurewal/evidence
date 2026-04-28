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

    Configuration:
      Commands read .evidence.toml from the current directory. Required fields:
      scheme, bundle_id, simulator_udid.

    Examples:
      evidence capture-evidence --ticket APP-123
      evidence resize --input raw.png --target 6.9 --output app-store.png
    """

    public static let captureScreenshots = """
    evidence capture-screenshots

    Runs the configured UI test workflow using Xcode simulator tooling.

    Requires .evidence.toml fields:
      scheme, bundle_id, simulator_udid

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
    evidence render-marketing --scene <svg-or-image> --output <png>

    Renders a marketing screenshot through the configured renderer dependency.

    Requires:
      ImageMagick `magick`

    Example:
      evidence render-marketing --scene scene.svg --output scene.png
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
    evidence capture-evidence --ticket <KEY>

    Captures a one-shot simulator screenshot into the configured evidence_dir.

    Output:
      docs/build-evidence/<KEY>-running.png unless evidence_dir is configured.

    Requires .evidence.toml fields:
      scheme, bundle_id, simulator_udid

    Example:
      evidence capture-evidence --ticket APP-123
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
        default:
            throw CLIError.usage("Unknown command '\(command)'. Run `evidence --help`.")
        }
    }
}
