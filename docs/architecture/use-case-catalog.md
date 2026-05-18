# Evidence Use-Case Catalog

This catalog names the application-level workflows that should stay stable as
Evidence grows. It is intentionally compact: entries describe behavior and
boundaries, not every helper function.

## PR Evidence

The PR evidence slice compares a pull request against its base revision and
produces repeatable proof for review. High-level policy belongs in named
use-case/application files. `EvidenceCLI.swift` should parse CLI arguments and
dispatch to those use cases; it should not own Git, GitHub, Xcode, simulator, or
report-rendering policy.

### CapturePullRequestEvidence

Actor: Developer or CI workflow

Goal: Capture review-ready proof for a pull request by resolving the compared
revisions, preparing isolated checkouts, building each revision, executing the
configured evidence plan, and rendering a report.

Inputs: Repository path, pull request identifier, base revision, head revision,
`.evidence.toml`, output directory, comparison mode, and optional GitHub comment
settings.

Outputs: Pull request evidence report, captured artifacts, comparison metadata,
and a process exit result suitable for CI.

Entities / values: `PullRequestEvidenceRequest`, `PullRequestEvidenceResult`,
`PullRequestComparison`, `EvidenceRevision`, `EvidenceArtifact`,
`EvidenceReport`.

Ports: `PullRequestComparisonResolving`, `ComparisonWorktreePreparing`,
`RevisionBuilding`, `EvidencePlanExecuting`, `PullRequestEvidenceReporting`,
`FileSystemWriting`, `Clock`.

Primary adapters: Git command adapter, GitHub pull request adapter, Xcode build
adapter, simulator capture adapter, filesystem artifact store, markdown report
renderer.

Current implementation: Planned for the PR evidence MVP outside the CLI router,
for example under `Sources/EvidenceCLIKit/PullRequestEvidence/`. The CLI command
router in `Sources/EvidenceCLIKit/EvidenceCLI.swift` should only parse
`capture-pr` arguments and call this use case.

### ResolvePullRequestComparison

Actor: `CapturePullRequestEvidence`

Goal: Resolve the exact before and after revisions that should be compared for a
pull request.

Inputs: Pull request identifier or URL, repository remote, current branch,
GitHub event environment, and optional explicit base/head overrides.

Outputs: `PullRequestComparison` containing base/head revision identities,
labels, repository metadata, and PR metadata needed for reporting.

Entities / values: `PullRequestComparison`, `EvidenceRevision`,
`PullRequestReference`, `RepositoryIdentity`.

Ports: `PullRequestMetadataLoading`, `GitRevisionResolving`,
`EnvironmentReading`.

Primary adapters: GitHub REST or CLI adapter, git command adapter, GitHub
Actions environment adapter.

Current implementation: Planned for the PR evidence MVP as an application
service used by `CapturePullRequestEvidence`; it should not be embedded in
`EvidenceCLI.swift`.

### PrepareComparisonWorktrees

Actor: `CapturePullRequestEvidence`

Goal: Create or locate isolated before/after worktrees so builds and captures do
not mutate the caller's checkout.

Inputs: `PullRequestComparison`, repository path, scratch/cache directory, and
cleanup policy.

Outputs: `ComparisonWorktrees` with before/after paths, checked-out revisions,
and cleanup instructions.

Entities / values: `ComparisonWorktrees`, `PreparedWorktree`,
`EvidenceRevision`, `WorktreeCleanupPolicy`.

Ports: `GitWorktreeManaging`, `FileSystemWriting`, `Clock`.

Primary adapters: git worktree command adapter and filesystem scratch-directory
adapter.

Current implementation: Planned for the PR evidence MVP as a worktree
preparation service. The implementation should live behind a git port so
worktree policy remains testable without shelling out from value objects.

### BuildRevisionForEvidence

Actor: `CapturePullRequestEvidence`

Goal: Build one prepared revision in the way required before screenshots,
xcresult summaries, or other evidence artifacts can be captured.

Inputs: Prepared worktree, `.evidence.toml`, build destination, scheme,
workspace/project selection, and result bundle settings.

Outputs: Build status, build log excerpt, optional result bundle location, and
diagnostics for the final report.

Entities / values: `BuildRevisionRequest`, `BuildRevisionResult`,
`PreparedWorktree`, `EvidenceBuildDiagnostics`.

Ports: `RevisionBuilding`, `CommandRunning`, `FileSystemWriting`.

Primary adapters: Xcode command adapter using `xcrun xcodebuild`, result bundle
artifact adapter, filesystem log writer.

Current implementation: Existing Xcode argument construction for screenshot and
xcresult capture is in `Sources/EvidenceCLIKit/EvidenceCLI.swift`; the PR
evidence path should extract new build policy into a named adapter/use-case file
rather than adding more policy to the CLI router.

### ExecuteEvidencePlan

Actor: `CapturePullRequestEvidence`

Goal: Run the configured Evidence capture plan against a prepared revision and
return normalized artifacts for comparison and reporting.

Inputs: Prepared worktree, `EvidenceConfig`, capture mode, simulator/device
destination, and artifact output directory.

Outputs: Captured screenshots, xcresult summaries, web screenshots, command
logs, and normalized artifact descriptors.

Entities / values: `EvidencePlanExecution`, `EvidenceArtifact`,
`EvidenceCaptureMode`, `EvidenceConfig`.

Ports: `EvidencePlanExecuting`, `CommandRunning`, `FileSystemWriting`,
`SimulatorCapturing`.

Primary adapters: Evidence CLI command adapter, simulator screenshot adapter,
Playwright web capture adapter, filesystem artifact store.

Current implementation: Existing single-revision capture commands live in
`Sources/EvidenceCLIKit/EvidenceCLI.swift`. PR evidence orchestration should
call through a plan-execution boundary instead of duplicating command policy in
the `capture-pr` switch case.

### RenderPullRequestEvidenceReport

Actor: `CapturePullRequestEvidence`

Goal: Convert before/after artifacts, build results, and comparison metadata
into a concise report that reviewers can read in a pull request.

Inputs: `PullRequestComparison`, before/after artifacts, build/test summaries,
diff results, repository raw URL settings, and timestamp.

Outputs: Markdown report body, local report file, and optional GitHub comment
payload.

Entities / values: `EvidenceReport`, `EvidenceReportSection`,
`EvidenceArtifact`, `PullRequestComparison`, `EvidenceRevision`.

Ports: `PullRequestEvidenceReporting`, `MarkdownRendering`, `PullRequestCommentPosting`,
`Clock`.

Primary adapters: Markdown report renderer, GitHub issue comment adapter,
filesystem report writer.

Current implementation: Existing markdown snippets are generated inside
`Sources/EvidenceCLIKit/EvidenceCLI.swift` for single-revision evidence and web
capture. PR evidence report rendering should move into a dedicated renderer so
the CLI router remains a thin adapter.

## Architecture Guardrails

`Tests/EvidenceCLIKitTests/ArchitectureBoundaryTests.swift` enforces the PR
evidence ratchet:

- `capture-pr` routing in `EvidenceCLI.swift` must stay thin and must not own
  Git, GitHub, Xcode, simulator, or comparison policy.
- PR evidence value objects must not import XCTest, GitHub-specific APIs, Xcode
  process APIs, or simctl wrappers.
- The `Evidence` library target must not import `EvidenceCLIKit`; dependencies
  point inward from CLI adapters to reusable library code.
