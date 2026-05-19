# Hacker News Submission

## Title Options

1. Show HN: Evidence - repeatable proof artifacts for app changes
2. Show HN: I built an open-source Swift tool for app proof artifacts
3. Evidence: screenshots, videos, manifests, and reports from real app runs

Recommended title: **Show HN: Evidence - repeatable proof artifacts for app changes**

## URL

https://github.com/RiddimSoftware/evidence

## First Comment Draft

I built Evidence because I kept seeing the same release ritual on app projects: after tests pass, someone still launches the app and manually taps through the important flow before a PR or release goes out.

That check is useful, but the proof usually disappears. It lives in a local screenshot, a short recording, or a chat thread.

Evidence is my attempt to make that step reproducible. It is a Swift package plus CLI. You describe real app states as screenshot plans with anchors and navigation, then the CLI writes artifacts to stable paths:

- screenshots from real app runs
- one-shot build evidence
- `.xcresult` summaries
- before/after pull request evidence reports
- preview-video source workflows
- App Store screenshot upload dry-runs
- Playwright-backed web screenshots

The app keeps its own plans, launch flags, fixtures, screenshots, and generated artifacts. There is no hosted service and no screenshot storage outside the repo or CI artifact store unless you choose to upload artifacts somewhere.

It is early, intentionally small, and iOS-first. I would especially like feedback from teams that already have UI tests but still rely on manual screenshot or release walkthroughs.
