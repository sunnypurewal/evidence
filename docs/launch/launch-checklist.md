# Launch Checklist

Primary URL: <https://github.com/RiddimSoftware/evidence>

## Pre-Launch

- Confirm the repository is ready to be made public after the hygiene PR merges.
- Confirm the README quick start still works:

```sh
swift test
swift run evidence -- --help
```

- Confirm workflow lint passes:

```sh
actionlint .github/workflows/*.yml Examples/workflows/*.yml
```

- Confirm the GitHub Marketplace listing points to the current README.
- Confirm repository metadata matches [`docs/repository-metadata.md`](../repository-metadata.md).
- Prepare one screenshot or short GIF for the article and X/Twitter thread.

## Launch Window

1. Change the repository visibility to public.
2. Verify the license badge, description, topics, and homepage in GitHub settings.
3. Publish the launch article.
4. Post the X/Twitter thread.
5. Publish the dev.to cross-post.
6. Submit the Hacker News post.
7. Add the first HN comment from `hacker-news.md`.
8. Watch replies for setup friction, confusing positioning, and missing examples.

## Follow-Up

- Turn repeated questions into README or troubleshooting updates.
- Label good first issues for small docs, examples, and app-integration improvements.
- Capture top objections and add them to future docs.
- After 24 hours, summarize results: stars, issues opened, comments, reposts, and docs changes made.
