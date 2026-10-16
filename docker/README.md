# Docker-Variante (z. B. ZimaOS, Synology, jeder Docker-Host)

Container mit Claude Code (für Login/Token) und einem kleinen Python-Poller.
Webseite danach unter `http://SERVER-IP:8099`.

## Installation (allgemein)

```sh
cd claude_usage/docker
docker compose up -d --build
# danach einmalig bei Claude anmelden – siehe nächster Abschnitt
```

Port und Abrufintervall optional: `.env.example` nach `.env` kopieren und anpassen (Standard: Port 8099, alle 300 s).

## Bei Claude anmelden (einmalig)

Der Container enthält Claude Code. Darüber meldest du dich einmal mit deinem Abo an.
Das Login landet im Volume `./data` (ZimaOS: `/DATA/AppData/claude-usage/data`)
und bleibt bei Neustarts und Updates erhalten.

1. Claude Code im laufenden Container starten:
   ```sh
   docker exec -it claude-usage claude
   # ZimaOS:
   sudo DOCKER_CONFIG=/DATA/.docker docker exec -it claude-usage claude
   ```
2. Erststart-Fragen (Farbschema usw.) mit Enter bestätigen.
3. Login-Methode **„Claude account with subscription“** wählen
   (falls nicht automatisch gefragt: `/login` eingeben).
4. Die angezeigte URL auf PC oder Handy im Browser öffnen, mit dem Claude-Konto anmelden,
   den angezeigten Code kopieren und ins Terminal einfügen.
5. Mit `/exit` beenden und den Container neu starten, damit sofort Daten kommen:
   ```sh
   docker restart claude-usage
   ```
6. Kontrolle: `docker logs claude-usage` zeigt `ok=True`, die Webseite zeigt Prozentwerte.

Danach ist nichts mehr zu tun – das Token wird automatisch erneuert.
Erscheint auf der Seite „Token-Erneuerung fehlgeschlagen“ oder „neu anmelden“: Schritte 1–5 wiederholen.

> Claude Code wird im Container nur für das Login gebraucht. Der Poller verbraucht
> kein Kontingent, er liest nur die Auslastung.

## Besonderheiten ZimaOS

- Systempartition ist schreibgeschützt → bei jedem Docker-Befehl `sudo DOCKER_CONFIG=/DATA/.docker` voranstellen.
- Inhalt des Ordners `docker/` nach `/DATA/AppData/claude-usage/` kopieren (auch die versteckte `.env.example`).
- Als App im Dashboard: ZimaOS lädt Images nur aus einer Registry, daher eine lokale Registry nutzen:
  ```sh
  D="sudo DOCKER_CONFIG=/DATA/.docker docker"
  $D run -d --name registry --restart unless-stopped -p 5000:5000 -v /DATA/AppData/registry:/var/lib/registry registry:2
  $D build -t localhost:5000/claude-usage:latest .
  $D push localhost:5000/claude-usage:latest
  ```
  Dann im App Store → „Benutzerdefinierte App installieren“ → Import → Docker Compose → `zima-app.yml`.
  In `zima-app.yml` vorher `SERVER-IP` (Icon-URL) anpassen.
- Updates: Image neu bauen, pushen, App in ZimaOS neu starten.

## Fehlerbilder

| Meldung | Lösung |
|---|---|
| Nicht angemeldet | Abschnitt „Bei Claude anmelden“ |
| Token-Erneuerung fehlgeschlagen (HTTP 400) | Login abgelaufen → neu anmelden |
| port is already allocated | anderen `PORT` in `.env` wählen |

Logs: `docker logs -f claude-usage`
