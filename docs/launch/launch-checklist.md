# Launch Checklist

Designated launch window: **Tuesday, May 12, 2026, 10:00-14:00 America/Toronto**.

Primary URL: <https://github.com/sunnypurewal/evidence>

Blog URL placeholder: `https://example.com/blog/introducing-evidence`

## Pre-Launch

- Replace the blog URL placeholder in `x-thread.md` with the final published blog URL.
- Record the terminal demo using `demo-terminal-capture.txt`.
- Confirm the README quick start still works:

```sh
swift test
swift run evidence -- --help
```

- Confirm the GitHub Marketplace listing points to the current README.
- Confirm all social drafts point at the same canonical blog URL and GitHub repo URL.
- Prepare one screenshot or short GIF for the blog and X/Twitter thread.

## Launch Window

1. Publish the blog post from `introducing-evidence.md`.
2. Update `x-thread.md` with the final blog URL.
3. Post the X/Twitter thread.
4. Publish the dev.to cross-post from `devto-cross-post.md`.
5. Submit the Hacker News post using the recommended title in `hacker-news.md`.
6. Add the first HN comment from `hacker-news.md`.
7. Watch replies for setup friction, confusing positioning, and missing examples.

## Follow-Up

- Turn repeated questions into README or troubleshooting updates.
- Label good first issues for small docs, examples, and app-integration improvements.
- Capture top objections and add them to future docs.
- After 24 hours, summarize results: stars, issues opened, comments, reposts, and docs changes made.
