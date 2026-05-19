# Terminal Demo Transcript

This is a text version of the 60-second terminal capture. Use it as the source of truth for captions, subtitles, or a README-linked demo when a video or GIF is not available.

```text
$ git clone https://github.com/RiddimSoftware/evidence.git
$ cd evidence
$ swift run evidence -- --help

evidence

Capture repeatable app evidence from real iOS app flows.

Usage:
  evidence <command> [options]

Commands:
  capture-screenshots   Run the configured UI test screenshot workflow.
  resize                Resize screenshots to App Store target dimensions.
  render-marketing      Render a marketing screenshot from a scene file.
  record-preview        Encode an App Preview-compatible video.
  capture-evidence      Capture a one-shot build evidence screenshot.
  upload-screenshots    Upload screenshots to App Store Connect.
  capture-web           Capture full-page Playwright screenshots at configured viewport sizes.
  capture-pr            Run before/after pull request evidence captures.

$ sed -n '1,120p' README.md

`evidence` captures repeatable proof that app changes work.

$ swift run evidence -- capture-pr --help

evidence capture-pr --repo <owner/repo> --pr <number> --plan <json> --output <dir> [--before-ref <ref>] [--after-ref <ref>]

$ sed -n '1,120p' Examples/workflows/capture-pr-on-pr.yml

uses: RiddimSoftware/evidence@v0
with:
  subcommand: capture-pr
  plan: .evidence/pr-home.json
  output-dir: docs/build-evidence/pr-${{ github.event.pull_request.number }}
  comment-on-pr: 'true'
```

End card: `https://github.com/RiddimSoftware/evidence`
