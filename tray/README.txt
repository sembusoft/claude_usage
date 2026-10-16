Claude-Verbrauch im Windows-Infobereich
=======================================

Zeigt die 5-Std.-Auslastung als farbiges Zahlen-Icon neben der Uhr
(gruen < 60 %, gelb < 85 %, rot ab 85 %).

- Display-Fenster (Session/Woche als Akku, Reset-Countdown) erscheint beim
  Start und bleibt dauerhaft sichtbar
  * mit der Maus verschieben, Position wird gemerkt
  * X oben rechts oder Esc: ausblenden
  * Linksklick aufs Tray-Icon: ein-/ausblenden
  * Doppelklick ins Fenster: Webseite oeffnen
- Maus drueberhalten: Kurzinfo mit Reset-Countdown
- Rechtsklick: Anzeige ein/aus, Immer im Vordergrund, Webseite, Aktualisieren, Beenden
- Ab 90 % Session-Auslastung kommt einmalig eine Windows-Benachrichtigung

Einrichtung
-----------
1. Ordner an einen festen Ort legen, z. B. C:\Tools\claude-usage-tray
2. Rechtsklick auf "Autostart-einrichten.ps1" -> "Mit PowerShell ausfuehren"
   (startet die Anwendung sofort und bei jeder Anmeldung)

Nur einmal testen ohne Autostart: Doppelklick auf "Start-Tray.vbs".

Anpassen
--------
Oben in ClaudeUsageTray.ps1:
- $Url      Server-Adresse (ZimaOS: http://SERVER-IP:8099)
- $ApiPath  "/api/usage" (ZimaOS) bzw. "/api/usage.php" (all-inkl/PHP)
- $ShowOnStart  $false = Fenster beim Start nicht automatisch zeigen
- $User / $Password  nur bei Verzeichnisschutz (Passwort steht im Klartext
  in der Datei - einen eigenen Benutzer nur fuer diesen Zweck anlegen)
Danach ueber Rechtsklick -> Beenden und Start-Tray.vbs neu starten.

Entfernen
---------
Win+R -> shell:startup -> "Claude Verbrauch.lnk" loeschen.

Hinweis: Blockiert eine Firmenrichtlinie PowerShell-Skripte, startet die
Anwendung nicht. Dann bitte die IT fragen.
