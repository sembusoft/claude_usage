# Claude-Verbrauch – PHP-Variante (z. B. all-inkl)

Gleiche Anzeige wie die Docker-Variante, nur mit PHP (≥ 7.4, cURL). Kein Cronjob nötig:
Die Daten werden beim Aufruf geholt und 5 Minuten zwischengespeichert.

## 1. Hochladen

Den kompletten Ordner per FTP hochladen, z. B. nach `/claude-usage/` deiner Domain.
Die beiden `.htaccess`-Dateien müssen mit (im FTP-Programm versteckte Dateien anzeigen).

```
claude-usage/
├─ index.html, icon.svg, config.php, .htaccess
├─ api/usage.php
└─ data/.htaccess          ← sperrt den Ordner
```

## 2. Zugangsdaten hochladen

Lege eine Kopie deiner Claude-Code-Zugangsdaten als `data/credentials.json` ab.

Quelle (eine davon):
- ZimaOS-Server: `/DATA/AppData/claude-usage/data/.credentials.json`
- Windows mit Claude Code: `%USERPROFILE%\.claude\.credentials.json`

**Wichtig:** Ein Login darf nur an EINER Stelle laufen. Beim Erneuern wird das Token
ausgetauscht – laufen ZimaOS und all-inkl mit derselben Datei, sperren sie sich gegenseitig aus.
Entweder ZimaOS-App stoppen, oder für all-inkl ein eigenes Login erzeugen
(z. B. `claude` → `/login` auf einem anderen Rechner und dessen Datei verwenden).

## 3. Prüfen

- `https://deine-domain.de/claude-usage/` → Display-Ansicht
- `https://deine-domain.de/claude-usage/data/credentials.json` → muss **403** liefern!

## 4. Seite schützen (empfohlen)

KAS → Tools → Verzeichnisschutz → Ordner `claude-usage` → Benutzer anlegen.

## Tray-Anwendung

Oben in `ClaudeUsageTray.ps1`:
```
$Url      = "https://deine-domain.de/claude-usage"
$ApiPath  = "/api/usage.php"
$User     = "…"   # Verzeichnisschutz-Benutzer
$Password = "…"
```

## Einstellungen (`config.php`)

- `cache_seconds` – Abrufintervall (Standard 300)
- `data_dir` – sicherer ist ein Ordner außerhalb des Webroots, z. B. `__DIR__ . '/../claude-usage-data'`

## Fehler

| Meldung | Bedeutung |
|---|---|
| credentials.json fehlt | Schritt 2 |
| Token-Erneuerung fehlgeschlagen (HTTP 400) | Login abgelaufen oder von anderer Instanz verbraucht → neue Datei hochladen |
| Usage-API-Fehler HTTP 403 / 429 | Anfrage vom Webhoster abgelehnt bzw. zu häufig |
| Datenordner fehlt / nicht beschreibbar | Ordner `data` anlegen, Rechte 755 |
