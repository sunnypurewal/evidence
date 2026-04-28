import Foundation
import XCTest

/// A declarative sequence of app states to prove and capture.
public struct ScreenshotPlan {
    public var name: String
    public var launchHook: LaunchHook
    public var scenes: [Scene]
    public var outputDirectory: OutputDirectory
    public var anchorTimeout: TimeInterval

    public init(
        name: String,
        launchHook: LaunchHook = .none,
        scenes: [Scene],
        outputDirectory: OutputDirectory = OutputDirectory(),
        anchorTimeout: TimeInterval = 10
    ) {
        self.name = name
        self.launchHook = launchHook
        self.scenes = scenes
        self.outputDirectory = outputDirectory
        self.anchorTimeout = anchorTimeout
    }

    @discardableResult
    public func run(on app: XCUIApplication = XCUIApplication()) throws -> [URL] {
        try run(on: app as EvidenceApplication)
    }

    @discardableResult
    public func run(on app: EvidenceApplication) throws -> [URL] {
        var app = app
        app.apply(launchHook)
        app.launch()

        var writtenFiles: [URL] = []
        for scene in scenes {
            let fileURL = try scene.capture(
                in: app,
                outputDirectory: outputDirectory.resolvedURL,
                timeout: anchorTimeout
            )
            writtenFiles.append(fileURL)

            for action in scene.navigation {
                try action.perform(in: app)
            }
        }
        return writtenFiles
    }
}

public extension ScreenshotPlan {
    /// A scene is one captured app state plus the navigation needed to leave it.
    struct Scene {
        public var name: String
        public var anchors: [PlanAnchor]
        public var navigation: [NavigationAction]
        public var captureName: String

        public init(
            name: String,
            anchors: [PlanAnchor],
            navigation: [NavigationAction] = [],
            captureName: String? = nil
        ) {
            self.name = name
            self.anchors = anchors
            self.navigation = navigation
            self.captureName = captureName ?? Self.fileSafeName(for: name)
        }

        func capture(
            in app: EvidenceApplication,
            outputDirectory: URL,
            timeout: TimeInterval
        ) throws -> URL {
            for anchor in anchors {
                guard anchor.wait(in: app, timeout: timeout) else {
                    throw EvidenceError.anchorTimedOut(
                        scene: name,
                        anchor: anchor.description,
                        timeout: timeout
                    )
                }
            }

            let fileURL = outputDirectory.appendingPathComponent("\(captureName).png")
            try app.captureScreenshot().write(to: fileURL)
            return fileURL
        }

        static func fileSafeName(for name: String) -> String {
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
            let scalars = name.unicodeScalars.map { scalar in
                allowed.contains(scalar) ? Character(scalar) : "-"
            }
            let collapsed = String(scalars)
                .split(separator: "-", omittingEmptySubsequences: true)
                .joined(separator: "-")
                .lowercased()
            return collapsed.isEmpty ? "scene" : collapsed
        }
    }
}
