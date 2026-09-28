#!/usr/bin/env python3
"""Builds Keel/Resources/Localizable.xcstrings from the keys the compiler extracted.

Run after a Release build (SWIFT_EMIT_LOC_STRINGS=YES writes .stringsdata files):
  python3 scripts/localize.py
It fails when a key has no translation or a translation's placeholders don't match the key's.
"""
import glob
import json
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from translations_1 import TR as TR1  # noqa: E402
from translations_2 import TR as TR2  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
LANGUAGES = ["pt-PT", "fr", "es", "de"]
STRINGSDATA = ROOT / "build/DerivedData/Build/Intermediates.noindex/Keel.build/Release/Keel.build/Objects-normal/arm64"
OUTPUT = ROOT / "Keel/Resources/Localizable.xcstrings"

# Keys whose number needs singular and plural forms: {key: {language: (one, other)}}.
PLURALS = {
  "A full cycle keeps the battery's percentage reading accurate. Last run %lld days ago.": {
    "en": ("A full cycle keeps the battery's percentage reading accurate. Last run %lld day ago.",
           "A full cycle keeps the battery's percentage reading accurate. Last run %lld days ago."),
    "pt-PT": ("Um ciclo completo mantém a percentagem da bateria exata. Última vez há %lld dia.",
              "Um ciclo completo mantém a percentagem da bateria exata. Última vez há %lld dias."),
    "fr": ("Un cycle complet garde le pourcentage de la batterie précis. Dernière fois il y a %lld jour.",
           "Un cycle complet garde le pourcentage de la batterie précis. Dernière fois il y a %lld jours."),
    "es": ("Un ciclo completo mantiene exacto el porcentaje de la batería. Última vez hace %lld día.",
           "Un ciclo completo mantiene exacto el porcentaje de la batería. Última vez hace %lld días."),
    "de": ("Ein voller Zyklus hält die Prozentanzeige des Akkus genau. Zuletzt vor %lld Tag.",
           "Ein voller Zyklus hält die Prozentanzeige des Akkus genau. Zuletzt vor %lld Tagen."),
  },
}

PLACEHOLDER = re.compile(r"%(?:%|@|lld|ld|d|lf|f)")


def placeholders(text: str) -> list:
  return sorted(PLACEHOLDER.findall(text))


def unit(value: str) -> dict:
  return {"stringUnit": {"state": "translated", "value": value}}


def plural(one: str, other: str) -> dict:
  return {"variations": {"plural": {"one": unit(one), "other": unit(other)}}}


def main() -> int:
  keys = set()
  for path in glob.glob(str(STRINGSDATA / "*.stringsdata")):
    data = json.load(open(path))
    for item in data.get("tables", {}).get("Localizable", []):
      keys.add(item["key"])
  if not keys:
    print("No .stringsdata found. Build Release first.")
    return 1

  translations = {**TR1, **TR2}
  problems = []
  strings = {}
  for key in sorted(keys):
    values = translations.get(key)
    if values is None or len(values) != len(LANGUAGES):
      problems.append(f"missing: {key!r}")
      continue
    localizations = {}
    for language, value in zip(LANGUAGES, values):
      if placeholders(value) != placeholders(key):
        problems.append(f"placeholders differ ({language}): {key!r} -> {value!r}")
      localizations[language] = unit(value)
    if key in PLURALS:
      for language, (one, other) in PLURALS[key].items():
        localizations[language] = plural(one, other)
    strings[key] = {"extractionState": "manual", "localizations": localizations}

  unused = sorted(set(translations) - keys)
  for key in unused:
    print(f"unused translation: {key!r}")
  if problems:
    print("\n".join(problems))
    return 1

  catalog = {"sourceLanguage": "en", "strings": strings, "version": "1.0"}
  OUTPUT.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
  print(f"Wrote {len(strings)} strings in {len(LANGUAGES)} languages to {OUTPUT.relative_to(ROOT)}")
  return 0


if __name__ == "__main__":
  sys.exit(main())
