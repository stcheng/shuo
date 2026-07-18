# Shuo Architecture

Shuo is organized around one visible path from speech to final text. The same
seven stages structure Advanced settings and the implementation boundaries.

```mermaid
flowchart LR
    A[Voice input] --> B[Audio processing] --> C[Context]
    C --> D[Inference] --> E[Post-processing]
    E --> F[Manual correction] --> G[Final result]
    D -. optional .-> H[Configured cloud service]
    E -. optional .-> H
```

The main path works locally. A dotted request is made only when the user
actively enables a cloud transcription or text feature.

## Stages

1. **Voice input** — A global push-to-talk shortcut captures one bounded
   recording.
2. **Audio processing** — Shuo detects useful speech and prepares audio for
   recognition without changing the archived source recording.
3. **Context** — Enabled terms, local project vocabulary, and reusable prompts
   are ranked into a bounded hint for engines and providers that support one.
   Project source and paths stay local. SenseVoice deliberately skips
   transcription hints rather than pretending to consume them.
4. **Inference** — A downloaded local Whisper or SenseVoice model, or a
   user-configured cloud service, produces an initial result.
5. **Post-processing** — Enabled rules handle formatting, punctuation, script
   conversion, replacements, and Emoji. Optional cloud text processing remains
   distinct from local rules.
6. **Manual correction** — The Floating Bar, History, menu actions, and voice
   editing create explicit before/after changes. Unsafe replacement falls back
   to copying the complete correction.
7. **Final result** — Shuo writes the result to the target app and retains
   related History data locally when the user keeps it.

## Code layout

```text
App/Views     SwiftUI UI and the Floating Bar
App/Stores    Observable state and orchestration
App/Services  Recording, permissions, inference, insertion, storage, updates
App/Models    Settings, History, vocabulary, correction, provider contracts
Config/       Optional feature profiles
Tests/        Unit and integration-contract checks
Scripts/      Build, verification, packaging, and update-feed tooling
web/          Public product site, privacy policy, and release notes
```

Views do not directly call cloud providers or write persistent files.
`AppState` coordinates a user-visible transaction; specialized services own
I/O and policy decisions.

## Trust boundaries

- With local transcription selected and cloud AI off, audio and text stay on
  the Mac. The app has no account requirement or app telemetry.
- When a cloud feature is enabled, it receives only its current-task payload.
  Complete History, correction records, project source, and paths are not sent
  as background context.
- API keys are stored in macOS Keychain.
- Text insertion is treated as a boundary: Shuo only rewrites a recently
  verified target; otherwise it copies the correction instead of deleting
  uncertain content.
- History connects retained audio, initial results, final text, and explicit
  corrections. Storage recovery preserves damaged sources rather than silently
  discarding them.

## Change checklist

Before changing behavior, answer:

- Which stage owns it?
- Does it add microphone, Accessibility, disk, Keychain, or network access?
- Is its local/cloud boundary explicit and documented?
- Can it be cancelled, timed out, retried, and explained?
- Does failure preserve existing user data and avoid uncertain target edits?
- Are tests, localization, accessibility, and privacy documentation updated?
