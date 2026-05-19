# X/Twitter Thread

1. I released Evidence: an open-source Swift package and CLI for proof artifacts from real app runs. It turns manual release walkthroughs into screenshots, videos, manifests, and reports. https://github.com/RiddimSoftware/evidence

2. Screenshots are easy. Trustworthy screenshots are harder. Evidence records which app state was captured, which anchors were required, and where the artifact lives. https://github.com/RiddimSoftware/evidence

3. A screenshot plan describes scenes with anchors and navigation. If the expected UI does not appear, the test fails before writing a misleading image. https://github.com/RiddimSoftware/evidence

4. The CLI covers release chores: capture screenshots, capture one-shot build evidence, capture before/after PR evidence, render App Store assets, encode preview videos, and dry-run screenshot uploads. https://github.com/RiddimSoftware/evidence

5. `capture-pr` runs the same evidence plan against before and after revisions, then writes a manifest and report so reviewers can inspect what changed. https://github.com/RiddimSoftware/evidence

6. `capture-evidence` can pair a simulator screenshot with an `.xcresult` summary, so reviewers get readable proof even when a build or UI test fails. https://github.com/RiddimSoftware/evidence

7. There is a GitHub Action for GitHub-hosted runners. It builds the CLI, checks runner compatibility, sets up dependencies, and can comment artifacts on PRs. https://github.com/RiddimSoftware/evidence

8. Evidence keeps app-specific plans, launch flags, screenshots, and App Store metadata in the consuming app repo. No hosted service required. https://github.com/RiddimSoftware/evidence

9. The best first flow to automate is the one someone still checks manually before every release: onboarding, purchase, import, settings, or release notes. https://github.com/RiddimSoftware/evidence

10. Try it here: https://github.com/RiddimSoftware/evidence. The package is MIT licensed and open to issues, examples, and small first contributions.
