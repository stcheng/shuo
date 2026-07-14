# Contributing to Shuo

Focused bug reports, tests, documentation, translations, accessibility work, and
small code changes are all welcome. By participating, you agree to follow the
[Code of Conduct](CODE_OF_CONDUCT.md).

## Issues

Search existing issues first. For a bug report, include the smallest
reproducible sequence, Shuo version, macOS version, hardware, and whether the
build is an official download or a source build.

Issues are public. Use invented examples and redact logs. Never post API keys,
certificates, recordings, transcripts, correction history, private paths, or
confidential project material. Report security vulnerabilities through the
private channel in [SECURITY.md](SECURITY.md), not in an issue.

## Pull requests

1. Open an issue before starting a large feature, a new dependency, a new cloud
   boundary, or a storage migration.
2. Work on a focused branch and follow [BUILDING.md](BUILDING.md).
3. Add or update tests for behavioral changes.
4. Run `make test-community` for ordinary changes; run `make verify` for
   changes that affect build, storage, privacy, or cross-app input behavior.
5. Explain the user problem, chosen behavior, validation, and any privacy
   impact in the pull request.

Keep generated products, model files, user data, credentials, and local notes
out of commits. Avoid unrelated formatting changes.

## Product boundaries

Shuo's small default workflow matters: hold, speak, release. Advanced behavior
must be independently discoverable and disableable. Do not add telemetry,
advertising, silent uploads, or a new network request without maintainer
agreement and matching privacy documentation.

User-visible work should consider English, Simplified Chinese, Traditional
Chinese, Japanese, keyboard navigation, VoiceOver, Reduce Motion, contrast,
safe failure in target applications, and preservation of local History.

## License and name

Contributions are licensed under GPL-3.0. You must have the right to submit
them. GPL-3.0 does not grant rights to the Shuo name or logo; see
[TRADEMARK.md](TRADEMARK.md).
