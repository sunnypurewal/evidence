# Terminal Demo Transcript

This is a text version of the 60-second terminal capture. Use it as the source of truth for captions, subtitles, or a README-linked demo when a video/GIF is not available.

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
  diff                  Compare current captures against committed baselines.
  accept-baseline       Promote the latest run into the baseline directory.
  upload-screenshots    Upload screenshots to App Store Connect.

$ sed -n '1,80p' README.md

`evidence` captures repeatable proof that app flows work, using real iOS app runs instead of manual replay.

$ swift run evidence -- diff --help

evidence diff [--baseline <dir>] [--current <dir>] [--output <dir>] [--report <path>] [--markdown <path>] [--threshold <number>]

Compares the latest screenshot run against a directory of committed baselines.

$ swift run evidence -- upload-screenshots --help

evidence upload-screenshots [--dry-run] [--locale en-US]

Uploads PNG screenshots from evidence_dir to App Store Connect screenshot slots for the configured app.

$ sed -n '1,120p' Examples/workflows/capture-evidence-on-pr.yml

uses: RiddimSoftware/evidence@v0
with:
  subcommand: capture-evidence
  ticket: ${{ github.event.pull_request.title }}
  comment-on-pr: 'true'
```

End card: `https://github.com/RiddimSoftware/evidence`
