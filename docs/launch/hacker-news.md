# Hacker News Submission

## Title Options

1. Show HN: evidence - repeatable proof artifacts for iOS app flows
2. Show HN: I built an open-source Swift tool for release proof artifacts
3. evidence: screenshots, visual diffs, and build evidence from real iOS app flows

Recommended title: **Show HN: evidence - repeatable proof artifacts for iOS app flows**

## URL

https://github.com/sunnypurewal/evidence

## First Comment Draft

I built evidence because I kept seeing the same release ritual on iOS projects: after tests pass, someone still launches the app and manually taps through the important flow before a PR or release goes out.

That check is useful, but the proof usually disappears. It lives in a local screenshot, a short recording, or a chat thread.

Evidence is my attempt to make that step reproducible. It is a Swift package plus CLI. You describe real app states as XCUITest-backed screenshot plans with anchors and navigation, then the CLI writes artifacts to stable paths:

- screenshots from real app runs
- one-shot build evidence
- `.xcresult` summaries
- visual diff reports against baselines
- App Store screenshot upload dry-runs
- marketing render and preview-video source workflows

The app keeps its own plans, launch flags, fixtures, baselines, and generated artifacts. There is no hosted service and no screenshot storage outside the repo unless you choose to upload artifacts in CI.

It is early, intentionally small, and iOS-first. I would especially like feedback from teams that already have UI tests but still rely on manual screenshot/release walkthroughs.
