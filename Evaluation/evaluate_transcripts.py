#!/usr/bin/env python3
import json
import re
import sys
import unicodedata
from pathlib import Path


def normalize(value: str) -> str:
    value = unicodedata.normalize("NFKC", value).casefold()
    value = "".join(character for character in value if not unicodedata.category(character).startswith("P"))
    return re.sub(r"\s+", " ", value).strip()


def edit_distance(left: str, right: str) -> int:
    previous = list(range(len(right) + 1))
    for left_index, left_character in enumerate(left, start=1):
        current = [left_index]
        for right_index, right_character in enumerate(right, start=1):
            current.append(min(
                current[-1] + 1,
                previous[right_index] + 1,
                previous[right_index - 1] + (left_character != right_character),
            ))
        previous = current
    return previous[-1]


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: evaluate_transcripts.py HYPOTHESES.json", file=sys.stderr)
        return 2

    corpus_path = Path(__file__).with_name("bilingual-technical-corpus.json")
    corpus = json.loads(corpus_path.read_text())
    hypotheses = json.loads(Path(sys.argv[1]).read_text())

    exact = 0
    character_errors = 0
    reference_characters = 0
    matched_terms = 0
    total_terms = 0
    missing = []

    for utterance in corpus["utterances"]:
        identifier = utterance["id"]
        hypothesis = normalize(hypotheses.get(identifier, ""))
        reference = normalize(utterance["text"])
        exact += hypothesis == reference
        character_errors += edit_distance(reference.replace(" ", ""), hypothesis.replace(" ", ""))
        reference_characters += max(1, len(reference.replace(" ", "")))

        for term in utterance["requiredTerms"]:
            total_terms += 1
            if normalize(term) in hypothesis:
                matched_terms += 1
            else:
                missing.append(f"{identifier}: {term}")

    count = len(corpus["utterances"])
    print(f"utterances: {count}")
    print(f"exact match: {exact / count:.1%}")
    print(f"character error rate: {character_errors / reference_characters:.1%}")
    print(f"required-term recall: {matched_terms / max(1, total_terms):.1%}")
    if missing:
        print("\nmissing required terms:")
        print("\n".join(missing))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
