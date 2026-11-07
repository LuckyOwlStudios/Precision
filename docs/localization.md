# Languages

Everything the app says lives in `locale/strings.csv`: one row per phrase, one
column per language. The English wording is the key, so scenes keep readable
text, and labels and buttons whose text matches a row translate themselves.
Text built in code goes through `tr("...")` (or `Localization.t()`).

## Add a language

1. Add a column to `locale/strings.csv`. The header is the locale code
   (`de`, `es`, `pt_BR`).
2. Fill the `LANGUAGE_NAME` row with the language written in itself
   (`Deutsch`), then translate the rest. Empty cells fall back to English.
3. Run the app: it shows up in Settings > Language.

The CSV is parsed at start-up by `ui/settings/localization.gd`, not imported by
the editor, so there is no re-import step. If you export the game, add `*.csv`
to the export preset's "Filters to export non-resource files".

## Add a new phrase

Put the English text on a Control and add the same text as a new row (key =
English text). Phrases with `%s` / `%d` use the same placeholders in every
language.

## Settings

Preferences (quality, units, language) are saved to `user://settings.cfg` by
`AppSettings` (`ui/settings/app_settings.gd`). See that file's header for how
to add another one.
