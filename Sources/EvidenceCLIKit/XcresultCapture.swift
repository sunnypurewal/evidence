import Foundation

/// Parsed view of the JSON emitted by
/// `xcrun xcresulttool get test-results summary --path <bundle> --format json`.
///
/// Only the fields the markdown summary needs are decoded; unknown keys are
/// ignored so that future Xcode releases that add fields don't break parsing.
public struct XcresultSummary: Equatable {
    public struct Failure: Equatable {
        public var testName: String
        public var targetName: String
        public var failureText: String
        public var fileLine: String?

        public init(testName: String, targetName: String, failureText: String, fileLine: String? = nil) {
            self.testName = testName
            self.targetName = targetName
            self.failureText = failureText
            self.fileLine = fileLine
        }
    }

    public var title: String
    public var result: String
    public var totalTestCount: Int
    public var passedTests: Int
    public var failedTests: Int
    public var skippedTests: Int
    public var expectedFailures: Int
    public var durationSeconds: Double?
    public var failures: [Failure]

    public init(
        title: String,
        result: String,
        totalTestCount: Int,
        passedTests: Int,
        failedTests: Int,
        skippedTests: Int,
        expectedFailures: Int,
        durationSeconds: Double?,
        failures: [Failure]
    ) {
        self.title = title
        self.result = result
        self.totalTestCount = totalTestCount
        self.passedTests = passedTests
        self.failedTests = failedTests
        self.skippedTests = skippedTests
        self.expectedFailures = expectedFailures
        self.durationSeconds = durationSeconds
        self.failures = failures
    }

    /// Decode the JSON produced by `xcresulttool get test-results summary`.
    public static func parse(_ json: String) throws -> XcresultSummary {
        guard let data = json.data(using: .utf8) else {
            throw CLIError.commandFailed("xcresulttool summary JSON was not valid UTF-8.")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CLIError.commandFailed("xcresulttool summary JSON was not an object.")
        }

        let title = (object["title"] as? String) ?? "Tests"
        let result = (object["result"] as? String) ?? "unknown"
        let totalTestCount = (object["totalTestCount"] as? Int) ?? 0
        let passedTests = (object["passedTests"] as? Int) ?? 0
        let failedTests = (object["failedTests"] as? Int) ?? 0
        let skippedTests = (object["skippedTests"] as? Int) ?? 0
        let expectedFailures = (object["expectedFailures"] as? Int) ?? 0

        let startTime = (object["startTime"] as? Double) ?? Double(object["startTime"] as? Int ?? -1)
        let finishTime = (object["finishTime"] as? Double) ?? Double(object["finishTime"] as? Int ?? -1)
        let durationSeconds: Double?
        if startTime >= 0, finishTime >= 0, finishTime >= startTime {
            durationSeconds = finishTime - startTime
        } else {
            durationSeconds = nil
        }

        // The schema's `testFailures` is documented as a single ref but in
        // practice xcresulttool emits an array of failure entries.
        let rawFailures: [[String: Any]]
        if let array = object["testFailures"] as? [[String: Any]] {
            rawFailures = array
        } else if let single = object["testFailures"] as? [String: Any] {
            rawFailures = [single]
        } else {
            rawFailures = []
        }

        let failures = rawFailures.map { entry -> Failure in
            let testName = (entry["testName"] as? String) ?? "(unknown test)"
            let targetName = (entry["targetName"] as? String) ?? ""
            let failureText = (entry["failureText"] as? String) ?? ""
            return Failure(
                testName: testName,
                targetName: targetName,
                failureText: failureText,
                fileLine: extractFileLine(from: failureText)
            )
        }

        return XcresultSummary(
            title: title,
            result: result,
            totalTestCount: totalTestCount,
            passedTests: passedTests,
            failedTests: failedTests,
            skippedTests: skippedTests,
            expectedFailures: expectedFailures,
            durationSeconds: durationSeconds,
            failures: failures
        )
    }

    /// XCTest failure messages typically begin with `<absolute path>:<line>: ...`.
    /// Pull that prefix out so the markdown summary can render `file:line` for
    /// each failure. Returns `nil` if no recognizable prefix exists.
    private static func extractFileLine(from failureText: String) -> String? {
        let trimmed = failureText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Look at only the first line; multi-line stack traces follow.
        let firstLine = trimmed.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? trimmed
        // Pattern: `<path>:<line>:` where <path> contains `/` and <line> is digits.
        let pieces = firstLine.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard pieces.count >= 2 else { return nil }
        let path = pieces[0]
        let lineNumber = pieces[1]
        guard !path.isEmpty, path.contains("/"), Int(lineNumber) != nil else {
            return nil
        }
        return "\(path):\(lineNumber)"
    }
}

public enum XcresultMarkdown {
    /// Render the summary into the markdown excerpt that ships into
    /// `<ticket>-tests.md`. Suitable for inlining in a PR comment.
    public static func render(_ summary: XcresultSummary, ticket: String) -> String {
        var lines: [String] = []
        lines.append("# \(ticket) — test summary")
        lines.append("")
        lines.append("- Result: **\(summary.result)**")
        lines.append("- Total: \(summary.totalTestCount)")
        lines.append("- Passed: \(summary.passedTests)")
        lines.append("- Failed: \(summary.failedTests)")
        lines.append("- Skipped: \(summary.skippedTests)")
        if summary.expectedFailures > 0 {
            lines.append("- Expected failures: \(summary.expectedFailures)")
        }
        if let duration = summary.durationSeconds {
            lines.append("- Duration: \(formatDuration(duration))")
        }

        if !summary.failures.isEmpty {
            lines.append("")
            lines.append("## Failures")
            for failure in summary.failures.prefix(3) {
                let target = failure.targetName.isEmpty ? "" : " (\(failure.targetName))"
                lines.append("")
                if let fileLine = failure.fileLine {
                    lines.append("- **\(failure.testName)**\(target) — `\(fileLine)`")
                } else {
                    lines.append("- **\(failure.testName)**\(target)")
                }
                let trimmed = failure.failureText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    lines.append("")
                    lines.append("  > \(trimmed.replacingOccurrences(of: "\n", with: "\n  > "))")
                }
            }
            if summary.failures.count > 3 {
                lines.append("")
                lines.append("_…and \(summary.failures.count - 3) more failure(s) in the bundle._")
            }
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Render a fast-fail markdown excerpt for the case where `xcodebuild test`
    /// failed before producing a result bundle (typical for a build error).
    public static func renderBuildError(ticket: String, stderr: String) -> String {
        var lines: [String] = []
        lines.append("# \(ticket) — test summary")
        lines.append("")
        lines.append("- Result: **Build error**")
        lines.append("- No `.xcresult` bundle was produced.")
        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            lines.append("")
            lines.append("```")
            // Cap the excerpt so PR comments stay readable.
            let capped = trimmed.split(separator: "\n").prefix(40).joined(separator: "\n")
            lines.append(capped)
            lines.append("```")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func formatDuration(_ seconds: Double) -> String {
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
}
