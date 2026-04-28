import Foundation

public struct EvidenceConfig: Equatable {
    public var scheme: String
    public var bundleID: String
    public var simulatorUDID: String
    public var evidenceDirectory: String
    public var screenshotTargets: [ScreenshotTarget]
    public var previewTargets: [String]
    public var deviceMatrix: [String]
    public var repositoryRawBaseURL: String?
    public var xcodeWorkspace: String?
    public var xcodeProject: String?
    public var previewDefaults: PreviewDefaults
    public var xcresult: XcresultConfig
    public var diff: DiffConfig

    public init(
        scheme: String,
        bundleID: String,
        simulatorUDID: String,
        evidenceDirectory: String = "docs/build-evidence",
        screenshotTargets: [ScreenshotTarget] = ScreenshotTarget.knownAppStoreTargets,
        previewTargets: [String] = ["app-preview"],
        deviceMatrix: [String] = [],
        repositoryRawBaseURL: String? = nil,
        xcodeWorkspace: String? = nil,
        xcodeProject: String? = nil,
        previewDefaults: PreviewDefaults = PreviewDefaults(),
        xcresult: XcresultConfig = XcresultConfig(),
        diff: DiffConfig = DiffConfig()
    ) {
        self.scheme = scheme
        self.bundleID = bundleID
        self.simulatorUDID = simulatorUDID
        self.evidenceDirectory = evidenceDirectory
        self.screenshotTargets = screenshotTargets
        self.previewTargets = previewTargets
        self.deviceMatrix = deviceMatrix
        self.repositoryRawBaseURL = repositoryRawBaseURL
        self.xcodeWorkspace = xcodeWorkspace
        self.xcodeProject = xcodeProject
        self.previewDefaults = previewDefaults
        self.xcresult = xcresult
        self.diff = diff
    }

    public static func load(from url: URL) throws -> EvidenceConfig {
        let document = try TOMLDocument(contentsOf: url)
        return try parse(document)
    }

    public static func parse(_ document: TOMLDocument) throws -> EvidenceConfig {
        let scheme = try document.requiredString("scheme")
        let bundleID = try document.requiredString("bundle_id")
        let simulatorUDID = try document.requiredString("simulator_udid")
        let evidenceDirectory = try document.optionalString("evidence_dir", default: "docs/build-evidence", allowEmpty: false) ?? "docs/build-evidence"
        let screenshotTargetNames = try document.optionalStringArray(
            "screenshot_targets",
            default: ScreenshotTarget.knownAppStoreTargets.map(\.name)
        ) ?? ScreenshotTarget.knownAppStoreTargets.map(\.name)
        let screenshotTargets = try screenshotTargetNames.map { name in
            guard let target = ScreenshotTarget(named: name) else {
                throw CLIError.config("Invalid field 'screenshot_targets': unknown target '\(name)'. Known targets: \(ScreenshotTarget.knownAppStoreTargets.map(\.name).joined(separator: ", ")).")
            }
            return target
        }

        let xcodeWorkspace = try document.optionalString("xcode_workspace", allowEmpty: false)
        let xcodeProject = try document.optionalString("xcode_project", allowEmpty: false)
        if xcodeWorkspace != nil, xcodeProject != nil {
            throw CLIError.config("Invalid configuration: only one of 'xcode_workspace' or 'xcode_project' may be set in .evidence.toml.")
        }

        return EvidenceConfig(
            scheme: scheme,
            bundleID: bundleID,
            simulatorUDID: simulatorUDID,
            evidenceDirectory: evidenceDirectory,
            screenshotTargets: screenshotTargets,
            previewTargets: try document.optionalStringArray("preview_targets", default: ["app-preview"]) ?? ["app-preview"],
            deviceMatrix: try document.optionalStringArray("device_matrix", default: []) ?? [],
            repositoryRawBaseURL: try document.optionalString("repository_raw_base_url", allowEmpty: false),
            xcodeWorkspace: xcodeWorkspace,
            xcodeProject: xcodeProject,
            previewDefaults: PreviewDefaults(
                width: try document.optionalInt("preview_width", default: 886, minimum: 1) ?? 886,
                height: try document.optionalInt("preview_height", default: 1920, minimum: 1) ?? 1920,
                fps: try document.optionalInt("preview_fps", default: 30, minimum: 1) ?? 30,
                maxDuration: try document.optionalDouble("preview_max_duration_seconds", default: 30, minimum: 0.1) ?? 30,
                trimStart: try document.optionalDouble("preview_trim_start", default: 0, minimum: 0) ?? 0,
                trimEnd: try document.optionalDouble("preview_trim_end", minimum: 0)
            ),
            xcresult: XcresultConfig(
                enabled: try document.optionalBool("xcresult_enabled", default: false) ?? false,
                keepFullBundle: try document.optionalBool("xcresult_keep_full_bundle", default: true) ?? true
            ),
            diff: DiffConfig(
                threshold: try document.optionalDouble("diff_threshold", default: 0.001, minimum: 0) ?? 0.001,
                ignoreRegions: try DiffConfig.parseRegions(
                    document.optionalStringArray("diff_ignore_regions", default: []) ?? []
                ),
                baselineDirectory: try document.optionalString(
                    "diff_baseline_dir",
                    default: "docs/baselines",
                    allowEmpty: false
                ) ?? "docs/baselines",
                acceptAllowDirty: try document.optionalBool("diff_accept_allow_dirty", default: false) ?? false,
                fuzzPercent: try document.optionalDouble("diff_fuzz_percent", default: 0, minimum: 0) ?? 0
            )
        )
    }
}

/// Configuration for `evidence diff` and `evidence accept-baseline`.
///
/// All keys are flat to match the project's line-based TOML parser (no nested
/// tables). The conceptual `[diff]` table from the epic description maps to
/// keys with a `diff_` prefix.
///
/// - `diff_threshold`: maximum fraction of pixels (0.0–1.0) that may differ
///   between baseline and current capture before the run is considered a
///   regression. Defaults to `0.001` (one tenth of one percent), which absorbs
///   sub-pixel renderer noise without hiding real drift.
/// - `diff_ignore_regions`: rectangles to mask (fill black) on both images
///   before comparison. Format: `"X,Y,WxH"` per entry, in pixel units of the
///   captured image. Use this for clocks, timestamps, or any deliberately
///   non-deterministic UI element.
/// - `diff_baseline_dir`: where committed baselines live in the consumer
///   repo. Per-device paths are nested under this root.
/// - `diff_accept_allow_dirty`: when `true`, `evidence accept-baseline` will
///   overwrite baselines even if `git status --porcelain` reports uncommitted
///   changes. Defaults to `false` so a stray local edit can't silently
///   contaminate baselines.
/// - `diff_fuzz_percent`: per-pixel color tolerance forwarded to
///   `magick compare -fuzz`. Tiny values (0–5%) absorb antialiasing noise on
///   font edges. Defaults to `0` (exact-match per pixel; the threshold
///   absorbs the noise budget at the image level instead).
public struct DiffConfig: Equatable {
    public var threshold: Double
    public var ignoreRegions: [DiffRegion]
    public var baselineDirectory: String
    public var acceptAllowDirty: Bool
    public var fuzzPercent: Double

    public init(
        threshold: Double = 0.001,
        ignoreRegions: [DiffRegion] = [],
        baselineDirectory: String = "docs/baselines",
        acceptAllowDirty: Bool = false,
        fuzzPercent: Double = 0
    ) {
        self.threshold = threshold
        self.ignoreRegions = ignoreRegions
        self.baselineDirectory = baselineDirectory
        self.acceptAllowDirty = acceptAllowDirty
        self.fuzzPercent = fuzzPercent
    }

    /// Parse `["X,Y,WxH", ...]` into structured regions.
    /// Surface a config error on the first malformed entry rather than
    /// silently dropping it, since dropping an ignore region tends to flip a
    /// run from green to red without an obvious cause.
    public static func parseRegions(_ raw: [String]) throws -> [DiffRegion] {
        try raw.map { entry in
            guard let region = DiffRegion(string: entry) else {
                throw CLIError.config("Invalid field 'diff_ignore_regions': '\(entry)' is not in 'X,Y,WxH' form (e.g. '0,0,200x100').")
            }
            return region
        }
    }
}

/// A rectangle (in image pixels) to mask out before computing a visual diff.
public struct DiffRegion: Equatable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Parse the `"X,Y,WxH"` form. Returns `nil` for any malformed input so
    /// the caller can build a precise error message.
    public init?(string: String) {
        let parts = string.split(separator: ",")
        guard parts.count == 3,
              let x = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let y = Int(parts[1].trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        let dim = parts[2].trimmingCharacters(in: .whitespaces).split(separator: "x")
        guard dim.count == 2,
              let width = Int(dim[0]),
              let height = Int(dim[1]),
              width >= 0, height >= 0 else {
            return nil
        }
        self.init(x: x, y: y, width: width, height: height)
    }

    /// ImageMagick `-draw` argument for filling this region with black on a
    /// copy of the input image.
    public var magickDrawArgument: String {
        "rectangle \(x),\(y) \(x + width),\(y + height)"
    }
}

/// Controls whether `capture-evidence` also produces an `.xcresult` bundle and
/// markdown summary alongside the screenshot.
///
/// The `.evidence.toml` keys are flat (`xcresult_enabled`,
/// `xcresult_keep_full_bundle`) rather than a `[xcresult]` table because the
/// project's TOML parser is intentionally line-based (no nested tables). The
/// behaviour matches the table-form description in RIDDIM-33: setting
/// `xcresult_enabled = true` is equivalent to `[xcresult] enabled = true` and
/// `xcresult_keep_full_bundle` mirrors `keep_full_bundle`.
public struct XcresultConfig: Equatable {
    public var enabled: Bool
    public var keepFullBundle: Bool

    public init(enabled: Bool = false, keepFullBundle: Bool = true) {
        self.enabled = enabled
        self.keepFullBundle = keepFullBundle
    }
}

public struct PreviewDefaults: Equatable {
    public var width: Int
    public var height: Int
    public var fps: Int
    public var maxDuration: Double
    public var trimStart: Double
    public var trimEnd: Double?

    public init(
        width: Int = 886,
        height: Int = 1920,
        fps: Int = 30,
        maxDuration: Double = 30,
        trimStart: Double = 0,
        trimEnd: Double? = nil
    ) {
        self.width = width
        self.height = height
        self.fps = fps
        self.maxDuration = maxDuration
        self.trimStart = trimStart
        self.trimEnd = trimEnd
    }
}

public struct ScreenshotTarget: Equatable {
    public var name: String
    public var width: Int
    public var height: Int

    public static let knownAppStoreTargets = [
        ScreenshotTarget(name: "6.9", width: 1290, height: 2796),
        ScreenshotTarget(name: "6.5", width: 1242, height: 2688),
        ScreenshotTarget(name: "6.1", width: 1179, height: 2556),
        ScreenshotTarget(name: "5.5", width: 1242, height: 2208),
        ScreenshotTarget(name: "ipad-13", width: 2064, height: 2752),
        ScreenshotTarget(name: "ipad-12.9", width: 2048, height: 2732),
        ScreenshotTarget(name: "ipad-11", width: 1668, height: 2388)
    ]

    public init(name: String, width: Int, height: Int) {
        self.name = name
        self.width = width
        self.height = height
    }

    public init?(named name: String) {
        guard let target = Self.knownAppStoreTargets.first(where: { $0.name == name }) else {
            return nil
        }
        self = target
    }
}
