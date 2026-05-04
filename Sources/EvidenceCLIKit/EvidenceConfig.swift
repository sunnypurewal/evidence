import Foundation

/// The target platform for evidence capture.
///
/// Defaults to `.ios` for full backward compatibility. Set `platform = "web"`
/// in `.evidence.toml` to enable the web capture path, which requires
/// `web_url` and `web_viewports` and recognises the optional `web_full_page`
/// and `web_wait_until` keys.
public enum Platform: String, Equatable {
    case ios = "ios"
    case web = "web"
}

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
    public var appStoreConnect: AppStoreConnectConfig?
    public var platform: Platform
    public var webConfig: WebConfig?

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
        appStoreConnect: AppStoreConnectConfig? = nil,
        platform: Platform = .ios,
        webConfig: WebConfig? = nil
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
        self.appStoreConnect = appStoreConnect
        self.platform = platform
        self.webConfig = webConfig
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

        // Platform parsing
        let platformRaw = try document.optionalString("platform", allowEmpty: false)
        let platform: Platform
        if let raw = platformRaw {
            guard let parsed = Platform(rawValue: raw) else {
                throw CLIError.config("Invalid field 'platform': unknown value '\(raw)'. Accepted values: ios, web.")
            }
            platform = parsed
        } else {
            platform = .ios
        }

        // Web config (parsed only when platform == .web)
        let webConfig: WebConfig?
        if platform == .web {
            webConfig = try WebConfig.parse(document)
        } else {
            webConfig = nil
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
            appStoreConnect: try AppStoreConnectConfig.parse(document),
            platform: platform,
            webConfig: webConfig
        )
    }
}

/// Configuration for the web capture path (`platform = "web"`).
///
/// Keys are flat in `.evidence.toml` (prefixed `web_`) rather than a nested
/// table, matching the project's intentionally line-based TOML parser.
public struct WebConfig: Equatable {
    /// The URL to capture. Required when `platform = "web"`.
    public var url: String
    /// Viewport presets or custom `WxH` strings (e.g. `"1280x800"`).
    /// Named presets: `"desktop-1440"`, `"mobile-390"`. Required when `platform = "web"`.
    public var viewports: [String]
    /// When `true` (the default), capture the full page height rather than
    /// just the visible viewport.
    public var fullPage: Bool
    /// The Puppeteer/Playwright wait-until event. One of `"networkidle"`,
    /// `"load"`, `"domcontentloaded"`. Defaults to `"networkidle"`.
    public var waitUntil: String

    public static let namedViewports: Set<String> = ["desktop-1440", "mobile-390"]
    public static let validWaitUntilValues: [String] = ["networkidle", "load", "domcontentloaded"]

    public init(url: String, viewports: [String], fullPage: Bool = true, waitUntil: String = "networkidle") {
        self.url = url
        self.viewports = viewports
        self.fullPage = fullPage
        self.waitUntil = waitUntil
    }

    public static func parse(_ document: TOMLDocument) throws -> WebConfig {
        guard let url = try document.optionalString("web_url", allowEmpty: false) else {
            throw CLIError.config("Missing required field 'web_url' when platform = \"web\" in .evidence.toml.")
        }

        guard let viewports = try document.optionalStringArray("web_viewports", default: nil),
              !viewports.isEmpty else {
            throw CLIError.config("Missing required field 'web_viewports' when platform = \"web\" in .evidence.toml.")
        }

        // Validate each viewport entry
        let customViewportPattern = #"^\d+x\d+$"#
        for viewport in viewports {
            if !namedViewports.contains(viewport) {
                let isCustom = viewport.range(of: customViewportPattern, options: .regularExpression) != nil
                if !isCustom {
                    throw CLIError.config("Invalid field 'web_viewports': unknown viewport '\(viewport)'. Named presets: \(namedViewports.sorted().joined(separator: ", ")). Custom format: WxH (e.g. \"1280x800\").")
                }
            }
        }

        let fullPage = try document.optionalBool("web_full_page", default: true) ?? true

        let waitUntil = try document.optionalString("web_wait_until", default: "networkidle", allowEmpty: false) ?? "networkidle"
        if !validWaitUntilValues.contains(waitUntil) {
            throw CLIError.config("Invalid field 'web_wait_until': unknown value '\(waitUntil)'. Accepted values: \(validWaitUntilValues.joined(separator: ", ")).")
        }

        return WebConfig(url: url, viewports: viewports, fullPage: fullPage, waitUntil: waitUntil)
    }
}

public struct AppStoreConnectConfig: Equatable {
    public var keyID: String
    public var issuerID: String
    public var p8Path: String
    public var appID: String

    public init(keyID: String, issuerID: String, p8Path: String, appID: String) {
        self.keyID = keyID
        self.issuerID = issuerID
        self.p8Path = p8Path
        self.appID = appID
    }

    public static func parse(_ document: TOMLDocument) throws -> AppStoreConnectConfig? {
        let keyPrefix = "app_store_connect."
        let legacyPrefix = "app_store_connect_"
        let tablePresent = document.string(keyPrefix + "key_id") != nil
            || document.string(keyPrefix + "issuer_id") != nil
            || document.string(keyPrefix + "p8_path") != nil
            || document.string(keyPrefix + "app_id") != nil
        let legacyPresent = document.string(legacyPrefix + "key_id") != nil
            || document.string(legacyPrefix + "issuer_id") != nil
            || document.string(legacyPrefix + "p8_path") != nil
            || document.string(legacyPrefix + "app_id") != nil
        guard tablePresent || legacyPresent else {
            return nil
        }

        let prefix = tablePresent ? keyPrefix : legacyPrefix
        return AppStoreConnectConfig(
            keyID: try document.requiredString(prefix + "key_id"),
            issuerID: try document.requiredString(prefix + "issuer_id"),
            p8Path: try document.requiredString(prefix + "p8_path"),
            appID: try document.requiredString(prefix + "app_id")
        )
    }
}

/// Controls whether `capture-evidence` also produces an `.xcresult` bundle and
/// markdown summary alongside the screenshot.
///
/// The `.evidence.toml` keys are flat (`xcresult_enabled`,
/// `xcresult_keep_full_bundle`) rather than a `[xcresult]` table because the
/// project's TOML parser is intentionally line-based (no nested tables). The
/// behaviour matches the table-form description: setting
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
