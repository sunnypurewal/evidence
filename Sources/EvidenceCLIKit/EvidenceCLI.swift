import Foundation

public struct EvidenceCLI {
    public var fileManager: FileManager
    public var runner: CommandRunning
    public var stdout: (String) -> Void
    public var stderr: (String) -> Void
    public var currentDirectory: URL
    public var toolPaths: ToolPaths
    public var httpClient: HTTPClient
    /// Directory used for the xcresult cache when
    /// `xcresult_keep_full_bundle = false`. Defaults to `~/.evidence/cache`.
    public var cacheDirectory: URL

    public init(
        fileManager: FileManager = .default,
        runner: CommandRunning = ProcessCommandRunner(),
        stdout: @escaping (String) -> Void = { print($0) },
        stderr: @escaping (String) -> Void = { FileHandle.standardError.write(Data(($0 + "\n").utf8)) },
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
        toolPaths: ToolPaths = ToolPaths(),
        httpClient: HTTPClient = URLSessionHTTPClient(),
        cacheDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".evidence", isDirectory: true)
            .appendingPathComponent("cache", isDirectory: true)
    ) {
        self.fileManager = fileManager
        self.runner = runner
        self.stdout = stdout
        self.stderr = stderr
        self.currentDirectory = currentDirectory
        self.toolPaths = toolPaths
        self.httpClient = httpClient
        self.cacheDirectory = cacheDirectory
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
            // Honor `CLIError.exit(code, ...)` so subcommands like
            // `evidence diff` can return CI-stable exit codes (1 = regression,
            // 2 = baseline missing). All other errors fall back to 1.
            if let cliError = error as? CLIError {
                return cliError.exitCode
            }
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
        case "upload-screenshots":
            try uploadScreenshots(commandArguments, config: config)
        case "capture-web":
            try captureWeb(config: config)
        default:
            throw CLIError.usage("Unknown command '\(first)'. Run `evidence --help`.")
        }
    }

    public func loadConfig() throws -> EvidenceConfig {
        try EvidenceConfig.load(from: currentDirectory.appendingPathComponent(".evidence.toml"))
    }

    private func captureScreenshots(config: EvidenceConfig) throws {
        try requireTool(toolPaths.xcrun, versionArguments: ["simctl", "help"], installHint: "Install Xcode and command line tools.")

        let arguments = xcodebuildTestArguments(config: config)
        let result = try runner.run(toolPaths.xcrun, ["xcodebuild"] + arguments)
        guard result.exitCode == 0 else {
            throw CLIError.commandFailed("xcodebuild screenshot capture failed. \(result.stderr)")
        }
    }

    /// Build the `xcodebuild test` argument list shared by `capture-screenshots`
    /// and the xcresult bundle capture path of `capture-evidence`. Caller is
    /// responsible for prepending the `xcodebuild` token (xcrun forwards it).
    private func xcodebuildTestArguments(config: EvidenceConfig, resultBundlePath: String? = nil) -> [String] {
        var arguments: [String] = ["test"]
        if let workspace = config.xcodeWorkspace {
            arguments.append(contentsOf: ["-workspace", workspace])
        } else if let project = config.xcodeProject {
            arguments.append(contentsOf: ["-project", project])
        }
        arguments.append(contentsOf: [
            "-scheme", config.scheme,
            "-destination", "platform=iOS Simulator,id=\(config.simulatorUDID)"
        ])
        if !config.deviceMatrix.isEmpty {
            arguments.append(contentsOf: ["-only-testing", config.deviceMatrix.joined(separator: ",")])
        }
        if let resultBundlePath {
            arguments.append(contentsOf: ["-resultBundlePath", resultBundlePath])
        }
        return arguments
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

        if config.xcresult.enabled {
            // CLI flag `--xcresult-summary-only` mirrors the toggle: when set,
            // the full bundle is dropped to the cache directory and only the
            // summary markdown is committed under `evidence_dir`.
            let summaryOnly = arguments.contains("--xcresult-summary-only") || !config.xcresult.keepFullBundle
            try captureXcresult(
                ticket: ticket,
                config: config,
                evidenceDirectory: outputDirectory,
                summaryOnly: summaryOnly
            )
        }
    }

    private func captureXcresult(
        ticket: String,
        config: EvidenceConfig,
        evidenceDirectory: URL,
        summaryOnly: Bool
    ) throws {
        let bundleName = "\(ticket).xcresult"
        let summaryName = "\(ticket)-tests.md"
        let summaryURL = evidenceDirectory.appendingPathComponent(summaryName)

        // Always run xcodebuild against a deterministic working bundle path
        // inside `evidence_dir`. When `summaryOnly` is true we move it to the
        // cache directory after the summary is written.
        let workingBundleURL = evidenceDirectory.appendingPathComponent(bundleName)
        // xcodebuild refuses to overwrite an existing -resultBundlePath, so a
        // re-run on the same ticket would otherwise fail. Wipe any previous
        // bundle (and any orphan from an earlier summary-only run in the
        // cache) before kicking off the test.
        if fileManager.fileExists(atPath: workingBundleURL.path) {
            try fileManager.removeItem(at: workingBundleURL)
        }

        let xcodebuildArguments = xcodebuildTestArguments(
            config: config,
            resultBundlePath: workingBundleURL.path
        )
        let testResult = try runner.run(toolPaths.xcrun, ["xcodebuild"] + xcodebuildArguments)

        // `xcodebuild test` exits non-zero on either a build error (bundle is
        // not produced) or a test failure (bundle IS produced). Distinguish
        // by looking for the bundle on disk.
        let bundleExists = fileManager.fileExists(atPath: workingBundleURL.path)
        if !bundleExists {
            // Build error fast-fail: still write a markdown summary so the PR
            // / PR comment surfaces what went wrong, then propagate the
            // failure as a non-zero exit.
            let markdown = XcresultMarkdown.renderBuildError(ticket: ticket, stderr: testResult.stderr)
            try markdown.write(to: summaryURL, atomically: true, encoding: .utf8)
            stdout("Wrote build-error summary to \(summaryURL.path)")
            throw CLIError.commandFailed("xcodebuild test failed before producing a result bundle. \(testResult.stderr)")
        }

        // Bundle exists — parse summary even if `xcodebuild` returned non-zero
        // (test failures are expected to surface in the markdown rather than
        // crash the CLI).
        let summaryArguments = [
            "xcresulttool", "get", "test-results", "summary",
            "--path", workingBundleURL.path
        ]
        let summaryResult = try runner.run(toolPaths.xcrun, summaryArguments)
        guard summaryResult.exitCode == 0 else {
            throw CLIError.commandFailed("xcresulttool failed to summarize \(workingBundleURL.path). \(summaryResult.stderr)")
        }

        let parsed = try XcresultSummary.parse(summaryResult.stdout)
        let markdown = XcresultMarkdown.render(parsed, ticket: ticket)
        try markdown.write(to: summaryURL, atomically: true, encoding: .utf8)
        stdout("Wrote test summary to \(summaryURL.path)")

        if summaryOnly {
            // Move the bundle out of the committed evidence directory and
            // into the user's cache so it remains inspectable locally without
            // bloating the repo.
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            let cachedBundleURL = cacheDirectory.appendingPathComponent(bundleName)
            if fileManager.fileExists(atPath: cachedBundleURL.path) {
                try fileManager.removeItem(at: cachedBundleURL)
            }
            try fileManager.moveItem(at: workingBundleURL, to: cachedBundleURL)
            stdout("Cached full xcresult bundle at \(cachedBundleURL.path)")
        } else {
            stdout("Captured xcresult bundle at \(workingBundleURL.path)")
        }

        // The markdown is now persisted regardless of pass/fail state. If the
        // underlying `xcodebuild test` reported failures, propagate that as a
        // non-zero CLI exit so CI catches the regression — `<KEY>-tests.md`
        // is still authoritative for the PR comment.
        if testResult.exitCode != 0 {
            throw CLIError.commandFailed("xcodebuild test reported \(parsed.failedTests) failure(s). See \(summaryURL.path).")
        }
    }

    /// Captures web screenshots for each configured viewport using Playwright.
    ///
    /// Requires `platform = "web"` in `.evidence.toml` and the `web_url` and
    /// `web_viewports` keys. Calls the bundled `capture-web.js` Node script via
    /// the `node` binary in `toolPaths`.
    ///
    /// Output layout:
    ///   `<evidence_dir>/<viewport-name>/<page-slug>.png`
    ///
    /// where `<viewport-name>` is the viewport preset name (e.g. `desktop-1440`)
    /// or the custom `WxH` string, and `<page-slug>` is derived from the URL path
    /// (defaulting to `index` for the root).
    private func captureWeb(config: EvidenceConfig) throws {
        guard config.platform == .web else {
            throw CLIError.usage("capture-web requires platform = \"web\" in .evidence.toml.")
        }
        guard let web = config.webConfig else {
            throw CLIError.config("Missing web configuration. Set platform = \"web\" and provide web_url and web_viewports in .evidence.toml.")
        }

        // Locate the bundled capture-web.js script via the module bundle.
        guard let scriptURL = Bundle.module.url(forResource: "capture-web", withExtension: "js") else {
            throw CLIError.commandFailed("Bundled capture-web.js script not found. Reinstall the evidence tool.")
        }

        // Ensure node is available.
        guard fileManager.isExecutableFile(atPath: toolPaths.node) else {
            throw CLIError.missingTool("node", installHint: "Install Node.js (https://nodejs.org) and ensure `node` is on your PATH.")
        }

        let pageSlug = Self.pageSlug(from: web.url)
        let evidenceDir = currentDirectory.appendingPathComponent(config.evidenceDirectory, isDirectory: true)

        for viewport in web.viewports {
            let viewportSpec = Self.resolveViewport(viewport)
            let outputDir = evidenceDir.appendingPathComponent(viewport, isDirectory: true)
            try fileManager.createDirectory(at: outputDir, withIntermediateDirectories: true)
            let outputPath = outputDir.appendingPathComponent("\(pageSlug).png").path

            let result = try runner.run(
                toolPaths.node,
                [
                    scriptURL.path,
                    web.url,
                    viewportSpec,
                    web.fullPage ? "true" : "false",
                    web.waitUntil,
                    outputPath
                ]
            )

            guard result.exitCode == 0 else {
                throw CLIError.commandFailed("Web screenshot capture failed for viewport '\(viewport)': \(result.stderr)")
            }

            guard fileManager.fileExists(atPath: outputPath) else {
                throw CLIError.commandFailed("Web screenshot capture produced no output for viewport '\(viewport)'.")
            }

            stdout("Captured \(viewport) screenshot at \(outputPath)")
        }
    }

    /// Resolves a named viewport preset to a `WxH` spec string, or passes
    /// through custom `WxH` strings unchanged.
    ///
    /// - `desktop-1440` → `1440x900`
    /// - `mobile-390`   → `390x844`
    /// - `WxH`          → `WxH` (passed through)
    public static func resolveViewport(_ viewport: String) -> String {
        switch viewport {
        case "desktop-1440":
            return "1440x900"
        case "mobile-390":
            return "390x844"
        default:
            return viewport
        }
    }

    /// Derives a filesystem-safe page slug from a URL path component.
    ///
    /// - Root paths (`/` or empty) → `"index"`
    /// - `/about/team` → `"about-team"`
    /// - `/products/widget-pro` → `"products-widget-pro"`
    public static func pageSlug(from urlString: String) -> String {
        guard let url = URL(string: urlString), url.scheme != nil else {
            return "index"
        }
        let path = url.path
        if path.isEmpty || path == "/" {
            return "index"
        }
        // Strip leading/trailing slashes, replace path separators with dashes,
        // and lowercase for consistency.
        let slug = path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .replacingOccurrences(of: "/", with: "-")
            .lowercased()
        return slug.isEmpty ? "index" : slug
    }

    private func uploadScreenshots(_ arguments: [String], config: EvidenceConfig) throws {
        try AppStoreScreenshotUploader(
            fileManager: fileManager,
            httpClient: httpClient,
            stdout: stdout
        ).upload(arguments: arguments, config: config, currentDirectory: currentDirectory)
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
    /// Path to the `node` binary. Used by `capture-web` to invoke the bundled
    /// Playwright script.
    public var node: String

    public init(
        xcrun: String = "/usr/bin/xcrun",
        magick: String = "/opt/homebrew/bin/magick",
        ffmpeg: String = "/opt/homebrew/bin/ffmpeg",
        git: String = "/usr/bin/git",
        node: String = "/usr/local/bin/node"
    ) {
        self.xcrun = xcrun
        self.magick = magick
        self.ffmpeg = ffmpeg
        self.git = git
        self.node = node
    }
}
