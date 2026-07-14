# Building Shuo

This guide covers development and community source builds. It does not grant
access to the official signing, notarization, or Sparkle update credentials.
See [TRADEMARK.md](TRADEMARK.md) before redistributing a build.

The corresponding source for an official Shuo binary is the exact matching
public Git tag. Official artifacts must not contain application-source changes
that are absent from that tag.

## Requirements

- A Mac running macOS 14 or later
- A current stable Xcode release capable of building the project, with its
  command-line tools selected
- Git
- CMake, `curl`, `shasum`, and `tar` when preparing the bundled whisper.cpp
  runtime or packaging a complete direct build
- Internet access for the initial Swift Package Manager resolution and first
  whisper.cpp source download

Install Xcode from Apple, launch it once to accept its license, then verify the
active command-line tools:

```sh
xcodebuild -version
xcode-select -p
```

CMake may be installed with your preferred package manager. Homebrew is not a
runtime requirement for Shuo users and is not required merely to compile the
Swift targets.

The full repository gates additionally use `jq`, `rg` (ripgrep), Python 3,
`xmllint`, `rsync`, and Gitleaks. macOS supplies several of these; one convenient
maintainer setup for the others is:

```sh
brew install cmake jq ripgrep gitleaks
```

These tools are required by `make verify` or `make scan-secrets`, not by people
installing the finished Shuo app.

## Clone and inspect

```sh
git clone https://github.com/stcheng/shuo.git
cd shuo
open Shuo.xcodeproj
```

Review [LICENSE](LICENSE), [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), and
the dependency changes in `Shuo.xcodeproj` before distributing a binary.
Downloaded speech models are not stored in this repository and may have their
own terms.

## Build targets, schemes, and configurations

The repository contains two application targets:

- `Shuo`: the sandbox-compatible application target. Its ordinary
  Debug/Release configurations support tests and future distribution
  experiments; its Community configuration supplies the isolated source-build
  identity. It does not embed Sparkle.
- `ShuoDirect`: direct-download target with Sparkle support. Official releases
  are built from this target, then separately signed and notarized.

`ShuoCommunity` is a shared scheme, not a third application target. It builds
the `Shuo` target with the Community configuration as **Shuo Community**, bundle
ID `org.shuo.community`, Application Support directory `Shuo Community`, and
Keychain prefix `org.shuo.community`. It does not link Sparkle or use the
official update feed, so it can coexist with an official installation.

For an ordinary source checkout, build the community scheme:

```sh
make build-community
```

This is the recommended contributor build. The Community configuration uses an
ad-hoc signature and requires neither a paid Apple Developer Program membership
nor the maintainer's signing credentials.

Build the direct target from Terminal:

```sh
make build
```

Build the sandbox-compatible target:

```sh
make build-store
```

The first Sparkle-enabled build resolves the pinned Swift package. Packaging a
complete direct build also prepares the pinned whisper.cpp runtime; that step
requires CMake and verifies the downloaded source archive before compiling it.
Models are selected or downloaded from inside the app and are intentionally
not bundled into the source tree.

## Tests and verification

Run the unit test suite through the isolated Community configuration:

```sh
make test-community
```

Run the complete repository verification before proposing a sensitive or
release-related change:

```sh
make verify
```

`make verify` runs script checks, static data validation, unit tests, application
target builds, and a clean exported-source verification. It intentionally uses
fresh derived data for important checks and can take substantially longer than
`make test-community`.

## Permissions and local testing

A running source build may request Microphone, Accessibility, Input Monitoring,
or Automation permission. macOS associates several permissions and Keychain
records with application identity and signature. Repeated ad-hoc signing or
changing bundle identifiers can therefore trigger new prompts.

Use invented dictation while developing. Do not commit recordings, transcripts,
History data, settings exports, API keys, or diagnostic files. Local app data
and downloaded models remain outside the repository.

## Community distribution

The `ShuoCommunity` scheme and Community configuration are the supported
source-build path. A locally compiled
application is not an official Shuo release. If you redistribute the unmodified
community build, describe it as **Shuo Community**, not as an official Shuo
download. Its default ad-hoc signature is for local and testing use; a
distributor is responsible for any signing and notarization it offers. If you
distribute a modified fork under another identity, use your own product name,
icon, bundle identifier, Keychain identifiers, update feed, signing identity,
and support channel. Make the source and GPL notices available as required by
GPL-3.0, identify the build as unofficial, and follow
[TRADEMARK.md](TRADEMARK.md).

Do not point a community binary at Shuo's production Sparkle feed. Do not copy
the official Sparkle private key, Developer ID certificate, notarization
profile, or other release secrets. Those are not part of the source release.

The `release-rc`, packaging, and appcast commands documented in the root README
are maintainer release tooling. A successful local invocation does not make the
result an official release.

## Common problems

### Xcode is using a different toolchain

Select the intended Xcode installation and retry:

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

### Swift package resolution fails

Confirm network access to the dependency host, then let Xcode resolve package
dependencies again. Do not commit local DerivedData as a workaround.

### Local model transcription is unavailable

Building the app and downloading a speech model are separate steps. Open Shuo's
model management after launch and download a supported model. A source checkout
does not contain model weights.

### macOS asks for permissions again

Confirm that you are launching the same installed app identity and signing it
consistently. Ad-hoc builds are expected to be less stable with respect to
TCC and Keychain identity than an official signed release.
