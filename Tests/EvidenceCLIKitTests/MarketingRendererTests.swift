import EvidenceCLIKit
import Foundation
import XCTest

final class MarketingRendererTests: XCTestCase {
    func testMarketingSceneParsesAllSupportedRows() throws {
        let scene = try MarketingScene.parse(sampleSceneJSON(), target: ScreenshotTarget(named: "6.9")!)

        XCTAssertEqual(scene.id, "launch")
        XCTAssertEqual(scene.width, 1290)
        XCTAssertEqual(scene.height, 2796)
        XCTAssertEqual(scene.rows.count, 8)
    }

    func testMarketingRendererWritesSVGAndBuildsPNGCommand() throws {
        let scene = try MarketingScene.parse(sampleSceneJSON(), target: ScreenshotTarget(named: "6.9")!)
        let directory = temporaryDirectory()
        let svg = directory.appendingPathComponent("scene.svg")
        let png = directory.appendingPathComponent("scene.png")
        let runner = MarketingRecordingRunner()
        let renderer = MarketingRenderer(runner: runner, toolPaths: ToolPaths(magick: "/bin/echo"))

        let svgText = try renderer.render(scene: scene, svgURL: svg, pngURL: png)

        XCTAssertTrue(FileManager.default.fileExists(atPath: svg.path))
        XCTAssertTrue(svgText.contains("<svg"))
        XCTAssertTrue(svgText.contains("Proof that your app works"))
        XCTAssertEqual(runner.commands.last?.arguments, [svg.path, png.path])
    }

    func testMarketingSceneValidationNamesInvalidSceneRowAndKey() throws {
        let json = try JSONSerialization.jsonObject(with: Data("""
        {
          "scenes": [
            {
              "id": "bad-scene",
              "headline": "Bad",
              "rows": [
                { "kind": "unknown" }
              ]
            }
          ]
        }
        """.utf8))

        XCTAssertThrowsError(try MarketingScene.parse(json, target: ScreenshotTarget(named: "6.9")!)) { error in
            XCTAssertEqual(
                error as? CLIError,
                .config("Invalid scene 'bad-scene' row 0 key 'kind': unknown row kind 'unknown'.")
            )
        }
    }

    func testMarketingSceneValidationRejectsUnsupportedKeys() throws {
        let json = try JSONSerialization.jsonObject(with: Data("""
        {
          "scenes": [
            {
              "id": "bad-scene",
              "headline": "Bad",
              "rows": [
                { "kind": "badge", "text": "Beta", "tracking_id": "unused" }
              ]
            }
          ]
        }
        """.utf8))

        XCTAssertThrowsError(try MarketingScene.parse(json, target: ScreenshotTarget(named: "6.9")!)) { error in
            XCTAssertEqual(
                error as? CLIError,
                .config("Invalid scene 'bad-scene' row 0 key 'tracking_id': unsupported key.")
            )
        }
    }

    func testRenderMarketingCommandLoadsSceneAndWritesIntermediateSVG() throws {
        let directory = try configuredProject()
        let scene = directory.appendingPathComponent("scene.json")
        try sampleSceneText().write(to: scene, atomically: true, encoding: .utf8)

        let runner = MarketingRecordingRunner()
        let cli = EvidenceCLI(
            runner: runner,
            stdout: { _ in },
            currentDirectory: directory,
            toolPaths: ToolPaths(magick: "/bin/echo")
        )

        try cli.execute([
            "render-marketing",
            "--scene", "scene.json",
            "--svg", "rendered.svg",
            "--output", "rendered.png",
            "--target", "6.9"
        ])

        let svg = directory.appendingPathComponent("rendered.svg")
        let png = directory.appendingPathComponent("rendered.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: svg.path))
        XCTAssertEqual(runner.commands.last?.arguments, [svg.path, png.path])
    }

    func testRenderMarketingCommandPreservesAbsoluteOutputPaths() throws {
        let directory = try configuredProject()
        let scene = directory.appendingPathComponent("scene.json")
        try sampleSceneText().write(to: scene, atomically: true, encoding: .utf8)

        let outputDirectory = temporaryDirectory()
        let svg = outputDirectory.appendingPathComponent("rendered.svg")
        let png = outputDirectory.appendingPathComponent("rendered.png")
        let runner = MarketingRecordingRunner()
        let cli = EvidenceCLI(
            runner: runner,
            stdout: { _ in },
            currentDirectory: directory,
            toolPaths: ToolPaths(magick: "/bin/echo")
        )

        try cli.execute([
            "render-marketing",
            "--scene", "scene.json",
            "--svg", svg.path,
            "--output", png.path,
            "--target", "6.9"
        ])

        XCTAssertTrue(FileManager.default.fileExists(atPath: svg.path))
        XCTAssertEqual(runner.commands.last?.arguments, [svg.path, png.path])
    }

    private func configuredProject() throws -> URL {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try """
        scheme = "Example"
        bundle_id = "com.example.app"
        simulator_udid = "SIM-123"
        """.write(
            to: directory.appendingPathComponent(".evidence.toml"),
            atomically: true,
            encoding: .utf8
        )
        return directory
    }

    private func sampleSceneJSON() throws -> Any {
        try JSONSerialization.jsonObject(with: Data(sampleSceneText().utf8))
    }

    private func sampleSceneText() -> String {
        """
        {
          "scenes": [
            {
              "id": "launch",
              "width": 1290,
              "height": 2796,
              "background": "#f8fafc",
              "headline": "Proof that your app works",
              "subhead": "Capture release assets from data.",
              "source_text": "Generated with evidence",
              "device_frame": {
                "x": 760,
                "y": 420,
                "width": 360,
                "height": 780,
                "corner_radius": 58,
                "fill": "#111827"
              },
              "rows": [
                { "kind": "left", "title": "Left", "text": "Left row" },
                { "kind": "right", "title": "Right", "text": "Right row" },
                { "kind": "badge", "text": "Open source" },
                { "kind": "metric", "label": "Coverage", "value": "100%" },
                { "kind": "timeline", "title": "Workflow", "items": ["Launch", "Capture"] },
                { "kind": "stage", "label": "Release", "status": "Ready" },
                { "kind": "row", "title": "Portable", "detail": "Keep app data local." },
                {
                  "kind": "compose",
                  "rows": [
                    { "kind": "badge", "text": "Nested" }
                  ]
                }
              ]
            }
          ]
        }
        """
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

private final class MarketingRecordingRunner: CommandRunning {
    struct Command: Equatable {
        var executable: String
        var arguments: [String]
    }

    var commands: [Command] = []

    func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
        commands.append(Command(executable: executable, arguments: arguments))
        return CommandResult(exitCode: 0)
    }
}
