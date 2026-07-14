# Public Repository Plan

Updated: 2026-07-14

Shuo 1.0 will publish the macOS application source under GPL-3.0. The public
GitHub repository becomes the single canonical home for source, website,
issues, releases, update metadata, and contributor history. The earlier
website-only 0.1 plan is superseded.

## Decisions

- **Source license:** GNU General Public License, version 3 (`GPL-3.0-only`).
- **Brand:** the Shuo name and logo are not licensed under GPL-3.0; public forks
  follow the root `TRADEMARK.md` policy.
- **History:** publish a newly curated history from a reviewed source snapshot,
  not the private development history.
- **Repository topology:** maintain one canonical public repository rather than
  separate website and application-source repositories.
- **Release provenance:** only maintainer-signed, notarized artifacts published
  through the official release process are official Shuo releases.

The source is open for use, study, modification, and redistribution under the
GPL. Official signing credentials and the Shuo marks remain outside that grant.

## Canonical public contents

The public repository includes:

- `App/`, `Config/`, the Xcode project, and source-bearing resources;
- tests and the bilingual evaluation corpus;
- reproducible build, verification, packaging, and release scripts that contain
  no secrets;
- `web/`, including privacy, release notes, update feed, and public manifest;
- issue templates, CI, GitHub Pages workflow, security policy, and contributor
  governance;
- `LICENSE`, `TRADEMARK.md`, third-party notices, build instructions, and the
  architecture overview; and
- user-facing technical documentation needed to understand privacy, storage,
  providers, and model behavior.

Public source releases must be sufficient to build a functional community
edition without access to the maintainer's signing credentials.

## Content that remains private or generated

Do not publish:

- Developer ID private keys, certificates, provisioning profiles, notarization
  credentials, Sparkle private keys, API keys, or Keychain exports;
- private dSYMs, crash reports, user recordings, transcripts, correction data,
  project indexes, model downloads, settings exports, or diagnostics;
- `NOTES.md`, assistant collaboration context, personal planning logs, and
  unpublished product or security triage;
- `DerivedData/`, `build/`, `dist/`, caches, screenshots, and local test output;
  or
- third-party material that Shuo may redistribute in a signed binary but does
  not have the right to publish as repository source.

Private planning can live in a separate private workspace, but it must not
become a second divergent source repository. Product code intended for release
lands in the canonical public repository.

## Curated-history cutover

The public history begins from a deliberately reviewed 1.0 source snapshot. It
must not copy the private Git history, because deleted credentials, personal
paths, recordings, experiments, or private notes may still exist in old Git
objects even when absent from the current tree.

Perform the cutover in a disposable staging clone, not by rewriting the only
working repository:

1. Freeze a candidate commit in the private working tree and record its commit
   hash internally for provenance.
2. Create a fresh staging directory containing only the reviewed public
   allowlist. Preserve file modes and symlinks deliberately.
3. Confirm that generated and private paths are absent before initializing its
   Git history.
4. Run secret, privacy, license, and large-file audits against both the staged
   tree and the exact commit to be published.
5. Build and test from a brand-new clone of the staged repository without
   private caches or credentials.
6. Create a small, readable initial history. The first source commit should
   identify the corresponding private provenance hash internally but must not
   expose private repository URLs or notes.
7. Publish the staged history to the one canonical public repository, enable
   branch protection and private vulnerability reporting, then tag 1.0 only
   after CI succeeds.

If a website-only history already exists in that repository, preserve useful
public authorship where practical, but do the source-history replacement in a
staging clone and review the exact force-update before changing the remote.
Announce the cutover clearly. Never improvise history rewriting in the release
working copy.

## Source-safety audit

Before the initial source push, inspect at least these classes of data:

- credentials and key material: API-key patterns, tokens, private keys,
  certificates, passwords, notarization profiles, and Sparkle secrets;
- personal data: home-directory paths, email addresses not intended as project
  contact information, machine names, recordings, transcript fragments, and
  copied customer or project text;
- release configuration: official public keys and Team IDs may be public, but
  private signing material and local Keychain labels must not be exported;
- generated files and large blobs: models, archives, DMGs, ZIPs, audio, dSYMs,
  screenshots, DerivedData, and caches; and
- source ownership: copied snippets, generated resources, fonts, sounds,
  datasets, model metadata, and bundled third-party licenses.

Use more than one scanner and manually inspect every finding. A clean scanner
result is evidence, not proof. Run `git status --short`, inspect the staged file
list, and test the final commit rather than an adjacent working directory.

## Dependency and license audit

For each dependency or bundled resource, record:

- upstream project and pinned version or revision;
- license and compatibility with GPL-3.0;
- whether it is linked, invoked as a separate executable, downloaded by the
  user, or copied into the application bundle;
- required notice or source-offer obligations; and
- where its exact license text appears in source and packaged applications.

At minimum, recheck Sparkle, whisper.cpp, Emoji/CLDR-derived data, generated
sounds and icons, local-model metadata, and every optional cloud SDK or sample.
A model's code license does not automatically cover its weights; downloaded
models need their own recorded provenance and terms.

Do not merge a new dependency until its license, data flow, update mechanism,
and maintenance cost are understood. Keep `THIRD_PARTY_NOTICES.md` and bundled
notices synchronized with the actual artifact.

## Community identity boundary

A source build must not silently collide with an installed official release.
The supported source-build path is the shared `ShuoCommunity` scheme and
`make build-community`. This is not a separate application target: the scheme
reuses the `Shuo` target with its Community build configuration. It produces
**Shuo Community** with an ad-hoc signature, bundle ID `org.shuo.community`,
Application Support directory `Shuo Community`, and Keychain prefix
`org.shuo.community`. It requires no paid developer account, does not link
Sparkle, and has no official update feed. Contributors use
`make test-community` for the default test path. The build must remain visually
and textually identifiable as a community build when redistributed.

The official binary keeps the Shuo marks, official bundle identity, Developer
ID signature, Apple notarization, Sparkle public key, and production update
feed. The source repository contains public verification material but no
private release credential.

## Verification gates before 1.0 source publication

The cutover is ready only when all of the following are true:

- root GPL-3.0 license, trademark policy, contribution guide, code of conduct,
  build guide, architecture guide, security policy, and third-party notices are
  present and mutually consistent;
- a clean clone builds without the maintainer's Apple account or private
  credentials using the documented community path;
- unit tests pass and CI validates the exact public tree;
- secret and privacy scans have no unresolved findings;
- dependency licenses and model provenance have been reviewed;
- official and community bundle, Keychain, update, and storage identities do
  not collide;
- no local user data is required, migrated, reset, or deleted to build the
  source;
- website Privacy, source README, application behavior, and release notes make
  the same Local/cloud claims; and
- the signed/notarized 1.0 artifacts correspond to the tagged public source,
  with checksums and public update metadata verified.

This repository cutover plan does not replace the maintainer's separate manual
release-acceptance checklist.

## Ongoing public workflow

After cutover:

1. Develop release-bound source through branches and pull requests against the
   canonical public repository.
2. Keep private notes outside public source and reference public issue numbers
   rather than maintaining duplicate code plans.
3. Require CI and review for the protected default branch.
4. Tag official versions only from reviewed, clean commits.
5. Build official artifacts from the tag, verify signatures, notarization,
   checksums, appcast metadata, license notices, and source correspondence.
6. Upload only the exact public artifact allowlist; keep dSYMs and operational
   credentials private.
7. Publish website, release notes, source tag, binaries, and update feed as one
   coherent release.

A later commercial service, hosted provider, or additional platform can use a
separate operational repository where necessary, but the macOS client and its
public build path remain canonical here.
