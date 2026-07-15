# Shuo bilingual transcription evaluation

`bilingual-technical-corpus.json` is a text-level preparation set for recording a stable release benchmark. It intentionally mixes Mandarin and English inside the same sentence and covers project terms, spelling, commands, numbers, and quiet speech.

## Recording protocol

1. Record every utterance verbatim in a quiet room, using the same microphone and distance.
2. For `speechStyle: quiet`, speak softly but naturally; do not whisper every consonant unnaturally.
3. Keep the audio files local and name them with the utterance ID, for example `api-01.m4a`.
4. Run every candidate provider/model against the same recordings.
5. Save hypotheses as JSON: `{ "api-01": "recognized text", ... }`.

## Score

```sh
python3 Evaluation/evaluate_transcripts.py Evaluation/hypotheses.json
```

The report includes normalized exact match, character error rate, and required-term recall. Required-term recall is the most important release gate for project vocabulary.

Audio is deliberately not committed to the repository. The eventual in-app private evaluation runner should read recordings from the user's local Shuo data vault.
