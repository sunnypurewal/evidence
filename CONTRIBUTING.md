# Contributing

Thanks for helping improve `evidence`. This project is public, so keep examples, issues, pull requests, logs, screenshots, and config snippets free of private app data, secrets, customer information, unreleased roadmap details, and internal operational context.

## Local Setup

Requirements:

- macOS 14 or newer
- Xcode with command line tools
- Swift Package Manager
- ImageMagick for screenshot resizing and marketing PNG rendering
- ffmpeg for preview video encoding

Run the core checks:

```sh
swift test
swift run evidence -- --help
```

## Pull Requests

Before opening a pull request:

- Keep changes focused and public-safe.
- Add or update tests for behavior changes.
- Update README or docs when command behavior, config, or integration steps change.
- Run `swift test`.
- Include the command output or a concise summary in the PR description.

## Issues

Use the issue templates for bugs, feature requests, and app-onboarding questions. Include enough detail to reproduce the behavior, but do not paste private app credentials, proprietary source, unreleased screenshots, or internal ticket links.

## API Stability

Until `1.0`, source-compatible changes are preferred but not guaranteed. Public API changes should be documented in `docs/versioning.md` and called out in release notes.
