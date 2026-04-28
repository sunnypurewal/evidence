import Foundation

public struct EvidenceCLI {
    public var fileManager: FileManager
    public var runner: CommandRunning
    public var stdout: (String) -> Void
    public var stderr: (String) -> Void
    public var currentDirectory: URL
    public var toolPaths: ToolPaths

    public init(
        fileManager: FileManager = .default,
        runner: CommandRunning = ProcessCommandRunner(),
        stdout: @escaping (String) -> Void = { print($0) },
        stderr: @escaping (String) -> Void = { FileHandle.standardError.write(Data(($0 + "\n").utf8)) },
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
        toolPaths: ToolPaths = ToolPaths()
    ) {
        self.fileManager = fileManager
        self.runner = runner
        self.stdout = stdout
        self.stderr = stderr
        self.currentDirectory = currentDirectory
        self.toolPaths = toolPaths
    }

    public static func main() {
        let exitCode = EvidenceCLI().run(Array(CommandLine.arguments.dropFirst()))
        Foundation.exit(exitCode)
    }

    @discardableResult
    public func run(_ arguments: [String]) -> Int32 {
        do {
            try execute(arguments)
            return 0
        } catch {
            stderr((error as? LocalizedError)?.errorDescription ?? String(describing: error))
            return 1
        }
    }

    public func execute(_ arguments: [String]) throws {
        let arguments = arguments.first == "--" ? Array(arguments.dropFirst()) : arguments
        guard let first = arguments.first else {
            stdout(Help.root)
            return
        }

        if first == "--help" || first == "-h" || first == "help" {
            stdout(Help.root)
            return
        }

        let commandArguments = Array(arguments.dropFirst())
        if commandArguments.contains("--help") || commandArguments.contains("-h") {
            stdout(try Help.text(for: first))
            return
        }

        let config = try loadConfig()

        switch first {
        case "capture-screenshots":
            try captureScreenshots(config: config)
        case "resize":
            try resize(commandArguments, config: config)
        case "render-marketing":
            try renderMarketing(commandArguments, config: config)
        case "record-preview":
            try recordPreview(commandArguments, config: config)
        case "capture-evidence":
            try captureEvidence(commandArguments, config: config)
        default:
            throw CLIError.usage("Unknown command '\(first)'. Run `evidence --help`.")
        }
    }

    public func loadConfig() throws -> EvidenceConfig {
        try EvidenceConfig.load(from: currentDirectory.appendingPathComponent(".evidence.toml"))
    }

    private func captureScreenshots(config: EvidenceConfig) throws {
        try requireTool(toolPaths.xcrun, versionArguments: ["simctl", "help"], installHint: "Install Xcode and command line tools.")

        var arguments = [
            "test",
            "-scheme", config.scheme,
            "-destination", "platform=iOS Simulator,id=\(config.simulatorUDID)"
        ]
        if !config.deviceMatrix.isEmpty {
            arguments.append(contentsOf: ["-only-testing", config.deviceMatrix.joined(separator: ",")])
        }

        let result = try runner.run(toolPaths.xcrun, ["xcodebuild"] + arguments)
        guard result.exitCode == 0 else {
            throw CLIError.commandFailed("xcodebuild screenshot capture failed. \(result.stderr)")
        }
    }

    private func resize(_ arguments: [String], config: EvidenceConfig) throws {
        let input = try option("input", in: arguments)
        let output = try option("output", in: arguments)
        let targetName = optionValue("target", in: arguments) ?? "6.9"
        guard let target = ScreenshotTarget(named: targetName) else {
            throw CLIError.usage("Unknown resize target '\(targetName)'. Run `evidence resize --help`.")
        }

        try requireTool(toolPaths.magick, versionArguments: ["--version"], installHint: "Install ImageMagick, for example with `brew install imagemagick`.")
        let result = try runner.run(
            toolPaths.magick,
            [input, "-resize", "\(target.width)x\(target.height)^", "-gravity", "center", "-extent", "\(target.width)x\(target.height)", output]
        )
        guard result.exitCode == 0 else {
            throw CLIError.commandFailed("Image resize failed. \(result.stderr)")
        }
    }

    private func renderMarketing(_ arguments: [String], config: EvidenceConfig) throws {
        let scenePath = try option("scene", in: arguments)
        let outputPath = try option("output", in: arguments)
        let targetName = optionValue("target", in: arguments) ?? config.screenshotTargets.first?.name ?? "6.9"
        guard let target = ScreenshotTarget(named: targetName) else {
            throw CLIError.usage("Unknown marketing target '\(targetName)'. Run `evidence render-marketing --help`.")
        }

        let sceneURL = url(forPath: scenePath)
        let outputURL = url(forPath: outputPath)
        let defaultSVGPath = outputURL.deletingPathExtension().appendingPathExtension("svg").path
        let svgURL = url(forPath: optionValue("svg", in: arguments) ?? defaultSVGPath)

        try requireTool(toolPaths.magick, versionArguments: ["--version"], installHint: "Install ImageMagick, for example with `brew install imagemagick`.")
        let renderer = MarketingRenderer(fileManager: fileManager, runner: runner, toolPaths: toolPaths)
        let scene = try renderer.loadScene(from: sceneURL, target: target)
        try renderer.render(scene: scene, svgURL: svgURL, pngURL: outputURL)
        stdout("Rendered marketing screenshot at \(outputURL.path)")
    }

    private func recordPreview(_ arguments: [String], config: EvidenceConfig) throws {
        let input = try option("input", in: arguments)
        let output = try option("output", in: arguments)
        let defaults = config.previewDefaults
        let duration = optionValue("duration", in: arguments).flatMap(Double.init) ?? defaults.maxDuration
        let fps = optionValue("fps", in: arguments).flatMap(Int.init) ?? defaults.fps
        let width = optionValue("width", in: arguments).flatMap(Int.init) ?? defaults.width
        let height = optionValue("height", in: arguments).flatMap(Int.init) ?? defaults.height
        let trimStart = optionValue("trim-start", in: arguments).flatMap(Double.init) ?? defaults.trimStart
        let trimEnd = optionValue("trim-end", in: arguments).flatMap(Double.init) ?? defaults.trimEnd

        try requireTool(toolPaths.ffmpeg, versionArguments: ["-version"], installHint: "Install ffmpeg, for example with `brew install ffmpeg`.")
        var ffmpegArguments = ["-y"]
        if trimStart > 0 {
            ffmpegArguments.append(contentsOf: ["-ss", "\(trimStart)"])
        }
        ffmpegArguments.append(contentsOf: ["-i", input, "-an", "-t", "\(duration)"])
        if let trimEnd {
            ffmpegArguments.append(contentsOf: ["-to", "\(trimEnd)"])
        }
        ffmpegArguments.append(contentsOf: [
            "-vf", "scale=\(width):\(height),fps=\(fps)",
            "-c:v", "libx264",
            "-pix_fmt", "yuv420p",
            output
        ])

        let result = try runner.run(
            toolPaths.ffmpeg,
            ffmpegArguments
        )
        guard result.exitCode == 0 else {
            throw CLIError.commandFailed("Preview recording encode failed. \(result.stderr)")
        }
    }

    private func captureEvidence(_ arguments: [String], config: EvidenceConfig) throws {
        let ticket = try option("ticket", in: arguments)
        let outputDirectory = currentDirectory.appendingPathComponent(config.evidenceDirectory, isDirectory: true)
        let output = outputDirectory.appendingPathComponent("\(ticket)-running.png")

        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try requireTool(toolPaths.xcrun, versionArguments: ["simctl", "help"], installHint: "Install Xcode and command line tools.")

        let result = try runner.run(toolPaths.xcrun, ["simctl", "io", config.simulatorUDID, "screenshot", output.path])
        guard result.exitCode == 0 else {
            throw CLIError.commandFailed("Build evidence capture failed. \(result.stderr)")
        }

        if let url = markdownURL(for: output, config: config) {
            stdout("![Build evidence](\(url))")
        } else {
            stdout("Captured build evidence at \(output.path)")
        }
    }

    private func markdownURL(for output: URL, config: EvidenceConfig) -> String? {
        guard let baseURL = config.repositoryRawBaseURL ?? inferredRepositoryRawBaseURL() else {
            return nil
        }
        let relativePath = output.path.replacingOccurrences(of: currentDirectory.path + "/", with: "")
        return baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/" + relativePath
    }

    private func url(forPath path: String) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return currentDirectory.appendingPathComponent(path)
    }

    private func inferredRepositoryRawBaseURL() -> String? {
        guard let result = try? runner.run(toolPaths.git, ["remote", "get-url", "origin"]),
              result.exitCode == 0 else {
            return nil
        }

        let remote = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if remote.hasPrefix("git@github.com:") {
            let path = remote
                .replacingOccurrences(of: "git@github.com:", with: "")
                .replacingOccurrences(of: ".git", with: "")
            return "https://raw.githubusercontent.com/\(path)/main"
        }

        if remote.hasPrefix("https://github.com/") {
            let path = remote
                .replacingOccurrences(of: "https://github.com/", with: "")
                .replacingOccurrences(of: ".git", with: "")
            return "https://raw.githubusercontent.com/\(path)/main"
        }

        return nil
    }

    private func requireTool(_ executable: String, versionArguments: [String], installHint: String) throws {
        guard fileManager.isExecutableFile(atPath: executable) else {
            throw CLIError.missingTool(URL(fileURLWithPath: executable).lastPathComponent, installHint: installHint)
        }
        let result = try runner.run(executable, versionArguments)
        guard result.exitCode == 0 else {
            throw CLIError.missingTool(URL(fileURLWithPath: executable).lastPathComponent, installHint: installHint)
        }
    }

    private func option(_ name: String, in arguments: [String]) throws -> String {
        guard let value = optionValue(name, in: arguments), !value.isEmpty else {
            throw CLIError.usage("Missing required option --\(name).")
        }
        return value
    }

    private func optionValue(_ name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: "--\(name)") else {
            return nil
        }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else {
            return nil
        }
        return arguments[valueIndex]
    }
}

public struct ToolPaths: Equatable {
    public var xcrun: String
    public var magick: String
    public var ffmpeg: String
    public var git: String

    public init(
        xcrun: String = "/usr/bin/xcrun",
        magick: String = "/opt/homebrew/bin/magick",
        ffmpeg: String = "/opt/homebrew/bin/ffmpeg",
        git: String = "/usr/bin/git"
    ) {
        self.xcrun = xcrun
        self.magick = magick
        self.ffmpeg = ffmpeg
        self.git = git
    }
}
