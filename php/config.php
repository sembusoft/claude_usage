<?php
// Konfiguration – bei Bedarf anpassen.
return [
    // Ordner mit credentials.json und Cache. Am besten AUSSERHALB des Webroots,
    // z. B. __DIR__ . '/../claude-usage-data'. Standard: data/ (per .htaccess gesperrt).
    'data_dir'      => __DIR__ . '/data',

    // Wie lange ein Abruf zwischengespeichert wird (Sekunden, min. 60).
    'cache_seconds' => 300,

    // Nach einem Fehler erst nach so vielen Sekunden erneut versuchen.
    'retry_seconds' => 60,

    'usage_url'     => 'https://api.anthropic.com/api/oauth/usage',
    'token_urls'    => [
        'https://platform.claude.com/v1/oauth/token',
        'https://console.anthropic.com/v1/oauth/token',
    ],
    'client_id'     => '9d1c250a-e61b-44d9-88ed-5944d1962f5e',
    'user_agent'    => 'claude-code/2.0.0',
    'timezone'      => 'Europe/Berlin',
];
