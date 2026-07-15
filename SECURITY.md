# Security Policy

## Supported versions

Security fixes are made for the latest published Shuo release. Before reporting
an issue in an older build, please confirm whether it is reproducible in the
latest release.

## Report a vulnerability privately

Use GitHub Private Vulnerability Reporting whenever possible:

<https://github.com/stcheng/shuo/security/advisories/new>

Do not disclose a suspected vulnerability in a public issue, discussion, pull
request, or social-media post before it has been reviewed. If private reporting
is temporarily unavailable, email `contact@bo-rista.com` with “Shuo Security”
in the subject. Do not open a public issue for vulnerability details.

Please include only what is needed to investigate:

- the Shuo version and build number;
- the macOS version and Mac hardware;
- whether the build came from the direct download or a local source build;
- concise reproduction steps and the security impact;
- redacted diagnostics, if they are relevant.

Never include API keys, Keychain contents, signing credentials, private audio,
transcript text, correction history, project vocabulary, or other personal data.
Remove usernames and private file paths from logs before attaching them.

The maintainers will use the private advisory to coordinate investigation,
remediation, disclosure timing, and credit with the reporter.

## Ordinary bugs

For non-security problems, use the repository's bug report form. Its privacy
checklist applies even when the issue does not appear security-sensitive.
