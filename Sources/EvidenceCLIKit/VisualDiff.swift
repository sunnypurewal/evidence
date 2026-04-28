import Foundation

/// Result of comparing one current capture against its baseline.
public struct SceneDiffResult: Equatable {
    /// Path-relative scene id (e.g. `"iPhone 16 Pro Max/home"`).
    public var scene: String
    /// Outcome bucket. Persisted in `diff-report.json` and rendered into the
    /// PR-comment markdown.
    public var status: Status
    /// Differing pixel count from `magick compare -metric AE`. Always 0 when
    /// `status == .baselineMissing` and may be nil when ImageMagick errored.
    public var differingPixels: Int?
    /// Total pixel count of the captured image; used for ratio computation
    /// and as the denominator the threshold is checked against.
    public var totalPixels: Int?
    /// Repo-relative path to the baseline (if any). Useful for the markdown
    /// report so the reader can click through.
    public var baselinePath: String?
    /// Repo-relative path to the actual captured image.
    public var actualPath: String
    /// Repo-relative path to the diff PNG produced by ImageMagick. nil when
    /// no diff was attempted (e.g. baseline missing).
    public var diffPath: String?

    public enum Status: String, Equatable {
        /// Within the configured tolerance.
        case match
        /// Above the configured tolerance — counts as a regression.
        case regression
        /// No baseline image exists for this scene.
        case baselineMissing
    }

    public init(
        scene: String,
        status: Status,
        differingPixels: Int? = nil,
        totalPixels: Int? = nil,
        baselinePath: String? = nil,
        actualPath: String,
        diffPath: String? = nil
    ) {
        self.scene = scene
        self.status = status
        self.differingPixels = differingPixels
        self.totalPixels = totalPixels
        self.baselinePath = baselinePath
        self.actualPath = actualPath
        self.diffPath = diffPath
    }

    /// Differing-pixel ratio (0.0–1.0). Returns 0 when the scene has no
    /// computable totals (missing baseline, or ImageMagick error).
    public var ratio: Double {
        guard let differingPixels, let totalPixels, totalPixels > 0 else {
            return 0
        }
        return Double(differingPixels) / Double(totalPixels)
    }
}

/// Aggregated diff outcome for a whole run. This is what gets serialized to
/// `diff-report.json` and what `evidence diff` uses to derive an exit code.
public struct DiffReport: Equatable {
    public var scenes: [SceneDiffResult]
    /// Threshold in effect when this report was produced. Captured so the
    /// JSON report is self-describing.
    public var threshold: Double

    public init(scenes: [SceneDiffResult], threshold: Double) {
        self.scenes = scenes
        self.threshold = threshold
    }

    /// True when at least one scene exceeded the threshold.
    public var hasRegression: Bool {
        scenes.contains { $0.status == .regression }
    }

    /// True when at least one expected scene is missing a baseline.
    public var hasMissingBaseline: Bool {
        scenes.contains { $0.status == .baselineMissing }
    }

    /// Exit code per the epic's CI contract:
    /// - `0`: every scene matched within threshold.
    /// - `1`: one or more scenes exceeded the threshold.
    /// - `2`: at least one expected scene had no baseline at all.
    /// `1` takes precedence over `2` when both occur — a regression in a
    /// known scene is more actionable than a missing baseline elsewhere.
    public var exitCode: Int32 {
        if hasRegression {
            return 1
        }
        if hasMissingBaseline {
            return 2
        }
        return 0
    }
}

/// Engine that compares baseline PNGs against current captures by shelling out
/// to ImageMagick. All side effects route through `CommandRunning` so tests can
/// substitute a fake.
public struct VisualDiff {
    public var fileManager: FileManager
    public var runner: CommandRunning
    public var magickPath: String

    public init(fileManager: FileManager, runner: CommandRunning, magickPath: String) {
        self.fileManager = fileManager
        self.runner = runner
        self.magickPath = magickPath
    }

    /// Compare every PNG under `currentDirectory` against the equivalent
    /// relative path under `baselineDirectory`. Writes per-scene diff PNGs
    /// (and masked intermediates when `ignoreRegions` is non-empty) into
    /// `diffOutputDirectory` and returns one `SceneDiffResult` per scene.
    ///
    /// Per-device baselines fall out naturally from "match by relative path":
    /// `<currentDirectory>/iPhone 16/home.png` is compared against
    /// `<baselineDirectory>/iPhone 16/home.png`. Devices missing entirely
    /// from the baseline directory surface as `.baselineMissing` for every
    /// scene under that subtree.
    public func compareDirectory(
        currentDirectory: URL,
        baselineDirectory: URL,
        diffOutputDirectory: URL,
        threshold: Double,
        ignoreRegions: [DiffRegion],
        fuzzPercent: Double,
        repoRoot: URL
    ) throws -> [SceneDiffResult] {
        let currentImages = try collectPNGs(
            under: currentDirectory,
            excluding: diffOutputDirectory
        )
        // Sort lexicographically so report output is deterministic across
        // filesystems that don't enumerate alphabetically.
        let sortedRelativePaths = currentImages.sorted()

        try fileManager.createDirectory(at: diffOutputDirectory, withIntermediateDirectories: true)

        var results: [SceneDiffResult] = []
        for relPath in sortedRelativePaths {
            let actualURL = currentDirectory.appendingPathComponent(relPath)
            let baselineURL = baselineDirectory.appendingPathComponent(relPath)
            let diffURL = diffOutputDirectory.appendingPathComponent(relPath)
            try fileManager.createDirectory(
                at: diffURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            // Use the baseline as the scene id, dropping the `.png` extension.
            // This matches how `ScreenshotPlan` names its scenes and keeps
            // the report human-readable when nested under a device folder.
            let scene = (relPath as NSString).deletingPathExtension
            let actualRelative = relativePath(from: repoRoot, to: actualURL)

            guard fileManager.fileExists(atPath: baselineURL.path) else {
                results.append(
                    SceneDiffResult(
                        scene: scene,
                        status: .baselineMissing,
                        actualPath: actualRelative
                    )
                )
                continue
            }

            // When ignore regions are configured, paint black over both
            // images first so ImageMagick never sees the volatile pixels.
            // The masked copies live next to the diff so they're easy to
            // inspect when a teammate asks "did we really mask the clock?"
            let comparisonBaseline: URL
            let comparisonActual: URL
            if ignoreRegions.isEmpty {
                comparisonBaseline = baselineURL
                comparisonActual = actualURL
            } else {
                comparisonBaseline = diffURL.deletingPathExtension().appendingPathExtension("baseline.masked.png")
                comparisonActual = diffURL.deletingPathExtension().appendingPathExtension("actual.masked.png")
                try maskRegions(source: baselineURL, destination: comparisonBaseline, regions: ignoreRegions)
                try maskRegions(source: actualURL, destination: comparisonActual, regions: ignoreRegions)
            }

            let compareArguments = magickCompareArguments(
                baseline: comparisonBaseline.path,
                actual: comparisonActual.path,
                output: diffURL.path,
                fuzzPercent: fuzzPercent
            )
            let result = try runner.run(magickPath, compareArguments)

            // `magick compare -metric AE` writes the differing-pixel count to
            // stderr (or stdout, depending on version). It returns non-zero
            // when differences are found OR when the inputs differ in
            // dimensions; the latter we want to surface explicitly rather
            // than silently calling it a regression.
            let combinedOutput = result.stderr.isEmpty ? result.stdout : result.stderr
            let differing = parseDifferingPixels(from: combinedOutput)
            let total = parseTotalPixels(from: combinedOutput)

            // Exit code 2 from ImageMagick means a real error (e.g. cannot
            // read input) — propagate it as a CLI-level commandFailed so the
            // caller doesn't mistake it for a "regression".
            if result.exitCode == 2 {
                throw CLIError.commandFailed("ImageMagick compare failed for \(relPath). \(combinedOutput)")
            }

            // If we couldn't parse a pixel count but ImageMagick reported
            // success-or-mismatch (0 or 1), assume the count is whatever AE
            // implies: 0 for exit 0, unknown for exit 1. We need at least
            // a count to evaluate the threshold; surface it as a regression
            // with `differingPixels = nil` so the human sees "couldn't
            // parse" rather than a false "match".
            let baselineRelative = relativePath(from: repoRoot, to: baselineURL)
            let diffRelative = relativePath(from: repoRoot, to: diffURL)
            let totalForRatio = total
            let differingForRatio = differing ?? (result.exitCode == 0 ? 0 : nil)

            let ratio: Double
            if let differingForRatio, let totalForRatio, totalForRatio > 0 {
                ratio = Double(differingForRatio) / Double(totalForRatio)
            } else {
                // Unknown pixel count: treat as match only when ImageMagick
                // returned 0 (no differences), otherwise as regression.
                ratio = result.exitCode == 0 ? 0 : .infinity
            }

            let status: SceneDiffResult.Status = ratio <= threshold ? .match : .regression
            results.append(
                SceneDiffResult(
                    scene: scene,
                    status: status,
                    differingPixels: differingForRatio,
                    totalPixels: totalForRatio,
                    baselinePath: baselineRelative,
                    actualPath: actualRelative,
                    diffPath: diffRelative
                )
            )
        }

        return results
    }

    /// Build the canonical `magick compare` argument list. Surfaced for
    /// testability — `EvidenceCLIKitTests` asserts on this exact list.
    public func magickCompareArguments(
        baseline: String,
        actual: String,
        output: String,
        fuzzPercent: Double
    ) -> [String] {
        var arguments: [String] = ["compare", "-metric", "AE"]
        if fuzzPercent > 0 {
            arguments.append(contentsOf: ["-fuzz", "\(fuzzPercent)%"])
        }
        arguments.append(contentsOf: [baseline, actual, output])
        return arguments
    }

    /// Render a markdown report that GitHub renders inline in a PR comment.
    /// Keep the table small enough to avoid the 65k-character body limit on
    /// monstrous test suites — anything beyond ~50 rows gets truncated with a
    /// "see diff-report.json for the full list" footer.
    public static func renderMarkdown(
        report: DiffReport,
        repoRawBaseURL: String?
    ) -> String {
        var lines: [String] = []
        lines.append("## Visual regression report")
        lines.append("")
        if report.scenes.isEmpty {
            lines.append("_No scenes captured — nothing to compare._")
            return lines.joined(separator: "\n") + "\n"
        }

        let regressions = report.scenes.filter { $0.status == .regression }
        let missing = report.scenes.filter { $0.status == .baselineMissing }
        let matches = report.scenes.filter { $0.status == .match }

        // Headline first so the bot-comment summary box on GitHub shows the
        // verdict without expanding the full report.
        if !regressions.isEmpty {
            lines.append("**\(regressions.count) regression(s)** above the \(formatPercent(report.threshold)) threshold.")
        } else if !missing.isEmpty {
            lines.append("**\(missing.count) scene(s) missing a baseline.** Run `evidence accept-baseline` to lock in the current capture.")
        } else {
            lines.append("All \(matches.count) scene(s) match within \(formatPercent(report.threshold)).")
        }
        lines.append("")
        lines.append("| Scene | Status | Differing pixels | Diff |")
        lines.append("| --- | --- | ---: | --- |")

        let truncationLimit = 50
        let truncated = report.scenes.prefix(truncationLimit)
        for scene in truncated {
            let statusEmoji: String
            switch scene.status {
            case .match: statusEmoji = "match"
            case .regression: statusEmoji = "regression"
            case .baselineMissing: statusEmoji = "missing baseline"
            }
            let pixels = scene.differingPixels.map { "\($0)" } ?? "n/a"
            let diffCell: String
            if let diffPath = scene.diffPath {
                if let baseURL = repoRawBaseURL {
                    let url = "\(baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/\(diffPath)"
                    diffCell = "![diff](\(url))"
                } else {
                    diffCell = "`\(diffPath)`"
                }
            } else {
                diffCell = "—"
            }
            lines.append("| `\(scene.scene)` | \(statusEmoji) | \(pixels) | \(diffCell) |")
        }
        if report.scenes.count > truncationLimit {
            lines.append("")
            lines.append("_… \(report.scenes.count - truncationLimit) more scene(s). See `diff-report.json` for the full list._")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Internals

    /// Walk `directory` and return repo-style relative paths (`device/scene.png`).
    /// Anything inside `excluding` (e.g. the diff output directory itself, when
    /// it's nested under `evidence_dir`) is dropped so a re-run never diffs
    /// last run's diff PNGs.
    private func collectPNGs(under directory: URL, excluding: URL) throws -> [String] {
        guard fileManager.fileExists(atPath: directory.path) else {
            return []
        }
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        // FileManager's enumerator resolves filesystem symlinks (e.g.
        // `/var/folders/...` -> `/private/var/folders/...` on macOS), so
        // string-stripping `directory.path` would leave `/private` glued to
        // the front. Compare against the *resolved* directory path instead.
        let prefix = directory.resolvingSymlinksInPath().path + "/"
        let excludedPrefix = excluding.resolvingSymlinksInPath().path + "/"
        var paths: [String] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "png" {
            let last = url.lastPathComponent
            // Skip our own intermediate masked files so a re-run doesn't
            // recursively diff them.
            if last.hasSuffix(".baseline.masked.png") || last.hasSuffix(".actual.masked.png") {
                continue
            }
            let resolvedPath = url.resolvingSymlinksInPath().path
            // Skip everything under the diff-output directory so prior
            // diff PNGs and report files don't feed back into the next walk.
            if resolvedPath.hasPrefix(excludedPrefix) {
                continue
            }
            let relative: String
            if resolvedPath.hasPrefix(prefix) {
                relative = String(resolvedPath.dropFirst(prefix.count))
            } else if url.path.hasPrefix(directory.path + "/") {
                // Fallback for filesystems where symlink resolution yields
                // the same path as input.
                relative = String(url.path.dropFirst(directory.path.count + 1))
            } else {
                relative = last
            }
            paths.append(relative)
        }
        return paths
    }

    private func maskRegions(source: URL, destination: URL, regions: [DiffRegion]) throws {
        // `magick <src> -fill black -draw "rectangle ... rectangle ..." <dst>`
        // is one process call rather than N. Cheap and easy to stub.
        var arguments: [String] = [source.path, "-fill", "black"]
        for region in regions {
            arguments.append(contentsOf: ["-draw", region.magickDrawArgument])
        }
        arguments.append(destination.path)
        let result = try runner.run(magickPath, arguments)
        guard result.exitCode == 0 else {
            throw CLIError.commandFailed("Failed to mask ignore regions on \(source.path). \(result.stderr)")
        }
    }

    private func relativePath(from root: URL, to url: URL) -> String {
        let rootResolved = root.resolvingSymlinksInPath().path
        let urlResolved = url.resolvingSymlinksInPath().path
        let prefix = rootResolved.hasSuffix("/") ? rootResolved : rootResolved + "/"
        if urlResolved.hasPrefix(prefix) {
            return String(urlResolved.dropFirst(prefix.count))
        }
        // Fallback to the original (pre-resolution) string-stripping so non-
        // symlinked filesystems still get a clean relative path.
        let originalPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        if url.path.hasPrefix(originalPrefix) {
            return String(url.path.dropFirst(originalPrefix.count))
        }
        return url.path
    }

    private static func formatPercent(_ value: Double) -> String {
        let percent = value * 100
        if percent >= 1 {
            return String(format: "%.1f%%", percent)
        }
        return String(format: "%.3f%%", percent)
    }

    /// `magick compare -metric AE` emits a single integer: the count of
    /// differing pixels. On versions that print extra context, this picks
    /// the first pure integer token so the parser stays robust.
    private func parseDifferingPixels(from output: String) -> Int? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Int(trimmed) {
            return value
        }
        for token in trimmed.split(whereSeparator: { $0.isWhitespace }) {
            if let value = Int(token) {
                return value
            }
        }
        return nil
    }

    /// Optional total-pixel hint. ImageMagick doesn't print this with `-metric AE`,
    /// but some fakes (and the `RecordingRunner` in tests) supply it via a
    /// `total=N` token so we can compute a ratio without invoking `identify`.
    private func parseTotalPixels(from output: String) -> Int? {
        for token in output.split(whereSeparator: { $0.isWhitespace }) {
            if token.hasPrefix("total=") {
                return Int(token.dropFirst("total=".count))
            }
        }
        return nil
    }
}

/// Helper that resolves a scene image's total pixel count by invoking
/// `magick identify`. Surfaced as a separate type so tests can stub it
/// without touching `VisualDiff`'s primary path.
public struct ImageIdentifier {
    public var runner: CommandRunning
    public var magickPath: String

    public init(runner: CommandRunning, magickPath: String) {
        self.runner = runner
        self.magickPath = magickPath
    }

    /// Returns total pixel count (width × height) for the given image. The
    /// caller is expected to have already verified the file exists.
    public func totalPixels(at url: URL) throws -> Int? {
        let result = try runner.run(magickPath, ["identify", "-format", "%w %h", url.path])
        guard result.exitCode == 0 else {
            return nil
        }
        let parts = result.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
        guard parts.count >= 2,
              let width = Int(parts[0]),
              let height = Int(parts[1]),
              width > 0, height > 0 else {
            return nil
        }
        return width * height
    }
}

/// Encoder for `diff-report.json`. Kept Foundation-only so the tool ships
/// without third-party JSON dependencies.
public enum DiffReportEncoder {
    public static func encode(_ report: DiffReport) throws -> Data {
        let payload: [String: Any] = [
            "threshold": report.threshold,
            "scenes": report.scenes.map { scene -> [String: Any] in
                var entry: [String: Any] = [
                    "scene": scene.scene,
                    "status": scene.status.rawValue,
                    "actual": scene.actualPath
                ]
                if let differing = scene.differingPixels {
                    entry["differing_pixels"] = differing
                }
                if let total = scene.totalPixels {
                    entry["total_pixels"] = total
                }
                if let baseline = scene.baselinePath {
                    entry["baseline"] = baseline
                }
                if let diff = scene.diffPath {
                    entry["diff"] = diff
                }
                return entry
            }
        ]
        return try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )
    }
}
