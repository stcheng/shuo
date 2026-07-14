# Contributing to Shuo

Thank you for helping improve Shuo. Contributions can include focused bug
reports, reproducible tests, documentation, translations, accessibility work,
performance improvements, and code changes.

By participating, you agree to follow [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
Security vulnerabilities belong in the private process described in
[SECURITY.md](SECURITY.md), not in a public issue.

## Before opening an issue

Search existing issues first. For a bug, include the smallest reproducible
sequence, Shuo version, macOS version, hardware, and whether the build is an
official download or a source build.

Issues are public. Never attach or paste:

- API keys, Keychain contents, certificates, signing material, or tokens;
- private audio, transcripts, correction history, or project vocabulary;
- usernames, private paths, or unredacted diagnostic exports; or
- confidential source code encountered while using project vocabulary.

Use invented sample text and redact logs before posting them.

## Proposing a change

A small, well-scoped pull request is usually easiest to review. Open an issue
before investing in a large feature, a new cloud provider, a storage migration,
a privacy-boundary change, or a new dependency. This lets maintainers confirm
the product direction and data-handling expectations first.

For user-visible changes, account for:

- English, Simplified Chinese, Traditional Chinese, and Japanese localization;
- VoiceOver, keyboard navigation, Reduce Motion, and adequate contrast;
- Local-only behavior and explicit cloud boundaries;
- safe failure when Shuo cannot confirm the target application; and
- preservation of existing local history, recordings, and settings.

Do not add app telemetry, advertising, silent data upload, or a new network
request without prior maintainer agreement and corresponding privacy
documentation.

If this is your first contribution, start with an issue carrying the
`good first issue` label. Those tasks should name likely files, preserve a small
scope, include objective acceptance checks, and require no private credentials
or release-account access. Comment on the issue before starting so work is not
duplicated.

Maintainers prepare bounded starter tasks in
[docs/good-first-issues.md](docs/good-first-issues.md) before creating and
labeling the corresponding public issues.

## Development workflow

1. Fork the repository and create a focused branch.
2. Follow [BUILDING.md](BUILDING.md) to build the source.
3. Add or update tests for behavioral changes.
4. Run `make test-community` for ordinary changes and `make verify` when
   changing build, storage, privacy, release, or cross-target behavior. The
   Community path uses ad-hoc signing and requires no paid developer account.
5. Run `git diff --check` and review the complete diff before committing.
6. Open a pull request that explains the user problem, chosen behavior, tests,
   privacy impact, and screenshots for visible UI changes.

Keep generated build products, downloaded models, real user data, credentials,
and local planning notes out of commits. Avoid drive-by formatting changes in
unrelated files.

## Code and dependency expectations

Prefer clear Swift and small components over new abstraction layers. Keep UI,
state orchestration, services, and persistent models separated according to
[ARCHITECTURE.md](ARCHITECTURE.md). Changes that cross a privacy boundary should
make that boundary explicit in code and tests.

New dependencies must have a GPL-3.0-compatible license, a clear maintenance
and security story, and a user-visible benefit that justifies their cost.
Document their license and attribution in `THIRD_PARTY_NOTICES.md` and the
bundled third-party notices when applicable. Do not commit model weights or
large generated assets without explicit approval.

## Licensing contributions

The repository is licensed under GPL-3.0. By submitting a contribution, you
certify that you have the right to submit it and agree that it may be
distributed under GPL-3.0. Do not submit employer-owned or third-party code
without the necessary permission. No contributor license agreement is
currently required.

The GPL license does not grant rights to the Shuo name or logo. See
[TRADEMARK.md](TRADEMARK.md). A merged contribution does not make a fork or
community binary an official Shuo release.

## Review and release authority

Maintainers may request changes, close work that does not fit the project, or
delay a feature until its privacy, migration, and maintenance costs are clear.
Only maintainers can designate a build as an official Shuo release, sign it
with the official Developer ID, notarize it, or publish it to the official
update feed. Every official binary must be built from and have corresponding
source at the exact matching public Git tag; uncommitted or private source
changes cannot be included in an official artifact.
