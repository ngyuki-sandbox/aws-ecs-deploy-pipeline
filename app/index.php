<?php
header('Content-Type: text/plain; charset=utf-8');
$envs = $_ENV;
ksort($envs);
var_export([
    '$_ENV' => $envs,
]);
