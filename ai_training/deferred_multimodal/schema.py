"""Shared label metadata contract for training and the Flutter app.

The retired Flutter metadata encoder used to encode fields in this order.
A missing dataset value is unknown. It is not encoded as "no".
"""

from __future__ import annotations

BODY_SITES = [
    "Face",
    "Neck",
    "Chest",
    "Back",
    "Arm",
    "Hand",
    "Leg",
    "Foot",
    "Other",
    "Unknown",
]
SYMPTOMS = ["itch", "pain", "swelling", "changed"]
SYMPTOM_STATES = ["no", "yes", "unknown"]
DURATIONS = [
    "Less than a week",
    "1\u20134 weeks",
    "1\u20136 months",
    "More than 6 months",
    "Not sure",
    "Unknown",
]
TONE_GROUPS = ("FST I-II", "FST III-IV", "FST V-VI", "Unknown")
ROMAN_TONES = {"I": 1, "II": 2, "III": 3, "IV": 4, "V": 5, "VI": 6}


def feature_names() -> list[str]:
    names = [f"body:{site}" for site in BODY_SITES]
    for symptom in SYMPTOMS:
        names.extend(f"{symptom}:{state}" for state in SYMPTOM_STATES)
    names.extend(f"duration:{item}" for item in DURATIONS)
    return names


def metadata_dim() -> int:
    return len(feature_names())


def normalize_key(value: object) -> str:
    text = str(value).casefold().replace("_", " ").replace("-", " ").replace("/", " ")
    return " ".join(text.split())


def parse_tri_state(value: object) -> str:
    if value is None:
        return "unknown"
    text = normalize_key(value)
    if text in {"", "nan", "none", "null", "unk", "unknown", "na", "n a"}:
        return "unknown"
    if text in {"1", "true", "yes", "y", "present"}:
        return "yes"
    if text in {"0", "false", "no", "n", "absent"}:
        return "no"
    return "unknown"


def parse_body_site(value: object, region_map: dict[str, str] | None = None) -> str:
    if value is None:
        return "Unknown"
    text = " ".join(str(value).strip().split())
    if text == "" or normalize_key(text) in {"nan", "none", "null", "unknown"}:
        return "Unknown"
    if region_map is not None:
        mapped = region_map.get(text.upper())
        if mapped is not None:
            return mapped
    titled = text.title()
    if titled in BODY_SITES:
        return titled
    return "Other"


def parse_duration(value: object) -> str:
    if value is None:
        return "Unknown"
    text = str(value).strip()
    if text in DURATIONS:
        return text
    return "Unknown"


def parse_tone(value: object) -> tuple[str, int | None]:
    if value is None:
        return "Unknown", None
    text = str(value).strip()
    if text == "" or normalize_key(text) in {"nan", "none", "null", "unknown"}:
        return "Unknown", None
    try:
        tone = int(float(text))
    except ValueError:
        tone = ROMAN_TONES.get(text.upper().replace("FST", "").strip())
    if tone in (1, 2):
        return "FST I-II", tone
    if tone in (3, 4):
        return "FST III-IV", tone
    if tone in (5, 6):
        return "FST V-VI", tone
    folded = " ".join(text.upper().split())
    if folded in {"FST I-II", "FST III-IV", "FST V-VI"}:
        return folded, None
    return "Unknown", None


def encode_metadata(
    body_site: object = None,
    itch: object = None,
    pain: object = None,
    swelling: object = None,
    changed: object = None,
    duration: object = None,
    region_map: dict[str, str] | None = None,
) -> list[float]:
    site = parse_body_site(body_site, region_map)
    states = [
        parse_tri_state(itch),
        parse_tri_state(pain),
        parse_tri_state(swelling),
        parse_tri_state(changed),
    ]
    duration_name = parse_duration(duration)
    vector: list[float] = []
    vector.extend(1.0 if name == site else 0.0 for name in BODY_SITES)
    for state in states:
        vector.extend(1.0 if name == state else 0.0 for name in SYMPTOM_STATES)
    vector.extend(1.0 if name == duration_name else 0.0 for name in DURATIONS)
    if len(vector) != metadata_dim():
        raise RuntimeError("Metadata vector length drifted from the feature layout.")
    return vector


def label_identified_by_blank_metadata(blank: list[bool], labels: list[str]) -> str | None:
    """Return a label when a blank questionnaire matches that label and no other."""
    grouped: dict[str, list[bool]] = {}
    for is_blank, label in zip(blank, labels):
        grouped.setdefault(label, []).append(is_blank)
    for label, flags in grouped.items():
        if not flags or not all(flags):
            continue
        others = [flag for other, other_flags in grouped.items() if other != label for flag in other_flags]
        if others and not any(others):
            return label
    return None


def metadata_is_blank(vector: list[float]) -> bool:
    names = feature_names()
    required = {
        "body:Unknown": 1.0,
        "itch:unknown": 1.0,
        "pain:unknown": 1.0,
        "swelling:unknown": 1.0,
        "changed:unknown": 1.0,
        "duration:Unknown": 1.0,
    }
    return all(vector[names.index(name)] == expected for name, expected in required.items())
