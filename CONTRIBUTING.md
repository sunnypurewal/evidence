# Contributing

Thanks for helping improve Evidence. This repository is intended to be public-facing, so contributions should keep examples, docs, workflows, and generated artifacts safe to publish.

## Before Opening a Pull Request

- Run `swift test`.
- Run `swift run evidence -- --help` when changing CLI docs or command routing.
- Run `actionlint .github/workflows/*.yml Examples/workflows/*.yml` when changing workflows.
- Review changed files for credentials, customer data, private app details, private URLs, local machine paths, and unpublished operational details.

## Public-Safe Examples

Use placeholder app names such as `ExampleOrg/ExampleApp`, `com.example.app`, and `.evidence/pr-home.json`. Do not include real customer apps, private repositories, production credentials, or generated evidence bundles unless they are intentionally sanitized fixtures.

## Reporting Security Issues

Please do not file public issues for vulnerabilities or accidentally exposed secrets. Follow [`SECURITY.md`](SECURITY.md) instead.
