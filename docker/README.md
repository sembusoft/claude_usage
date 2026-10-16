# Docker-Variante (z. B. ZimaOS, Synology, jeder Docker-Host)

Container mit Claude Code (für Login/Token) und einem kleinen Python-Poller.
Webseite danach unter `http://SERVER-IP:8099`.

## Installation (allgemein)

```sh
cd claude-usage-monitor/docker
docker compose up -d --build
docker exec -it claude-usage claude      # /login → „Claude account with subscription“, danach /exit
docker restart claude-usage
```

Port und Abrufintervall optional: `.env.example` nach `.env` kopieren und anpassen (Standard: Port 8099, alle 300 s).

## Besonderheiten ZimaOS

- Systempartition ist schreibgeschützt → bei jedem Docker-Befehl `sudo DOCKER_CONFIG=/DATA/.docker` voranstellen.
- Ordner nach `/DATA/AppData/claude-usage/` kopieren.
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
| Nicht angemeldet | `docker exec -it claude-usage claude` → `/login` |
| Token-Erneuerung fehlgeschlagen (HTTP 400) | Login abgelaufen → erneut `/login` |
| port is already allocated | anderen `PORT` in `.env` wählen |

Logs: `docker logs -f claude-usage`
