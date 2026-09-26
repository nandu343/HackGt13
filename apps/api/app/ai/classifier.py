"""Scenario classifier from free-text layout prompts."""

from __future__ import annotations

from typing import Literal

Scenario = Literal['party', 'study', 'dinner', 'movie']

_KEYWORDS: dict[Scenario, tuple[str, ...]] = {
    'study': ('study', 'desk', 'focus', 'homework', 'office', 'work'),
    'dinner': ('dinner', 'dining', 'eat', 'supper', 'meal', 'feast'),
    'movie': ('movie', 'film', 'watch', 'cinema', 'netflix', 'screening'),
    'party': ('party', 'dance', 'celebrate', 'bash', 'rave', 'guest'),
}


def classify_scenario(prompt: str) -> Scenario:
    text = prompt.lower()
    scores: dict[Scenario, int] = {k: 0 for k in _KEYWORDS}
    for scenario, words in _KEYWORDS.items():
        for word in words:
            if word in text:
                scores[scenario] += 1
    best = max(scores, key=lambda s: scores[s])
    if scores[best] == 0:
        return 'party'
    return best
