<?php
/**
 * Claude-Verbrauch: liefert Abo-Auslastung als JSON (gleiches Format wie die Docker-Variante).
 * Abruf bei Bedarf mit Cache, Token-Erneuerung unter Dateisperre.
 */
declare(strict_types=1);

$cfg = require __DIR__ . '/../config.php';
date_default_timezone_set($cfg['timezone'] ?? 'Europe/Berlin');

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

$dir       = rtrim($cfg['data_dir'], '/');
$credFile  = $dir . '/credentials.json';
$cacheFile = $dir . '/cache.json';
$lockFile  = $dir . '/.lock';
$ttl       = max(60, (int)$cfg['cache_seconds']);
$retry     = max(30, (int)$cfg['retry_seconds']);

final class RefreshError extends RuntimeException {}
final class ApiError extends RuntimeException {}

function out(array $state, int $ttl): void {
    $state['poll_seconds'] = $ttl;
    echo json_encode($state, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function read_json(string $file): ?array {
    if (!is_file($file)) return null;
    $j = json_decode((string)file_get_contents($file), true);
    return is_array($j) ? $j : null;
}

function write_json(string $file, array $data): void {
    $tmp = $file . '.tmp';
    file_put_contents($tmp, json_encode($data, JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT));
    @chmod($tmp, 0600);
    rename($tmp, $file);
}

/** @return array{0:int,1:?array,2:string} [HTTP-Code, JSON, Fehlertext] */
function http(string $url, array $headers, ?array $body = null): array {
    $ch = curl_init($url);
    $opts = [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT        => 20,
        CURLOPT_CONNECTTIMEOUT => 10,
        CURLOPT_HTTPHEADER     => $headers,
    ];
    if ($body !== null) {
        $opts[CURLOPT_POST] = true;
        $opts[CURLOPT_POSTFIELDS] = json_encode($body);
    }
    curl_setopt_array($ch, $opts);
    $raw  = curl_exec($ch);
    $code = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    $err  = $raw === false ? curl_error($ch) : '';
    curl_close($ch);
    $json = is_string($raw) ? json_decode($raw, true) : null;
    return [$code, is_array($json) ? $json : null, $err];
}

function now_ms(): int { return (int)floor(microtime(true) * 1000); }

function refresh_token(array &$creds, array $cfg, string $credFile): void {
    $o = &$creds['claudeAiOauth'];
    $body = ['grant_type' => 'refresh_token', 'refresh_token' => $o['refreshToken'],
             'client_id' => $cfg['client_id']];
    $last = 'kein Token-Endpoint konfiguriert';
    foreach ($cfg['token_urls'] as $url) {
        [$code, $json, $err] = http($url, ['Content-Type: application/json',
                                           'User-Agent: ' . $cfg['user_agent']], $body);
        if ($code === 200 && isset($json['access_token'])) {
            $o['accessToken'] = $json['access_token'];
            if (!empty($json['refresh_token'])) $o['refreshToken'] = $json['refresh_token'];
            if (!empty($json['expires_in'])) $o['expiresAt'] = now_ms() + (int)$json['expires_in'] * 1000;
            write_json($credFile, $creds);
            return;
        }
        $last = $err !== '' ? "$err ($url)" : "HTTP $code von $url";
        if (!in_array($code, [0, 404, 405], true)) break; // Endpoint da, Token abgelehnt
    }
    throw new RefreshError($last);
}

function fetch_usage(array $cfg, string $credFile): array {
    $creds = read_json($credFile);
    if ($creds === null) {
        throw new RuntimeException('credentials.json fehlt oder ist ungültig – bitte in den data-Ordner hochladen.');
    }
    if (empty($creds['claudeAiOauth']['refreshToken'])) {
        throw new RuntimeException('credentials.json unvollständig – bitte neu exportieren.');
    }
    if (($creds['claudeAiOauth']['expiresAt'] ?? 0) - 120000 < now_ms()) {
        refresh_token($creds, $cfg, $credFile);
    }
    $call = function () use (&$creds, $cfg) {
        return http($cfg['usage_url'], [
            'Authorization: Bearer ' . $creds['claudeAiOauth']['accessToken'],
            'anthropic-beta: oauth-2025-04-20',
            'User-Agent: ' . $cfg['user_agent'],
            'Accept: application/json',
        ]);
    };
    [$code, $json, $err] = $call();
    if ($code === 401) {
        refresh_token($creds, $cfg, $credFile);
        [$code, $json, $err] = $call();
    }
    if ($code !== 200 || $json === null) {
        throw new ApiError($err !== '' ? $err : "HTTP $code von {$cfg['usage_url']}");
    }
    return $json;
}

// ---------- Ablauf ----------
if (!is_dir($dir)) {
    out(['ok' => false, 'error' => "Datenordner fehlt: $dir", 'data' => null], $ttl);
}

$cache = read_json($cacheFile) ?? ['ok' => false, 'error' => 'Noch keine Daten', 'data' => null];
$age   = isset($cache['checked_at']) ? time() - (int)$cache['checked_at'] : PHP_INT_MAX;
$limit = !empty($cache['ok']) ? $ttl : $retry;
if ($age < $limit) {
    unset($cache['checked_at']);
    out($cache, $ttl);
}

// Nur ein Abruf gleichzeitig (Token-Rotation darf nicht doppelt laufen)
$lock = fopen($lockFile, 'c');
if ($lock === false || !flock($lock, LOCK_EX | LOCK_NB)) {
    unset($cache['checked_at']);
    out($cache, $ttl); // anderer Aufruf holt gerade – alten Stand liefern
}

$now = gmdate('c');
try {
    $data   = fetch_usage($cfg, $credFile);
    $result = ['ok' => true, 'error' => null, 'data' => $data, 'fetched_at' => $now, 'data_at' => $now];
} catch (RefreshError $e) {
    $result = ['ok' => false, 'error' => 'Token-Erneuerung fehlgeschlagen (' . $e->getMessage() . ') – credentials.json neu hochladen.'];
} catch (ApiError $e) {
    $result = ['ok' => false, 'error' => 'Usage-API-Fehler: ' . $e->getMessage()];
} catch (Throwable $e) {
    $result = ['ok' => false, 'error' => $e->getMessage()];
}

if (!$result['ok']) {
    $result['fetched_at'] = $now;
    $result['data']    = $cache['data'] ?? null;      // letzte gültige Werte behalten
    $result['data_at'] = $cache['data_at'] ?? null;
}
$result['checked_at'] = time();
write_json($cacheFile, $result);
flock($lock, LOCK_UN);
fclose($lock);

unset($result['checked_at']);
out($result, $ttl);
