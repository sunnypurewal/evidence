import Foundation

public struct EvidenceReport: Equatable {
    public var markdown: String
    public var reportURL: URL
    public var comparisonImagePaths: [String]
    public var skippedComparisonReasons: [String]

    public init(
        markdown: String,
        reportURL: URL,
        comparisonImagePaths: [String] = [],
        skippedComparisonReasons: [String] = []
    ) {
        self.markdown = markdown
        self.reportURL = reportURL
        self.comparisonImagePaths = comparisonImagePaths
        self.skippedComparisonReasons = skippedComparisonReasons
    }
}

public struct SceneComparison: Equatable {
    public var name: String
    public var beforeScreenshot: CapturedArtifact?
    public var afterScreenshot: CapturedArtifact?
    public var beforeVideo: CapturedArtifact?
    public var afterVideo: CapturedArtifact?
    public var comparisonImagePath: String?

    public init(
        name: String,
        beforeScreenshot: CapturedArtifact? = nil,
        afterScreenshot: CapturedArtifact? = nil,
        beforeVideo: CapturedArtifact? = nil,
        afterVideo: CapturedArtifact? = nil,
        comparisonImagePath: String? = nil
    ) {
        self.name = name
        self.beforeScreenshot = beforeScreenshot
        self.afterScreenshot = afterScreenshot
        self.beforeVideo = beforeVideo
        self.afterVideo = afterVideo
        self.comparisonImagePath = comparisonImagePath
    }
}

public struct ReportFailureSection: Equatable {
    public var title: String
    public var lines: [String]

    public init(title: String, lines: [String]) {
        self.title = title
        self.lines = lines
    }
}

public struct ComparisonImageRenderRequest: Equatable {
    public var sceneName: String
    public var beforeURL: URL
    public var afterURL: URL
    public var outputURL: URL
    public var beforeLabel: String
    public var afterLabel: String

    public init(
        sceneName: String,
        beforeURL: URL,
        afterURL: URL,
        outputURL: URL,
        beforeLabel: String,
        afterLabel: String
    ) {
        self.sceneName = sceneName
        self.beforeURL = beforeURL
        self.afterURL = afterURL
        self.outputURL = outputURL
        self.beforeLabel = beforeLabel
        self.afterLabel = afterLabel
    }
}

public enum ComparisonImageRenderResult: Equatable {
    case rendered(URL)
    case skipped(String)
}

public protocol ComparisonImageRendering {
    func render(_ request: ComparisonImageRenderRequest) throws -> ComparisonImageRenderResult
}

public protocol PullRequestEvidenceReporting {
    @discardableResult
    func writeReport(
        manifest: PRChangeEvidenceManifest,
        plan: PRChangeEvidencePlan,
        outputDirectory: URL
    ) throws -> EvidenceReport

    @discardableResult
    func writeReportOnlyFailure(
        _ failure: PullRequestEvidenceReportOnlyFailure,
        outputDirectory: URL
    ) throws -> EvidenceReport
}

public struct PullRequestEvidenceReportOnlyFailure: Equatable {
    public var repo: String
    public var pr: Int
    public var planPath: String
    public var command: [String]
    public var startedAt: String
    public var completedAt: String
    public var errorMessage: String

    public init(
        repo: String,
        pr: Int,
        planPath: String,
        command: [String],
        startedAt: String,
        completedAt: String,
        errorMessage: String
    ) {
        self.repo = repo
        self.pr = pr
        self.planPath = planPath
        self.command = command
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.errorMessage = errorMessage
    }
}

public struct ImageMagickComparisonRenderer: ComparisonImageRendering {
    public var fileManager: FileManager
    public var runner: CommandRunning
    public var toolPaths: ToolPaths

    public init(
        fileManager: FileManager = .default,
        runner: CommandRunning,
        toolPaths: ToolPaths = ToolPaths()
    ) {
        self.fileManager = fileManager
        self.runner = runner
        self.toolPaths = toolPaths
    }

    public func render(_ request: ComparisonImageRenderRequest) throws -> ComparisonImageRenderResult {
        guard fileManager.isExecutableFile(atPath: toolPaths.magick) else {
            return .skipped("ImageMagick is not available at \(toolPaths.magick)")
        }

        try fileManager.createDirectory(
            at: request.outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let result = try runner.run(toolPaths.magick, [
            "montage",
            "-label", request.beforeLabel,
            request.beforeURL.path,
            "-label", request.afterLabel,
            request.afterURL.path,
            "-tile", "2x1",
            "-geometry", "900x900+24+24",
            "-background", "#ffffff",
            request.outputURL.path
        ])

        guard result.exitCode == 0 else {
            let detail = result.stderr.nonEmpty ?? result.stdout.nonEmpty ?? "exit code \(result.exitCode)"
            return .skipped("ImageMagick contact-sheet rendering failed: \(detail)")
        }
        return .rendered(request.outputURL)
    }
}

public struct RenderPullRequestEvidenceReport: PullRequestEvidenceReporting {
    public var comparisonRenderer: any ComparisonImageRendering
    public var fileManager: FileManager

    public init(
        comparisonRenderer: any ComparisonImageRendering,
        fileManager: FileManager = .default
    ) {
        self.comparisonRenderer = comparisonRenderer
        self.fileManager = fileManager
    }

    @discardableResult
    public func writeReport(
        manifest: PRChangeEvidenceManifest,
        plan: PRChangeEvidencePlan,
        outputDirectory: URL
    ) throws -> EvidenceReport {
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        var skippedComparisonReasons: [String] = []
        var comparisonImagePaths: [String] = []
        var scenes = sceneComparisons(plan: plan, manifest: manifest)

        for index in scenes.indices {
            guard let before = scenes[index].beforeScreenshot,
                  let after = scenes[index].afterScreenshot else {
                continue
            }

            let outputURL = outputDirectory
                .appendingPathComponent("comparisons", isDirectory: true)
                .appendingPathComponent("\(slug(for: scenes[index].name)).png")
            let request = ComparisonImageRenderRequest(
                sceneName: scenes[index].name,
                beforeURL: URL(fileURLWithPath: before.path),
                afterURL: URL(fileURLWithPath: after.path),
                outputURL: outputURL,
                beforeLabel: "\(scenes[index].name) - Before \(shortSHA(manifest.beforeSHA))",
                afterLabel: "\(scenes[index].name) - After \(shortSHA(manifest.afterSHA))"
            )

            do {
                switch try comparisonRenderer.render(request) {
                case .rendered(let url):
                    let path = markdownPath(for: url.path, outputDirectory: outputDirectory)
                    scenes[index].comparisonImagePath = path
                    comparisonImagePaths.append(path)
                case .skipped(let reason):
                    skippedComparisonReasons.append(reason)
                }
            } catch {
                skippedComparisonReasons.append("Contact-sheet rendering failed: \(errorDescription(error))")
            }
        }

        let markdown = renderMarkdown(
            manifest: manifest,
            plan: plan,
            outputDirectory: outputDirectory,
            scenes: scenes,
            skippedComparisonReasons: skippedComparisonReasons
        )
        let reportURL = outputDirectory.appendingPathComponent("report.md")
        try markdown.write(to: reportURL, atomically: true, encoding: .utf8)
        return EvidenceReport(
            markdown: markdown,
            reportURL: reportURL,
            comparisonImagePaths: comparisonImagePaths,
            skippedComparisonReasons: skippedComparisonReasons
        )
    }

    @discardableResult
    public func writeReportOnlyFailure(
        _ failure: PullRequestEvidenceReportOnlyFailure,
        outputDirectory: URL
    ) throws -> EvidenceReport {
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        var lines: [String] = []
        lines.append("# PR Change Evidence Report")
        lines.append("")
        lines.append("## Summary")
        lines.append("- Repository: `\(failure.repo)`")
        lines.append("- Pull request: #\(failure.pr)")
        lines.append("- PR title: unavailable")
        lines.append("- PR URL: unavailable")
        lines.append("- Before SHA: unavailable")
        lines.append("- After SHA: unavailable")
        lines.append("- Runner mode: unavailable")
        lines.append("- Simulator: unavailable")
        lines.append("- Command: `\(failure.command.joined(separator: " "))`")
        lines.append("- Started: `\(failure.startedAt)`")
        lines.append("- Completed: `\(failure.completedAt)`")
        lines.append("- Overall status: **failed**")
        lines.append("")
        lines.append("## Failure Details")
        lines.append("")
        lines.append("### Report-Only Partial Output")
        lines.append("- Evidence failed before a manifest could be completed, so this report contains metadata and failure details only.")
        lines.append("- Plan: `\(failure.planPath)`")
        lines.append("")
        lines.append("### Capture Failure")
        lines.append("- \(failure.errorMessage)")
        lines.append("")

        let markdown = lines.joined(separator: "\n")
        let reportURL = outputDirectory.appendingPathComponent("report.md")
        try markdown.write(to: reportURL, atomically: true, encoding: .utf8)
        return EvidenceReport(markdown: markdown, reportURL: reportURL)
    }

    private func renderMarkdown(
        manifest: PRChangeEvidenceManifest,
        plan: PRChangeEvidencePlan,
        outputDirectory: URL,
        scenes: [SceneComparison],
        skippedComparisonReasons: [String]
    ) -> String {
        var lines: [String] = []
        lines.append("# PR Change Evidence Report")
        lines.append("")
        appendSummary(to: &lines, manifest: manifest, plan: plan)
        appendVisualComparisons(
            to: &lines,
            scenes: scenes,
            outputDirectory: outputDirectory,
            skippedComparisonReasons: skippedComparisonReasons
        )
        appendPlannedSteps(to: &lines, plan: plan, manifest: manifest, outputDirectory: outputDirectory)
        appendFailureDetails(to: &lines, plan: plan, manifest: manifest, outputDirectory: outputDirectory)
        appendRunMetadata(to: &lines, manifest: manifest, outputDirectory: outputDirectory)
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private func appendSummary(
        to lines: inout [String],
        manifest: PRChangeEvidenceManifest,
        plan: PRChangeEvidencePlan
    ) {
        lines.append("## Summary")
        lines.append("- Repository: `\(repositoryName(from: manifest))`")
        if let url = manifest.prURL?.nonEmpty {
            let title = manifest.prTitle?.nonEmpty.map { " \($0)" } ?? ""
            lines.append("- Pull request: [#\(manifest.prNumber)\(title)](\(url))")
        } else {
            let title = manifest.prTitle?.nonEmpty.map { " \($0)" } ?? ""
            lines.append("- Pull request: #\(manifest.prNumber)\(title)")
        }
        if let title = manifest.prTitle?.nonEmpty {
            lines.append("- PR title: \(title)")
        } else {
            lines.append("- PR title: unavailable")
        }
        lines.append("- PR URL: \(manifest.prURL?.nonEmpty ?? "unavailable")")
        lines.append("- Before SHA: `\(manifest.beforeSHA)`")
        lines.append("- After SHA: `\(manifest.afterSHA)`")
        lines.append("- Runner mode: `\(manifest.runnerMode.rawValue)`")
        lines.append("- Simulator: \(simulatorDescription(manifest.simulator))")
        lines.append("- Command: `\(manifest.command.joined(separator: " "))`")
        lines.append("- Started: `\(manifest.startedAt)`")
        lines.append("- Completed: `\(manifest.completedAt ?? "unavailable")`")
        lines.append("- Overall status: **\(overallStatus(manifest, plan: plan))**")
        lines.append("")
    }

    private func appendVisualComparisons(
        to lines: inout [String],
        scenes: [SceneComparison],
        outputDirectory: URL,
        skippedComparisonReasons: [String]
    ) {
        lines.append("## Visual Comparisons")

        let screenshotScenes = scenes.filter { $0.beforeScreenshot != nil || $0.afterScreenshot != nil }
        if screenshotScenes.isEmpty {
            lines.append("")
            lines.append("No screenshot artifacts were captured for comparison.")
        } else {
            for scene in screenshotScenes {
                lines.append("")
                lines.append("### \(scene.name)")
                if let comparisonImagePath = scene.comparisonImagePath {
                    lines.append("![\(scene.name) comparison](\(comparisonImagePath))")
                } else {
                    if let before = scene.beforeScreenshot {
                        let beforePath = markdownPath(for: before.path, outputDirectory: outputDirectory)
                        lines.append("![\(scene.name) before](\(beforePath))")
                    }
                    if let after = scene.afterScreenshot {
                        let afterPath = markdownPath(for: after.path, outputDirectory: outputDirectory)
                        lines.append("![\(scene.name) after](\(afterPath))")
                    }
                }
                lines.append(artifactLine(
                    label: "Artifacts",
                    before: scene.beforeScreenshot,
                    after: scene.afterScreenshot,
                    outputDirectory: outputDirectory
                ))
            }
        }

        for reason in unique(skippedComparisonReasons) {
            lines.append("")
            lines.append("> Contact-sheet rendering skipped: \(reason)")
        }
        lines.append("")
    }

    private func appendPlannedSteps(
        to lines: inout [String],
        plan: PRChangeEvidencePlan,
        manifest: PRChangeEvidenceManifest,
        outputDirectory: URL
    ) {
        lines.append("## Planned Steps")
        for (index, step) in plan.steps.enumerated() {
            lines.append("")
            lines.append("### \(index + 1). \(step.name)")
            lines.append("- Kind: `\(step.kind.rawValue)`")
            lines.append("- Before status: \(statusDescription(for: step, phase: .before, manifest: manifest))")
            lines.append("- After status: \(statusDescription(for: step, phase: .after, manifest: manifest))")

            let beforeScreenshot = artifact(kind: .screenshot, phase: .before, stepName: step.name, manifest: manifest)
            let afterScreenshot = artifact(kind: .screenshot, phase: .after, stepName: step.name, manifest: manifest)
            if step.kind == .screenshot || beforeScreenshot != nil || afterScreenshot != nil {
                lines.append(mediaLine(
                    title: "Before screenshot",
                    artifact: beforeScreenshot,
                    expected: expectedArtifactPath(for: step, phase: .before, fallbackExtension: "png"),
                    outputDirectory: outputDirectory
                ))
                lines.append(mediaLine(
                    title: "After screenshot",
                    artifact: afterScreenshot,
                    expected: expectedArtifactPath(for: step, phase: .after, fallbackExtension: "png"),
                    outputDirectory: outputDirectory
                ))
            }

            let beforeVideo = artifact(kind: .video, phase: .before, stepName: step.name, manifest: manifest)
            let afterVideo = artifact(kind: .video, phase: .after, stepName: step.name, manifest: manifest)
            if step.kind == .stopVideo || beforeVideo != nil || afterVideo != nil {
                lines.append(mediaLine(
                    title: "Before video",
                    artifact: beforeVideo,
                    expected: expectedArtifactPath(for: step, phase: .before, fallbackExtension: "mov"),
                    outputDirectory: outputDirectory
                ))
                lines.append(mediaLine(
                    title: "After video",
                    artifact: afterVideo,
                    expected: expectedArtifactPath(for: step, phase: .after, fallbackExtension: "mov"),
                    outputDirectory: outputDirectory
                ))
            }
        }
        lines.append("")
    }

    private func appendFailureDetails(
        to lines: inout [String],
        plan: PRChangeEvidencePlan,
        manifest: PRChangeEvidenceManifest,
        outputDirectory: URL
    ) {
        let sections = failureSections(plan: plan, manifest: manifest, outputDirectory: outputDirectory)
        guard !sections.isEmpty else { return }

        lines.append("## Failure Details")
        for section in sections {
            lines.append("")
            lines.append("### \(section.title)")
            for line in section.lines {
                lines.append("- \(line)")
            }
        }
        lines.append("")
    }

    private func appendRunMetadata(
        to lines: inout [String],
        manifest: PRChangeEvidenceManifest,
        outputDirectory: URL
    ) {
        lines.append("## Run Metadata")
        lines.append("- Plan: `\(manifest.planPath)`")
        if let destination = manifest.xcodeDestination?.nonEmpty {
            lines.append("- Xcode destination: `\(destination)`")
        }
        if let duration = manifest.buildResult.durationSeconds {
            lines.append("- Build duration: \(formatDuration(duration))")
        }
        let logs = manifest.artifacts.filter { $0.kind == .log }.sorted { $0.path < $1.path }
        if !logs.isEmpty {
            let links = logs.map { artifact -> String in
                let path = markdownPath(for: artifact.path, outputDirectory: outputDirectory)
                return "[\(path)](\(path))"
            }
            lines.append("- Logs: \(links.joined(separator: ", "))")
        }
    }

    private func sceneComparisons(
        plan: PRChangeEvidencePlan,
        manifest: PRChangeEvidenceManifest
    ) -> [SceneComparison] {
        var scenes: [SceneComparison] = []
        for step in plan.steps {
            guard step.kind == .screenshot || step.kind == .stopVideo else {
                continue
            }
            scenes.append(SceneComparison(
                name: step.name,
                beforeScreenshot: artifact(kind: .screenshot, phase: .before, stepName: step.name, manifest: manifest),
                afterScreenshot: artifact(kind: .screenshot, phase: .after, stepName: step.name, manifest: manifest),
                beforeVideo: artifact(kind: .video, phase: .before, stepName: step.name, manifest: manifest),
                afterVideo: artifact(kind: .video, phase: .after, stepName: step.name, manifest: manifest)
            ))
        }
        return scenes
    }

    private func failureSections(
        plan: PRChangeEvidencePlan,
        manifest: PRChangeEvidenceManifest,
        outputDirectory: URL
    ) -> [ReportFailureSection] {
        var sections: [ReportFailureSection] = []
        let mediaSteps = plan.steps.filter { $0.kind == .screenshot || $0.kind == .stopVideo }

        let missingBefore = missingArtifacts(
            phase: .before,
            steps: mediaSteps,
            manifest: manifest
        )
        if !missingBefore.isEmpty {
            sections.append(ReportFailureSection(title: "Missing Before Artifact", lines: missingBefore))
        }

        let missingAfter = missingArtifacts(
            phase: .after,
            steps: mediaSteps,
            manifest: manifest
        )
        if !missingAfter.isEmpty {
            sections.append(ReportFailureSection(title: "Missing After Artifact", lines: missingAfter))
        }

        if manifest.buildResult.status == .failed || manifest.revisionBuilds.contains(where: { $0.exitCode != 0 }) {
            var lines = manifest.revisionBuilds.filter { $0.exitCode != 0 }.map { build in
                "\(build.phase.rawValue) build failed with exit code \(build.exitCode). Log: [\(markdownPath(for: build.logPath, outputDirectory: outputDirectory))](\(markdownPath(for: build.logPath, outputDirectory: outputDirectory)))"
            }
            if lines.isEmpty, let logPath = manifest.buildResult.logPath?.nonEmpty {
                let path = markdownPath(for: logPath, outputDirectory: outputDirectory)
                lines.append("Build failed. Logs: [\(path)](\(path))")
            }
            for failure in manifest.failures where failure.message.localizedCaseInsensitiveContains("build failed") {
                lines.append(failure.message)
            }
            sections.append(ReportFailureSection(title: "Build Failure", lines: unique(lines)))
        }

        let timeoutLines = timeoutFailures(manifest: manifest)
        if !timeoutLines.isEmpty {
            sections.append(ReportFailureSection(title: "Capture Timeout", lines: timeoutLines))
        }

        if manifest.artifacts.allSatisfy({ $0.kind != .screenshot && $0.kind != .video }) {
            sections.append(ReportFailureSection(
                title: "Report-Only Partial Output",
                lines: ["No screenshot or video artifacts were captured; this report preserves metadata, logs, and failure context only."]
            ))
        }

        let genericFailures = manifest.failures
            .map(\.message)
            .filter { !$0.localizedCaseInsensitiveContains("build failed") && !isTimeout($0) }
        if !genericFailures.isEmpty {
            sections.append(ReportFailureSection(title: "Capture Failure", lines: unique(genericFailures)))
        }

        return sections
    }

    private func missingArtifacts(
        phase: PRChangeEvidencePhase,
        steps: [PRChangeEvidenceStep],
        manifest: PRChangeEvidenceManifest
    ) -> [String] {
        steps.compactMap { step in
            let kind: CapturedArtifact.Kind = step.kind == .screenshot ? .screenshot : .video
            guard artifact(kind: kind, phase: phase, stepName: step.name, manifest: manifest) == nil else {
                return nil
            }
            let expected = expectedArtifactPath(
                for: step,
                phase: phase,
                fallbackExtension: kind == .screenshot ? "png" : "mov"
            ) ?? "unknown"
            return "\(step.name): expected `\(expected)`"
        }
    }

    private func timeoutFailures(manifest: PRChangeEvidenceManifest) -> [String] {
        let failureMessages = manifest.failures.map(\.message).filter(isTimeout)
        let stepMessages = manifest.stepResults.compactMap { result -> String? in
            guard let message = result.message, isTimeout(message) else { return nil }
            return "\(result.phase.rawValue) \(result.stepName): \(message)"
        }
        return unique(failureMessages + stepMessages)
    }

    private func artifact(
        kind: CapturedArtifact.Kind,
        phase: PRChangeEvidencePhase,
        stepName: String,
        manifest: PRChangeEvidenceManifest
    ) -> CapturedArtifact? {
        manifest.artifacts.first {
            $0.kind == kind && $0.phase == phase && $0.stepName == stepName
        }
    }

    private func statusDescription(
        for step: PRChangeEvidenceStep,
        phase: PRChangeEvidencePhase,
        manifest: PRChangeEvidenceManifest
    ) -> String {
        guard let result = manifest.stepResults.first(where: { $0.phase == phase && $0.stepName == step.name }) else {
            return "`not recorded`"
        }
        if let message = result.message?.nonEmpty {
            return "`\(result.status.rawValue)` - \(message)"
        }
        return "`\(result.status.rawValue)`"
    }

    private func mediaLine(
        title: String,
        artifact: CapturedArtifact?,
        expected: String?,
        outputDirectory: URL
    ) -> String {
        if let artifact {
            let path = markdownPath(for: artifact.path, outputDirectory: outputDirectory)
            return "- \(title): [\(path)](\(path))"
        }
        if let expected {
            return "- \(title): missing (expected `\(expected)`)"
        }
        return "- \(title): missing"
    }

    private func artifactLine(
        label: String,
        before: CapturedArtifact?,
        after: CapturedArtifact?,
        outputDirectory: URL
    ) -> String {
        let beforePath = before.map { "`\(markdownPath(for: $0.path, outputDirectory: outputDirectory))`" } ?? "`missing`"
        let afterPath = after.map { "`\(markdownPath(for: $0.path, outputDirectory: outputDirectory))`" } ?? "`missing`"
        return "\(label): before \(beforePath), after \(afterPath)"
    }

    private func expectedArtifactPath(
        for step: PRChangeEvidenceStep,
        phase: PRChangeEvidencePhase,
        fallbackExtension: String
    ) -> String? {
        let rawPath = step.path?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = "\(slug(for: step.name)).\(fallbackExtension)"
        let relativePath = rawPath?.isEmpty == false ? rawPath! : fallback
        guard !relativePath.hasPrefix("/") else { return relativePath }
        var components = relativePath.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return nil }
        if components.first != PRChangeEvidencePhase.before.rawValue,
           components.first != PRChangeEvidencePhase.after.rawValue {
            components.insert(phase.rawValue, at: 0)
        }
        return components.joined(separator: "/")
    }

    private func repositoryName(from manifest: PRChangeEvidenceManifest) -> String {
        manifest.base?.repo?.nonEmpty
            ?? manifest.head?.repo?.nonEmpty
            ?? manifest.merge?.repo?.nonEmpty
            ?? "unknown"
    }

    private func simulatorDescription(_ simulator: PRChangeEvidenceSimulator?) -> String {
        guard let simulator else { return "unavailable" }
        switch (simulator.name?.nonEmpty, simulator.udid?.nonEmpty) {
        case let (name?, udid?):
            return "`\(name)` (`\(udid)`)"
        case let (name?, nil):
            return "`\(name)`"
        case let (nil, udid?):
            return "`\(udid)`"
        case (nil, nil):
            return "unavailable"
        }
    }

    private func overallStatus(_ manifest: PRChangeEvidenceManifest, plan: PRChangeEvidencePlan) -> String {
        if manifest.buildResult.status == .failed
            || !manifest.failures.isEmpty
            || manifest.stepResults.contains(where: { $0.status == .failed }) {
            return "failed"
        }
        if manifest.completedAt == nil
            || manifest.stepResults.contains(where: { $0.status == .skipped })
            || hasMissingExpectedMedia(plan: plan, manifest: manifest) {
            return "partial"
        }
        return "succeeded"
    }

    private func hasMissingExpectedMedia(
        plan: PRChangeEvidencePlan,
        manifest: PRChangeEvidenceManifest
    ) -> Bool {
        for step in plan.steps where step.kind == .screenshot || step.kind == .stopVideo {
            let kind: CapturedArtifact.Kind = step.kind == .screenshot ? .screenshot : .video
            if artifact(kind: kind, phase: .before, stepName: step.name, manifest: manifest) == nil
                || artifact(kind: kind, phase: .after, stepName: step.name, manifest: manifest) == nil {
                return true
            }
        }
        return false
    }

    private func shortSHA(_ sha: String) -> String {
        String(sha.prefix(7))
    }

    private func markdownPath(for path: String, outputDirectory: URL) -> String {
        let outputPath = outputDirectory.standardizedFileURL.path
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        if standardized == outputPath {
            return URL(fileURLWithPath: standardized).lastPathComponent
        }
        if standardized.hasPrefix(outputPath + "/") {
            return String(standardized.dropFirst(outputPath.count + 1))
        }
        return path
    }

    private func slug(for value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.lowercased().unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "scene" : collapsed
    }

    private func formatDuration(_ seconds: Double) -> String {
        if seconds < 1 {
            return String(format: "%.0f ms", seconds * 1000)
        }
        if seconds < 60 {
            return String(format: "%.2fs", seconds)
        }
        let minutes = Int(seconds) / 60
        let remainder = seconds - Double(minutes * 60)
        return String(format: "%dm %.1fs", minutes, remainder)
    }

    private func isTimeout(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        return lowercased.contains("timeout") || lowercased.contains("timed out")
    }

    private func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }

    private func errorDescription(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
