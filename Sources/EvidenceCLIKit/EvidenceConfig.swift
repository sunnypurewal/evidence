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
    public var previewDefaults: PreviewDefaults

    public init(
        scheme: String,
        bundleID: String,
        simulatorUDID: String,
        evidenceDirectory: String = "docs/build-evidence",
        screenshotTargets: [ScreenshotTarget] = ScreenshotTarget.knownAppStoreTargets,
        previewTargets: [String] = ["app-preview"],
        deviceMatrix: [String] = [],
        repositoryRawBaseURL: String? = nil,
        previewDefaults: PreviewDefaults = PreviewDefaults()
    ) {
        self.scheme = scheme
        self.bundleID = bundleID
        self.simulatorUDID = simulatorUDID
        self.evidenceDirectory = evidenceDirectory
        self.screenshotTargets = screenshotTargets
        self.previewTargets = previewTargets
        self.deviceMatrix = deviceMatrix
        self.repositoryRawBaseURL = repositoryRawBaseURL
        self.previewDefaults = previewDefaults
    }

    public static func load(from url: URL) throws -> EvidenceConfig {
        let document = try TOMLDocument(contentsOf: url)
        return try parse(document)
    }

    public static func parse(_ document: TOMLDocument) throws -> EvidenceConfig {
        let scheme = try document.requiredString("scheme")
        let bundleID = try document.requiredString("bundle_id")
        let simulatorUDID = try document.requiredString("simulator_udid")
        let evidenceDirectory = document.string("evidence_dir") ?? "docs/build-evidence"
        let screenshotTargetNames = document.stringArray("screenshot_targets") ?? ScreenshotTarget.knownAppStoreTargets.map(\.name)
        let screenshotTargets = try screenshotTargetNames.map { name in
            guard let target = ScreenshotTarget(named: name) else {
                throw CLIError.config("Invalid field 'screenshot_targets': unknown target '\(name)'. Known targets: \(ScreenshotTarget.knownAppStoreTargets.map(\.name).joined(separator: ", ")).")
            }
            return target
        }

        return EvidenceConfig(
            scheme: scheme,
            bundleID: bundleID,
            simulatorUDID: simulatorUDID,
            evidenceDirectory: evidenceDirectory,
            screenshotTargets: screenshotTargets,
            previewTargets: document.stringArray("preview_targets") ?? ["app-preview"],
            deviceMatrix: document.stringArray("device_matrix") ?? [],
            repositoryRawBaseURL: document.string("repository_raw_base_url"),
            previewDefaults: PreviewDefaults(
                width: document.int("preview_width") ?? 886,
                height: document.int("preview_height") ?? 1920,
                fps: document.int("preview_fps") ?? 30,
                maxDuration: document.double("preview_max_duration_seconds") ?? 30,
                trimStart: document.double("preview_trim_start") ?? 0,
                trimEnd: document.double("preview_trim_end")
            )
        )
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
