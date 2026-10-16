# Legt eine Verknuepfung im Autostart-Ordner an und startet die Tray-Anwendung sofort.
$script = Join-Path $PSScriptRoot "ClaudeUsageTray.ps1"
$launcher = Join-Path $PSScriptRoot "Start-Tray.vbs"
$lnk = Join-Path ([Environment]::GetFolderPath("Startup")) "Claude Verbrauch.lnk"

$ws = New-Object -ComObject WScript.Shell
$s = $ws.CreateShortcut($lnk)
$s.TargetPath = "wscript.exe"
$s.Arguments = "`"$launcher`""
$s.WorkingDirectory = $PSScriptRoot
$s.Description = "Claude-Verbrauch im Infobereich"
$s.Save()

Start-Process wscript.exe -ArgumentList "`"$launcher`""
Write-Host "Autostart eingerichtet: $lnk"
