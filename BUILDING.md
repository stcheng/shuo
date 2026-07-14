# Building Shuo

This repository supports a self-contained, source-built **Shuo Community**
application. It is separate from the official download: it has its own app
identity, local storage, and no production update feed.

## Requirements

- macOS 14 or later
- Xcode with command-line tools selected
- Git
- Internet access for the first Swift package resolution

For local-model runtime preparation or packaging, also install CMake. The
finished app does not require Homebrew.

~~~sh
xcodebuild -version
xcode-select -p
~~~

## Build

~~~sh
git clone https://github.com/stcheng/shuo.git
cd shuo
make build-community
~~~

Or open Shuo.xcodeproj in Xcode and choose the ShuoCommunity scheme. The
Community build is named **Shuo Community** and is ad-hoc signed, so it does
not require an Apple Developer Program account.

The direct ShuoDirect target is available for development:

~~~sh
make build
~~~

Local speech models are downloaded or selected from inside the app; model
weights are deliberately not stored in this repository.

## Test

~~~sh
make test-community
~~~

For a broader source and build verification, run:

~~~sh
make verify
~~~

It is slower and requires a few additional command-line tools. See the
repository CI configuration for the exact verifier setup.

## Development notes

Source builds may request Microphone, Accessibility, Input Monitoring, or
Automation permission. macOS associates several of those permissions with the
app identity and signature, so changing either can cause a new prompt.

Use invented dictation while developing. Do not commit recordings, transcripts,
History data, downloaded models, credentials, or diagnostic exports.

## Redistribution

Shuo source is GPL-3.0. A source build is not an official Shuo release. If you
redistribute a modified build, use your own product identity, support channel,
and update path, comply with GPL-3.0, and read [TRADEMARK.md](TRADEMARK.md).
