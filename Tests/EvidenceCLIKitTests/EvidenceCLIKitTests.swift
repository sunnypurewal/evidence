import EvidenceCLIKit
import Foundation
import XCTest

final class EvidenceCLIKitTests: XCTestCase {
    func testConfigParsingRequiresNamedFields() throws {
        let document = try TOMLDocument.parse("""
        scheme = "Example"
        simulator_udid = "SIM-123"
        """)

        XCTAssertThrowsError(try EvidenceConfig.parse(document)) { error in
            XCTAssertEqual(
                error as? CLIError,
                .config("Missing required field 'bundle_id' in .evidence.toml.")
            )
        }
    }

    func testConfigParsingSupportsKnownTargetsAndPreviewDefaults() throws {
        let document = try TOMLDocument.parse("""
        scheme = "Example"
        bundle_id = "com.example.app"
        simulator_udid = "SIM-123"
        evidence_dir = "docs/proof"
        screenshot_targets = ["6.9", "5.5", "ipad-13"]
        preview_targets = ["app-preview"]
        device_matrix = ["iPhone 16 Pro Max", "iPad Pro 13-inch"]
        repository_raw_base_url = "https://raw.githubusercontent.com/example/app/main"
        preview_width = 886
        preview_height = 1920
        preview_fps = 30
        preview_max_duration_seconds = 28
        """)

        let config = try EvidenceConfig.parse(document)

        XCTAssertEqual(config.scheme, "Example")
        XCTAssertEqual(config.bundleID, "com.example.app")
        XCTAssertEqual(config.simulatorUDID, "SIM-123")
        XCTAssertEqual(config.evidenceDirectory, "docs/proof")
        XCTAssertEqual(config.screenshotTargets.map(\.name), ["6.9", "5.5", "ipad-13"])
        XCTAssertEqual(config.deviceMatrix, ["iPhone 16 Pro Max", "iPad Pro 13-inch"])
        XCTAssertEqual(config.previewDefaults, PreviewDefaults(width: 886, height: 1920, fps: 30, maxDuration: 28))
    }

    func testConfigParsingRejectsInvalidOptionalFieldTypes() throws {
        let document = try TOMLDocument.parse("""
        scheme = "Example"
        bundle_id = "com.example.app"
        simulator_udid = "SIM-123"
        preview_width = "wide"
        """)

        XCTAssertThrowsError(try EvidenceConfig.parse(document)) { error in
            XCTAssertEqual(
                error as? CLIError,
                .config("Invalid field 'preview_width': expected integer.")
            )
        }
    }

    func testConfigParsingRejectsInvalidOptionalFieldValues() throws {
        let document = try TOMLDocument.parse("""
        scheme = "Example"
        bundle_id = "com.example.app"
        simulator_udid = "SIM-123"
        preview_fps = 0
        """)

        XCTAssertThrowsError(try EvidenceConfig.parse(document)) { error in
            XCTAssertEqual(
                error as? CLIError,
                .config("Invalid field 'preview_fps': expected value >= 1.")
            )
        }
    }

    func testHelpDoesNotRequireConfig() throws {
        var output: [String] = []
        let cli = EvidenceCLI(stdout: { output.append($0) }, currentDirectory: temporaryDirectory())

        try cli.execute(["record-preview", "--help"])

        XCTAssertTrue(output.joined().contains("886x1920, 30fps, <=30s"))
    }

    func testResizeBuildsImageMagickCommandForAppStoreTargets() throws {
        let directory = try configuredProject()
        let runner = RecordingRunner()
        let cli = testCLI(directory: directory, runner: runner)

        try cli.execute(["resize", "--input", "raw.png", "--target", "6.9", "--output", "store.png"])

        XCTAssertEqual(runner.commands.last?.executable, "/bin/echo")
        XCTAssertEqual(
            runner.commands.last?.arguments,
            ["raw.png", "-resize", "1290x2796^", "-gravity", "center", "-extent", "1290x2796", "store.png"]
        )
    }

    func testRecordPreviewBuildsH264NoAudioCommandWithDefaults() throws {
        let directory = try configuredProject()
        let runner = RecordingRunner()
        let cli = testCLI(directory: directory, runner: runner)

        try cli.execute(["record-preview", "--input", "capture.mov", "--output", "preview.mp4"])

        XCTAssertEqual(
            runner.commands.last?.arguments,
            [
                "-y",
                "-i", "capture.mov",
                "-an",
                "-t", "30.0",
                "-vf", "scale=886:1920,fps=30",
                "-c:v", "libx264",
                "-pix_fmt", "yuv420p",
                "preview.mp4"
            ]
        )
    }

    func testRecordPreviewSupportsTrimOptions() throws {
        let directory = try configuredProject()
        let runner = RecordingRunner()
        let cli = testCLI(directory: directory, runner: runner)

        try cli.execute([
            "record-preview",
            "--input", "capture.mov",
            "--output", "preview.mp4",
            "--trim-start", "1.5",
            "--trim-end", "12"
        ])

        XCTAssertEqual(
            runner.commands.last?.arguments,
            [
                "-y",
                "-ss", "1.5",
                "-i", "capture.mov",
                "-an",
                "-t", "30.0",
                "-to", "12.0",
                "-vf", "scale=886:1920,fps=30",
                "-c:v", "libx264",
                "-pix_fmt", "yuv420p",
                "preview.mp4"
            ]
        )
    }

    func testCaptureEvidenceWritesConfiguredPathAndPrintsMarkdownURL() throws {
        let directory = try configuredProject(rawBaseURL: "https://raw.githubusercontent.com/example/app/main")
        let runner = RecordingRunner(createScreenshotForSimctl: true)
        var output: [String] = []
        let cli = testCLI(directory: directory, runner: runner, stdout: { output.append($0) })

        try cli.execute(["capture-evidence", "--ticket", "APP-123"])

        let screenshot = directory.appendingPathComponent("docs/build-evidence/APP-123-running.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: screenshot.path))
        XCTAssertEqual(
            runner.commands.last?.arguments,
            ["simctl", "io", "SIM-123", "screenshot", screenshot.path]
        )
        XCTAssertEqual(
            output.last,
            "![Build evidence](https://raw.githubusercontent.com/example/app/main/docs/build-evidence/APP-123-running.png)"
        )
    }

    func testCaptureEvidenceInfersRawGitHubURLFromOriginRemote() throws {
        let directory = try configuredProject()
        let runner = RecordingRunner(
            createScreenshotForSimctl: true,
            gitRemote: "git@github.com:example/app.git\n"
        )
        var output: [String] = []
        let cli = testCLI(directory: directory, runner: runner, stdout: { output.append($0) })

        try cli.execute(["capture-evidence", "--ticket", "APP-456"])

        XCTAssertEqual(
            output.last,
            "![Build evidence](https://raw.githubusercontent.com/example/app/main/docs/build-evidence/APP-456-running.png)"
        )
    }

    private func configuredProject(rawBaseURL: String? = nil) throws -> URL {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var lines = [
            "scheme = \"Example\"",
            "bundle_id = \"com.example.app\"",
            "simulator_udid = \"SIM-123\""
        ]
        if let rawBaseURL {
            lines.append("repository_raw_base_url = \"\(rawBaseURL)\"")
        }
        try lines.joined(separator: "\n").write(
            to: directory.appendingPathComponent(".evidence.toml"),
            atomically: true,
            encoding: .utf8
        )
        return directory
    }

    private func testCLI(
        directory: URL,
        runner: RecordingRunner,
        stdout: @escaping (String) -> Void = { _ in }
    ) -> EvidenceCLI {
        EvidenceCLI(
            runner: runner,
            stdout: stdout,
            currentDirectory: directory,
            toolPaths: ToolPaths(xcrun: "/bin/echo", magick: "/bin/echo", ffmpeg: "/bin/echo", git: "/bin/echo")
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

private final class RecordingRunner: CommandRunning {
    struct Command: Equatable {
        var executable: String
        var arguments: [String]
    }

    var commands: [Command] = []
    var createScreenshotForSimctl: Bool
    var gitRemote: String?

    init(createScreenshotForSimctl: Bool = false, gitRemote: String? = nil) {
        self.createScreenshotForSimctl = createScreenshotForSimctl
        self.gitRemote = gitRemote
    }

    func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
        commands.append(Command(executable: executable, arguments: arguments))

        if createScreenshotForSimctl, arguments.starts(with: ["simctl", "io"]) {
            let outputPath = arguments[4]
            try Data("png".utf8).write(to: URL(fileURLWithPath: outputPath))
        }

        if arguments == ["remote", "get-url", "origin"], let gitRemote {
            return CommandResult(exitCode: 0, stdout: gitRemote)
        }

        return CommandResult(exitCode: 0)
    }
}
