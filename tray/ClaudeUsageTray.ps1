# Claude-Verbrauch im Windows-Infobereich (Tray)
# Icon zeigt die 5-Std.-Auslastung, Linksklick blendet das Display-Fenster ein/aus.
param(
    # ZimaOS:   $Url = "http://SERVER-IP:8099"            $ApiPath = "/api/usage"
    # all-inkl: $Url = "https://deine-domain.de/claude-usage"  $ApiPath = "/api/usage.php"
    [string]$Url = "http://SERVER-IP:8099",
    [string]$ApiPath = "/api/usage",
    # Nur bei Verzeichnisschutz (.htaccess / KAS) ausfuellen
    [string]$User = "",
    [string]$Password = "",
    [int]$RefreshSeconds = 60,
    # Display-Fenster beim Start automatisch anzeigen
    [bool]$ShowOnStart = $true,
    [int]$WarnPercent = 90
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class NativeIcon {
    [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr handle);
    [DllImport("user32.dll")] public static extern bool ReleaseCapture();
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wp, IntPtr lp);
}
"@
[System.Windows.Forms.Application]::EnableVisualStyles()

# Nur eine Instanz
$script:mutex = New-Object System.Threading.Mutex($false, "Local\ClaudeUsageTray")
if (-not $script:mutex.WaitOne(0)) { exit }

$script:hIcon = [IntPtr]::Zero
$script:lastFive = 0
$script:resp = $null
$script:fetchError = $null
$script:hoverX = $false
$script:settingsDir = Join-Path $env:APPDATA "ClaudeUsageTray"
$script:posFile = Join-Path $script:settingsDir "fenster.txt"
$script:de = [Globalization.CultureInfo]::GetCultureInfo("de-DE")

function C([string]$hex) { return [System.Drawing.ColorTranslator]::FromHtml($hex) }
$script:col = @{
    Lcd = C "#0f2238"; Edge = C "#3a5f86"; Text = C "#cfe6ff"; Muted = C "#8fb8dc"
    Frame = C "#5aa7d8"; Cell = C "#1e4f7a"; Ok = C "#6fdc9a"; Warn = C "#f0c04a"
    Bad = C "#ff6b5e"; Accent = C "#e07a5f"
}

function Get-UsageColor([double]$p) {
    if ($p -ge 85) { return $script:col.Bad }
    if ($p -ge 60) { return $script:col.Warn }
    return $script:col.Ok
}

function ConvertTo-Time($v) {
    if (-not $v) { return $null }
    if ($v -is [datetime]) { return [DateTimeOffset]$v }
    return [DateTimeOffset]::Parse([string]$v, [Globalization.CultureInfo]::InvariantCulture)
}

function Format-Countdown($t) {
    if (-not $t) { return "-" }
    $span = $t - [DateTimeOffset]::Now
    if ($span.TotalSeconds -le 0) { return "jetzt" }
    if ($span.TotalDays -ge 1) { return "{0}d {1}h" -f [int][math]::Floor($span.TotalDays), $span.Hours }
    return "{0}h {1}m" -f [int][math]::Floor($span.TotalHours), $span.Minutes
}

# ---------- Tray-Icon ----------
function Set-TrayIcon([string]$text, [System.Drawing.Color]$color) {
    $bmp = New-Object System.Drawing.Bitmap 32, 32
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $bg = New-Object System.Drawing.SolidBrush $script:col.Lcd
    $g.FillRectangle($bg, 0, 0, 32, 32)
    $pen = New-Object System.Drawing.Pen($color, 3)
    $g.DrawRectangle($pen, 1, 1, 29, 29)
    $size = if ($text.Length -ge 3) { 13 } else { 18 }
    $font = New-Object System.Drawing.Font("Consolas", $size, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = [System.Drawing.StringAlignment]::Center
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
    $tb = New-Object System.Drawing.SolidBrush $color
    $g.DrawString($text, $font, $tb, (New-Object System.Drawing.RectangleF(0, 1, 32, 32)), $sf)
    $g.Dispose(); $font.Dispose(); $bg.Dispose(); $pen.Dispose(); $tb.Dispose()

    $h = $bmp.GetHicon()
    $script:notify.Icon = [System.Drawing.Icon]::FromHandle($h)
    $bmp.Dispose()
    if ($script:hIcon -ne [IntPtr]::Zero) { [void][NativeIcon]::DestroyIcon($script:hIcon) }
    $script:hIcon = $h
}

function Set-Tooltip([string]$text) {
    if ($text.Length -gt 63) { $text = $text.Substring(0, 63) }
    $script:notify.Text = $text
}

# ---------- Display-Popup ----------
$W = 264; $H = 270
# rechte Kante von Akku-Pol und Schliessen-Kreuz
$script:EdgeR = $W - 14
$script:popup = New-Object System.Windows.Forms.Form
$script:popup.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$script:popup.ShowInTaskbar = $false
$script:popup.TopMost = $true
$script:popup.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$script:popup.ClientSize = New-Object System.Drawing.Size($W, $H)
$script:popup.BackColor = $script:col.Lcd
$dbProp = [System.Windows.Forms.Control].GetProperty("DoubleBuffered", [Reflection.BindingFlags]"NonPublic,Instance")
$dbProp.SetValue($script:popup, $true, $null)

$script:fTitle = New-Object System.Drawing.Font("Consolas", 22, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$script:fLabel = New-Object System.Drawing.Font("Consolas", 13, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$script:fPct = New-Object System.Drawing.Font("Consolas", 20, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$script:fPctSign = New-Object System.Drawing.Font("Consolas", 13, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$script:fReset = New-Object System.Drawing.Font("Consolas", 22, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
$script:fSmall = New-Object System.Drawing.Font("Consolas", 12, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)

function Draw-Battery($g, [int]$y, [string]$label, $win) {
    $muted = New-Object System.Drawing.SolidBrush $script:col.Muted
    $text = New-Object System.Drawing.SolidBrush $script:col.Text
    $g.DrawString($label, $script:fLabel, $muted, 16, ($y + 4))

    # Akku: Koerper + Pol, Pol endet an $script:EdgeR
    $poleW = 7
    $bx = 16; $by = $y + 24; $bh = 36
    $bw = $script:EdgeR - $poleW - 2 - $bx
    $cell = New-Object System.Drawing.SolidBrush $script:col.Cell
    $frame = New-Object System.Drawing.Pen($script:col.Frame, 3)
    $fb = New-Object System.Drawing.SolidBrush $script:col.Frame
    $g.FillRectangle($cell, $bx, $by, $bw, $bh)
    $g.DrawRectangle($frame, $bx, $by, $bw, $bh)
    $g.FillRectangle($fb, ($bx + $bw + 2), ($by + 10), $poleW, 16)

    if ($win -and $null -ne $win.utilization) {
        $p = [math]::Min(100, [math]::Max(0, [double]$win.utilization))
        $segs = 20; $gap = 2
        $ix = $bx + 4; $iy = $by + 4; $iw = $bw - 8; $ih = $bh - 8
        $sw = ($iw - ($segs - 1) * $gap) / $segs
        $filled = if ($p -gt 0) { [math]::Max(1, [math]::Ceiling($p / (100 / $segs))) } else { 0 }
        $sb = New-Object System.Drawing.SolidBrush (Get-UsageColor $p)
        for ($i = 0; $i -lt $filled; $i++) {
            $g.FillRectangle($sb, [single]($ix + $i * ($sw + $gap)), [single]$iy, [single]$sw, [single]$ih)
        }
        $sb.Dispose()
        # Prozentwert rechtsbuendig im Akku, mit dunkler Kontur fuer Lesbarkeit auf den Segmenten
        $num = "{0} %" -f [math]::Round($p)
        $sz = $g.MeasureString($num, $script:fPct)
        $tx = [single]($bx + $bw - 6 - $sz.Width + 4)
        $ty = [single]($by + ($bh - $sz.Height) / 2 + 1)
        $shadow = New-Object System.Drawing.SolidBrush $script:col.Lcd
        foreach ($o in @(@(-1,0),@(1,0),@(0,-1),@(0,1),@(1,1))) {
            $g.DrawString($num, $script:fPct, $shadow, [single]($tx + $o[0]), [single]($ty + $o[1]))
        }
        $shadow.Dispose()
        $g.DrawString($num, $script:fPct, $text, $tx, $ty)
    } else {
        $g.DrawString("keine Daten", $script:fLabel, $muted, $bx + 12, $by + 10)
    }
    $muted.Dispose(); $text.Dispose(); $cell.Dispose(); $frame.Dispose(); $fb.Dispose()
}

$script:popup.add_Paint({
    $g = $_.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

    $edge = New-Object System.Drawing.Pen($script:col.Edge, 1)
    $g.DrawRectangle($edge, 0, 0, $W - 1, $H - 1)
    $edge.Dispose()

    # Logo (Stern) + Titel
    $ap = New-Object System.Drawing.Pen($script:col.Accent, 3)
    $ap.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $ap.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $cx = 30; $cy = 30; $r = 10; $q = 7
    $g.DrawLine($ap, $cx, $cy - $r, $cx, $cy + $r)
    $g.DrawLine($ap, $cx - $r, $cy, $cx + $r, $cy)
    $g.DrawLine($ap, $cx - $q, $cy - $q, $cx + $q, $cy + $q)
    $g.DrawLine($ap, $cx + $q, $cy - $q, $cx - $q, $cy + $q)
    $ap.Dispose()
    $text = New-Object System.Drawing.SolidBrush $script:col.Text
    $muted = New-Object System.Drawing.SolidBrush $script:col.Muted
    $g.DrawString("Claude", $script:fTitle, $text, 48, 16)

    $d = if ($script:resp) { $script:resp.data } else { $null }
    $five = if ($d) { $d.five_hour } else { $null }
    $week = if ($d) { $d.seven_day } else { $null }

    Draw-Battery $g 52 "Session genutzt" $five
    Draw-Battery $g 118 "Woche genutzt" $week

    $t5 = if ($five) { ConvertTo-Time $five.resets_at } else { $null }
    $g.DrawString("Reset in $(Format-Countdown $t5)", $script:fReset, $text, 14, 186)

    $t7 = if ($week) { ConvertTo-Time $week.resets_at } else { $null }
    $sub = if ($t7) { "Woche: Reset " + $t7.LocalDateTime.ToString("ddd HH:mm", $script:de) } else { "" }
    $err = if ($script:fetchError) { $script:fetchError } elseif ($script:resp -and $script:resp.error) { $script:resp.error } else { $null }
    if ($err) {
        $wb = New-Object System.Drawing.SolidBrush $script:col.Warn
        $g.DrawString($err, $script:fSmall, $wb, (New-Object System.Drawing.RectangleF(16, 218, ($W - 28), 48)))
        $wb.Dispose()
    } else {
        $g.DrawString($sub, $script:fSmall, $muted, 16, 220)
        if ($script:resp -and $script:resp.data_at) {
            $stand = "Stand " + (ConvertTo-Time $script:resp.data_at).LocalDateTime.ToString("HH:mm")
            $g.DrawString($stand, $script:fSmall, $muted, 16, 238)
        }
    }
    # Schliessen-Kreuz oben rechts
    $xc = if ($script:hoverX) { $script:col.Text } else { $script:col.Muted }
    if ($script:hoverX) {
        $hb = New-Object System.Drawing.SolidBrush $script:col.Cell
        $g.FillRectangle($hb, $script:xRect)
        $hb.Dispose()
    }
    $xp = New-Object System.Drawing.Pen($xc, 2)
    $r0 = $script:xRect
    $g.DrawLine($xp, $r0.Left + 7, $r0.Top + 7, $r0.Right - 7, $r0.Bottom - 7)
    $g.DrawLine($xp, $r0.Right - 7, $r0.Top + 7, $r0.Left + 7, $r0.Bottom - 7)
    $xp.Dispose()

    $text.Dispose(); $muted.Dispose()
})

$script:xRect = New-Object System.Drawing.Rectangle(($script:EdgeR - 19), 10, 26, 26)

function Save-Position {
    try {
        if (-not (Test-Path $script:settingsDir)) { [void](New-Item -ItemType Directory $script:settingsDir) }
        "$($script:popup.Left);$($script:popup.Top);$([int]$script:popup.TopMost)" | Set-Content $script:posFile -Encoding ASCII
    } catch {}
}

function Hide-Popup {
    Save-Position
    $script:popup.Hide()
    $script:popTimer.Stop()
}

$script:popup.add_MouseMove({
    $over = $script:xRect.Contains($_.Location)
    if ($over -ne $script:hoverX) {
        $script:hoverX = $over
        $script:popup.Cursor = if ($over) { [System.Windows.Forms.Cursors]::Hand } else { [System.Windows.Forms.Cursors]::SizeAll }
        $script:popup.Invalidate($script:xRect)
    }
})
$script:popup.add_MouseLeave({ if ($script:hoverX) { $script:hoverX = $false; $script:popup.Invalidate($script:xRect) } })
$script:popup.add_MouseDown({
    if ($_.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    if ($script:xRect.Contains($_.Location)) { Hide-Popup; return }
    # Fenster mit der Maus verschieben
    [void][NativeIcon]::ReleaseCapture()
    [void][NativeIcon]::SendMessage($script:popup.Handle, 0xA1, [IntPtr]2, [IntPtr]::Zero)
    Save-Position
})
$script:popup.add_KeyDown({ if ($_.KeyCode -eq "Escape") { Hide-Popup } })
$script:popup.add_MouseDoubleClick({ if (-not $script:xRect.Contains($_.Location)) { Start-Process $Url } })
$script:popup.Cursor = [System.Windows.Forms.Cursors]::SizeAll

$script:popTimer = New-Object System.Windows.Forms.Timer
$script:popTimer.Interval = 15000
$script:popTimer.add_Tick({ $script:popup.Invalidate() })

function Show-Popup {
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $x = $wa.Right - $W - 12; $y = $wa.Bottom - $H - 12
    try {
        if (Test-Path $script:posFile) {
            $parts = (Get-Content $script:posFile -TotalCount 1) -split ";"
            $px = [int]$parts[0]; $py = [int]$parts[1]
            $rect = New-Object System.Drawing.Rectangle($px, $py, $W, $H)
            # nur uebernehmen, wenn das Fenster auf einem vorhandenen Bildschirm liegt
            foreach ($sc in [System.Windows.Forms.Screen]::AllScreens) {
                if ($sc.WorkingArea.IntersectsWith($rect)) { $x = $px; $y = $py; break }
            }
            if ($parts.Count -ge 3) { $script:popup.TopMost = ($parts[2] -eq "1"); $script:miTop.Checked = $script:popup.TopMost }
        }
    } catch {}
    $script:popup.Location = New-Object System.Drawing.Point($x, $y)
    $script:popup.Show()
    $script:popup.Invalidate()
    $script:popTimer.Start()
}

# ---------- Daten ----------
function Update-Tray {
    try {
        $headers = @{}
        if ($User) {
            $pair = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${User}:${Password}"))
            $headers["Authorization"] = "Basic $pair"
        }
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $script:resp = Invoke-RestMethod -Uri ($Url.TrimEnd("/") + $ApiPath) -Headers $headers -TimeoutSec 15 -UseBasicParsing
        $script:fetchError = $null
        $d = $script:resp.data
        $five = $d.five_hour
        $week = $d.seven_day

        if ($five -and $null -ne $five.utilization) {
            $p = [double]$five.utilization
            Set-TrayIcon ([string][math]::Round($p)) (Get-UsageColor $p)
            $t5 = ConvertTo-Time $five.resets_at
            $tip = "Claude 5h: {0} % - Reset in {1}" -f [math]::Round($p), (Format-Countdown $t5)
            if ($week -and $null -ne $week.utilization) { $tip += "`nWoche: {0} %" -f [math]::Round([double]$week.utilization) }
            Set-Tooltip $tip

            if ($p -ge $WarnPercent -and $script:lastFive -lt $WarnPercent) {
                $script:notify.ShowBalloonTip(5000, "Claude-Limit", ("Session bei {0} % - Reset in {1}" -f [math]::Round($p), (Format-Countdown $t5)), [System.Windows.Forms.ToolTipIcon]::Warning)
            }
            $script:lastFive = $p
        } else {
            Set-TrayIcon "-" ([System.Drawing.Color]::Gray)
            Set-Tooltip "Claude: keine Verbrauchsdaten"
        }
    } catch {
        $script:fetchError = "Server nicht erreichbar: $Url"
        Set-TrayIcon "?" ([System.Drawing.Color]::Gray)
        Set-Tooltip "Claude: Server nicht erreichbar"
    }
    if ($script:popup.Visible) { $script:popup.Invalidate() }
}

# ---------- Tray und Menue ----------
$script:notify = New-Object System.Windows.Forms.NotifyIcon
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$miShow = $menu.Items.Add("Anzeige ein-/ausblenden")
$miShow.add_Click({ if ($script:popup.Visible) { Hide-Popup } else { Show-Popup } })
$script:miTop = New-Object System.Windows.Forms.ToolStripMenuItem("Immer im Vordergrund")
$script:miTop.CheckOnClick = $true
$script:miTop.Checked = $true
$script:miTop.add_Click({ $script:popup.TopMost = $script:miTop.Checked; Save-Position })
[void]$menu.Items.Add($script:miTop)
$miOpen = $menu.Items.Add("Webseite öffnen")
$miOpen.add_Click({ Start-Process $Url })
$miRefresh = $menu.Items.Add("Aktualisieren")
$miRefresh.add_Click({ Update-Tray })
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$miExit = $menu.Items.Add("Beenden")
$miExit.add_Click({
    if ($script:popup.Visible) { Save-Position }
    $script:timer.Stop()
    $script:notify.Visible = $false
    $script:notify.Dispose()
    [System.Windows.Forms.Application]::Exit()
})

$script:notify.ContextMenuStrip = $menu
$script:notify.add_MouseClick({
    if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        if ($script:popup.Visible) { Hide-Popup } else { Show-Popup }
    }
})
Set-TrayIcon "..." ([System.Drawing.Color]::Gray)
$script:notify.Visible = $true

$script:timer = New-Object System.Windows.Forms.Timer
$script:timer.Interval = [math]::Max(15, $RefreshSeconds) * 1000
$script:timer.add_Tick({ Update-Tray })
$script:timer.Start()

Update-Tray
if ($ShowOnStart) { Show-Popup }
[System.Windows.Forms.Application]::Run()
