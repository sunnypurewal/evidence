import Foundation

/// Resolves where captured evidence should be written.
public struct OutputDirectory: Equatable {
    public var explicitURL: URL?
    public var environment: [String: String]
    public var fallbackURL: URL

    public init(
        explicitURL: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fallbackURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("EvidenceOutput", isDirectory: true)
    ) {
        self.explicitURL = explicitURL
        self.environment = environment
        self.fallbackURL = fallbackURL
    }

    public var resolvedURL: URL {
        if let explicitURL {
            return explicitURL
        }

        if let path = environment["EVIDENCE_OUTPUT_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }

        if let path = environment["APPSTORE_SCREENSHOT_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }

        return fallbackURL
    }
}
