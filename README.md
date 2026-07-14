# Shuo

Shuo（说）is a lightweight macOS voice keyboard for bilingual work. Hold Right
Command or Right Option, speak naturally in Chinese, English, and technical
terms, then release to insert the result into the app you are already using.

Shuo is local-first and configurable without making configuration the default
experience. Home focuses on one loop—hold, speak, release. Settings contains
the everyday controls. Advanced presents the complete configuration as a
seven-stage path from voice input to final result, with search on its unselected
overview. Permissions, updates, support, export, and local-data tools live in
About.

## What Works

- Local transcription through whisper.cpp, including managed model downloads,
  integrity checks, free-space checks, progress, cancellation, and timeouts.
- The universal whisper.cpp runtime ships inside the direct app, so Local setup
  only requires downloading a model.
- OpenAI-compatible transcription with Keychain credentials, authenticated
  model discovery, Automatic or Fixed model selection, and safe fallback.
- Optional Advanced/Beta profiles can expose ElevenLabs Scribe v2 and Alibaba
  Cloud Qwen3-ASR-Flash adapters with separate Keychain credentials. They are
  not part of the stable onboarding surface.
- Right Command or Right Option push-to-talk from any app.
- Automatic insertion plus a compact latest-result menu with Copy, Replace,
  Play, and Redo. Replace reactivates the original app and rewrites only the
  changed suffix when the recent insertion, app process, and interaction guard
  still match; otherwise it copies the complete correction for safety.
- An optional Floating Bar for editing the latest result and safely
  replacing the text that Shuo just inserted. It is draggable across displays,
  remembers its position, cannot be manually resized, and offers Hide Floating
  Bar, Open Shuo, and Quit Shuo from its right-click menu.
- Whisper Mode with per-recording noise-floor measurement and bounded gain for
  quiet speech. Archived source audio is never modified.
- Local history, replayable audio, retranscription, monotonic metrics, and
  corruption-safe recovery.
- Preferred Terms and opt-in Project Vocabulary. Linked folders are indexed
  locally and read-only; source content and paths are not uploaded.
- Full before/after edits captured locally from explicit Copy, Replace, History
  save, and voice-edit actions. Correction Learning is off by default; when the
  user enables it, Shuo shows locally derived token-level preferences in
  descending frequency. Every `A → B` pattern starts disabled and can affect
  future transcription only after the user enables that row and it passes the
  selected mode's confidence gate.
- A direct-download build with signed Sparkle update support. The sandboxed App
  Store target remains buildable as a future option but is not the current
  release channel.

The application source is licensed under
[GPL-3.0-only](LICENSE). The Shuo name and logo remain subject to the separate
[trademark policy](TRADEMARK.md).

## Privacy Boundary

Shuo requires no account, sends no telemetry, behavioral analytics, or crash
reports to Shuo, and contains no advertising. With Local transcription selected
and cloud AI disabled, audio, text, corrections, and personal vocabulary never
leave the Mac. Settings, history, metrics, recordings, downloaded models,
project vocabulary indexes, explicit before/after edits, and crash reports stay
local. API keys live in macOS Keychain. Recordings linked to retained History
items remain available until the user deletes those items. Preserved
damaged-file recovery copies stay local, are never loaded or uploaded
automatically, and are disclosed in the privacy page.

When an OpenAI-compatible, ElevenLabs, or Alibaba Cloud provider is selected,
the current recording and provider-supported spelling hints are sent to that
provider. If Correction Learning is enabled, only individually enabled and
eligible preferred terms (the corrected `B` side) may join those bounded hints.
Shuo does not send the observed `A` side, complete History, or the correction
dataset.
Enabled LLM features may also send transcript text and instructions to that
endpoint. Linked project source files and paths are never uploaded. Correction
data stays linked to History metadata when possible and can be reviewed,
exported, or cleared from Advanced → Human correction → Correction Data.
Clearing sets a learning cutoff so older evidence is no longer reused; it does
not delete History or its recordings. Per-pattern choices are stored only on
this Mac and are also reset when correction data is cleared. Future training or
dataset upload still requires a separate explicit action.

See the public [privacy page](web/privacy.html) for details.

## Local whisper.cpp Transcription

1. Open Shuo and choose Local during first-run setup, or open Settings.
2. Download a managed model or choose a visible `.bin` model in your model
   folder. Shuo verifies managed downloads using the publisher's exact size and
   SHA-256 digest.
3. Use Base for fast testing, Small as the lightweight choice, or Large Turbo
   as the recommended default on Apple Silicon Macs with at least 16 GB of
   memory. Additional
   quantization variants remain under More Models until benchmarks show a
   user-visible benefit.
4. Choose a known language when possible; Automatic language detection is more
   convenient but can take longer.

The direct app contains a pinned, static universal whisper.cpp runtime. Manual
Setup still accepts another `whisper-cli` path for development and comparison.

Shuo records 16 kHz mono 16-bit WAV. Local processes can be cancelled and stop
after ten minutes rather than hanging indefinitely. Fast performance mode uses
more CPU threads and greedier decoding, with a possible small accuracy tradeoff.

## OpenAI-Compatible Transcription

1. Choose OpenAI-compatible in Settings.
2. Add an API key; Shuo stores it in macOS Keychain.
3. Keep the base URL at `https://api.openai.com/v1` for OpenAI, or enter a
   compatible endpoint.
4. Use Automatic to select the best compatible model visible to that API key,
   or Fixed to pin a supported model.

`Whisper-1 · Cloud API` is the hosted Whisper API model: Shuo uploads the
current recording to the configured endpoint. With the default base URL, that
endpoint is OpenAI; a custom compatible base URL uses its corresponding cloud
service. It is separate from the Local provider, which runs the downloaded
whisper.cpp model on the Mac.

Shuo queries the authenticated `/models` endpoint when the settings open,
caches results for 24 hours, and refreshes after connection changes or a
model-access failure. Server results are intersected with Shuo's task-specific
catalog, so an arbitrary model ID is not assumed to accept audio. The same
Automatic/Fixed policy applies to optional text-model features.

## Vocabulary And Corrections

Preferred Terms are user-managed spelling hints. Project Vocabulary is an
opt-in feature under Advanced → Context: the user links a local folder and Shuo builds a
bounded index from names, manifests, paths, source symbols, and documentation.
Dependencies, build output, likely secrets, hidden files, and symbolic links
are skipped. Users can link one or more folders and enable each project
independently; terms from enabled projects share the same bounded prompt budget.

For cloud transcription, only selected terms within the current prompt budget
can leave the Mac—never project source or paths.

When a user explicitly edits the latest draft and chooses Copy or Replace,
saves a History edit, or completes a voice edit, Shuo stores the complete
before/after event locally with provider, model, language, and History/audio
references when available, whether Correction Learning is on or off.

Correction Learning is off by default. When enabled, Shuo derives token-level
`observed → preferred` patterns locally and lists them in descending frequency.
Every pattern is disabled by default. Only a pattern the user individually
enables can affect later transcription, and it must still pass the active mode's
gate. For Model Hints that means at least two observations, at least 75%
confidence, and a lead of at least two observations over the runner-up. Safe
Local Replacement is stricter: at least three distinct trusted sessions, 100%
confidence, and no alternative or reverse mapping. Pure numbers, short lowercase
Latin words, and unsafe partial-word matches are excluded; Latin matches require
word boundaries and CJK replacements require a complete word range confirmed by
the system tokenizer. Safe Local Replacement is still a context-free global
token rule, so it is intended for names and jargon rather than ordinary words
whose meaning changes by context. Per-pattern choices stay on this Mac and are
cleared together with Correction Data.

Provider-supported cloud transcription receives only individually enabled,
eligible preferred terms, not the mistaken source phrase, complete History, or
the correction dataset. This is conservative text personalization, not acoustic
model training.
The recording, raw model result, and corrected final text remain connected in
local History, creating a user-owned corpus for future evaluation and explicitly
initiated personalized-model work.

## Build And Verify

For an ordinary source checkout, build and test the isolated Community edition:

```sh
make build-community
make test-community
```

It uses `Shuo Community.app`, a separate bundle/storage/Keychain/permission
identity and no official update feed. It does not require a paid Apple developer
account. You can also open the shared scheme in Xcode:

```sh
open Shuo.xcodeproj
```

Run the full repository verification:

```sh
make verify
```

Maintainers can build the official direct-download target, which includes
Sparkle, with `make build`. The `Shuo` scheme retains the sandbox-compatible
target:

```sh
make build-store
```

See [BUILDING.md](BUILDING.md) for target details and redistribution boundaries.

## Maintainer Release Packaging And Update Feed

The only supported public RC command is:

```sh
make verify
git status --short  # must be empty after committing the verified source
git tag -a v1.0.0 -m "Shuo 1.0.0"
git remote get-url origin  # must be https://github.com/stcheng/shuo.git or its SSH form
git push origin HEAD:main refs/tags/v1.0.0
make release-rc
```

`release-rc` fails closed unless the source tree is clean, the Developer ID and
notary profile are valid, the exact tag is anonymously reachable from the
canonical public repository, and the build is universal. It uses fresh
temporary DerivedData and a fresh pinned whisper.cpp source build, and stages
all outputs in temporary directories; only after the
app, ZIP, DMG, signatures,
notarization tickets, Gatekeeper assessments, update metadata, licenses,
entitlements, and checksums pass verification does it publish files to `dist/`.
The versioned JSON manifest records the exact Git commit, version, build, and
ZIP/DMG/private-symbol SHA-256 hashes. The matching dSYM archive stays private
in `dist/private/` (or `SHUO_PRIVATE_ARTIFACT_DIR`) for crash symbolication.
Stable `Shuo-latest-macOS` aliases are byte-identical to their versioned
artifacts.

The lower-level `package-*` targets use development signing defaults and are
only packaging smoke tools; their output is never a public release candidate.
After `release-rc` creates the final verified artifacts, first inspect the
six-file public allowlist and attach exactly those files to the published
(non-draft) GitHub Release. Confirm the versioned ZIP URL is reachable before
generating the signed feed entry; otherwise the deployed feed could point to a
404. The ZIP must remain beside the matching RC checksum and JSON manifest:

```sh
SHUO_APPCAST_ARCHIVE=dist/Shuo-1.0.0-macOS.zip make appcast
```

Before the GitHub upload, inspect the six-file public allowlist with
`SHUO_RELEASE_MANIFEST=dist/Shuo-1.0.0-macOS.manifest.json make
release-public-assets`. Never upload with a glob; the private dSYM is not a
public release asset. After the upload is live, run `make appcast` above and
commit the resulting `web/appcast.xml`.

The Sparkle private key stays in the release Mac's Keychain. Never export it
into this repository, and never publish output from a lower-level packaging
target.

`make appcast` resolves the pinned Sparkle package into a fresh temporary
DerivedData directory before reading its signing tools; it does not trust an
older global Xcode cache.

## Maintainer Development Install

This command intentionally installs the official `dev.shuotian.Shuo` development
identity and may replace `/Applications/Shuo.app`. Community contributors should
use the `ShuoCommunity` scheme instead.

For daily use, install and relaunch the current Release build:

```sh
make install-dev
```

This uses the stable `Shuo Local Development` signing identity, installs to
`/Applications/Shuo.app` when writable or `~/Applications/Shuo.app` otherwise,
and opens the app. The local-only signature carries the library-validation
exception required by the locally signed Sparkle framework; production
entitlements remain unchanged.

Use `make install-dev-adhoc` only when Keychain access is undesirable. macOS may
treat each ad-hoc build as a new app identity and request Accessibility again.

## Website

The static bilingual product site, privacy policy, release notes, update feed,
and manifest live in `web/`:

```sh
python3 -m http.server --directory web 8080
```

Then open `http://127.0.0.1:8080`.

## Public Source Preparation

The canonical public repository contains application source, tests, public
documentation, the website, releases, and the update feed. Private planning
notes, user data, credentials, and generated artifacts are excluded. Maintainers
can create a reviewed source export with:

```sh
make export-public
```

To create the one-time fresh public Git history without copying the private
repository history, run `Scripts/initialize-public-repository.sh`. It performs a
source audit, initializes `main`, and leaves every file staged but uncommitted
for human review. See [docs/public-repo-plan.md](docs/public-repo-plan.md).

## Permissions

Shuo needs Microphone permission to record. Global push-to-talk, target
verification, and insertion need Accessibility permission. Permission buttons
open the relevant macOS pane; Shuo refreshes state when you return and resumes
the shortcut monitor automatically.

## Release Status

Shuo 1.0 uses a signed and notarized direct-download release process. Every
official binary corresponds exactly to its public Git tag, and each release
publishes matching source, checksums, release notes, and a signed update feed.
