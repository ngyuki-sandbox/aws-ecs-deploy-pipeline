<?php
header('Content-Type: text/plain; charset=utf-8');
var_export([
    'APP_ENV'  => getenv('APP_ENV'),
    '$_SERVER' => $_SERVER,
]);
