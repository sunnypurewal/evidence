# X/Twitter Thread

Blog link placeholder: `https://example.com/blog/introducing-evidence`

1. I released `evidence`: an open-source Swift package and CLI for proof artifacts from real iOS app flows. It turns manual release walkthroughs into screenshots, diffs, and build evidence. https://example.com/blog/introducing-evidence

2. Screenshots are easy. Trustworthy screenshots are harder. Evidence records which app state was captured, which anchors were required, and where the artifact lives. https://example.com/blog/introducing-evidence

3. A screenshot plan describes scenes with anchors and navigation. If the expected UI does not appear, the test fails before writing a misleading image. https://example.com/blog/introducing-evidence

4. The CLI covers the release chores: capture screenshots, capture one-shot build evidence, compare against baselines, render App Store assets, and dry-run uploads. https://example.com/blog/introducing-evidence

5. `evidence diff` writes visual diff PNGs, markdown for PR comments, and a JSON report. It is a small visual-regression layer over the captures you already produce. https://example.com/blog/introducing-evidence

6. `capture-evidence` can pair a simulator screenshot with an `.xcresult` summary, so reviewers get readable proof even when a build or UI test fails. https://example.com/blog/introducing-evidence

7. There is a GitHub Action for macOS runners. It builds the CLI, checks runner compatibility, sets up ImageMagick/ffmpeg, and can comment artifacts on PRs. https://example.com/blog/introducing-evidence

8. Evidence keeps app-specific plans, launch flags, baselines, screenshots, and App Store metadata in the consuming app repo. No hosted service required. https://example.com/blog/introducing-evidence

9. The best first flow to automate is the one someone still checks manually before every release: onboarding, purchase, import, settings, or release notes. https://example.com/blog/introducing-evidence

10. Try it here: https://github.com/sunnypurewal/evidence. The package is MIT licensed, public, and ready for issues, examples, and small first contributions. https://example.com/blog/introducing-evidence
