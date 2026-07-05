"""Guest welcome copy + language detection (pure — no DB, no network).

The welcome is sent in the property's local language by default (derived from
`master_json.location.country`), and additionally in English when the property's
`welcome_also_english` toggle is on. Ships EN + ES; add languages by extending
`WELCOME` and `_COUNTRY_LANG`.
"""

DEFAULT_LANG = "en"

WELCOME = {
    "en": (
        "Welcome to {property}. I'm Alfred, your invisible assistant for a "
        "flawless stay. Ask me anything — check-in, wifi, details about the "
        "home, or local tips — anytime, day or night. And if you ever need "
        "your host, I'll bring them in."
    ),
    "es": (
        "Bienvenido a {property}. Soy Alfred, tu asistente invisible para una "
        "estancia perfecta. Pregúntame lo que necesites —entrada, wifi, "
        "detalles sobre el alojamiento o recomendaciones locales— a cualquier "
        "hora. Y si necesitas a tu anfitrión, le aviso al instante."
    ),
}

# country (lowercased) → language. Extend as more languages are added.
_COUNTRY_LANG = {
    "mexico": "es", "méxico": "es", "spain": "es", "españa": "es",
    "argentina": "es", "colombia": "es", "peru": "es", "perú": "es",
    "chile": "es", "ecuador": "es", "guatemala": "es", "costa rica": "es",
    "panama": "es", "panamá": "es", "uruguay": "es", "paraguay": "es",
    "bolivia": "es", "honduras": "es", "nicaragua": "es", "el salvador": "es",
    "dominican republic": "es", "república dominicana": "es",
    "venezuela": "es", "cuba": "es", "puerto rico": "es",
}


def _extract_country(master_json: dict | None) -> str | None:
    location = (master_json or {}).get("location") or {}
    country = location.get("country")
    return country.strip() if isinstance(country, str) and country.strip() else None


def language_for_property(master_json: dict | None) -> str:
    country = _extract_country(master_json)
    if country:
        return _COUNTRY_LANG.get(country.lower(), DEFAULT_LANG)
    return DEFAULT_LANG


def build_welcome(property_name: str | None, master_json: dict | None,
                  also_english: bool = False) -> str:
    """Localized welcome. Local language first; append English when toggled on
    (skipped if the local language already IS English)."""
    name = (property_name or "your stay").strip()
    lang = language_for_property(master_json)
    primary = WELCOME.get(lang, WELCOME[DEFAULT_LANG]).format(property=name)
    if also_english and lang != "en":
        return f"{primary}\n\n{WELCOME['en'].format(property=name)}"
    return primary
