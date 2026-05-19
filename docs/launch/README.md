# Launch Materials

This folder contains public launch drafts for Evidence. The copy is aligned with the current CLI surface from `swift run evidence -- --help`.

- [`introducing-evidence.md`](introducing-evidence.md): long-form launch article draft.
- [`devto-cross-post.md`](devto-cross-post.md): shorter dev.to adaptation.
- [`x-thread.md`](x-thread.md): 10-post X/Twitter thread draft.
- [`hacker-news.md`](hacker-news.md): HN title options and first comment.
- [`demo-terminal-capture.txt`](demo-terminal-capture.txt): 60-second terminal demo script.
- [`demo-terminal-transcript.md`](demo-terminal-transcript.md): text transcript for captions or subtitles.
- [`launch-checklist.md`](launch-checklist.md): ordered launch checks.

Before publishing, run:

```sh
swift test
swift run evidence -- --help
actionlint .github/workflows/*.yml Examples/workflows/*.yml
```
