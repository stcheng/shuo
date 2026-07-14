# Third-Party Notices

This document identifies third-party software and data used by Shuo. It is not
a license for Shuo itself.

## Sparkle 2.9.4

The direct-download build uses Sparkle for signed application updates. The
App Store-compatible target does not link Sparkle.

- Source: <https://github.com/sparkle-project/Sparkle/tree/2.9.4>
- License: MIT, with additional notices for code incorporated by Sparkle
- Copyright: Copyright (c) 2006-2013 Andy Matuschak; 2009-2013 Elgato Systems
  GmbH; 2011-2014 Kornel Lesiński; 2015-2017 Mayur Pawashe; 2014 C.W. Betts;
  2014 Petroules Corporation; and 2014 Big Nerd Ranch
- Complete license and incorporated-code notices:
  <https://github.com/sparkle-project/Sparkle/blob/2.9.4/LICENSE>

## whisper.cpp 1.8.6

The direct-download build includes a statically built `whisper-cli` runtime.
The build is pinned to whisper.cpp 1.8.6 and verifies the source archive before
compiling it. The packaged direct-download app also carries the upstream license at
`Contents/Resources/ThirdParty/whisper.cpp-LICENSE`.

- Source: <https://github.com/ggml-org/whisper.cpp/tree/v1.8.6>
- License: MIT
- Copyright: Copyright (c) 2023-2026 The ggml authors
- License text: <https://github.com/ggml-org/whisper.cpp/blob/v1.8.6/LICENSE>

## OpenAI Whisper model weights

Shuo does not include Whisper model weights in its source tree or initial app
download. If a user chooses local transcription, Shuo can download converted
GGML model files on demand from the `ggerganov/whisper.cpp` Hugging Face model
repository at the revision pinned in `App/Models/LocalWhisperModelCatalog.swift`.

The models are derived from OpenAI Whisper model weights. OpenAI states that
Whisper code and model weights are released under the MIT License.

- Upstream project: <https://github.com/openai/whisper>
- Upstream license: <https://github.com/openai/whisper/blob/main/LICENSE>
- Copyright: Copyright (c) 2022 OpenAI
- Exact model source used by Shuo:
  <https://huggingface.co/ggerganov/whisper.cpp/tree/5359861c739e955e79d9a303bcbc70fb988958b1>
- Model repository license: MIT

## Unicode CLDR annotation data

`App/Resources/EmojiAnnotations.json` is a derived subset of Unicode CLDR JSON
`cldr-annotations-full` data for English, Simplified Chinese, and Traditional
Chinese. Shuo uses it for local emoji-name and keyword matching.

- Source: <https://github.com/unicode-org/cldr-json>
- License: Unicode License v3 (`Unicode-3.0`)
- Copyright: Copyright © 2015-2024 Unicode, Inc.
- License text: <https://github.com/unicode-org/cldr-json/blob/main/LICENSE>

Unicode and the Unicode Logo are registered trademarks of Unicode, Inc. in the
United States and other countries. Unicode's name is used here only to identify
the source of the data.

## No endorsement

The names and trademarks above belong to their respective owners. Their
inclusion does not imply endorsement of Shuo by those projects or owners.
