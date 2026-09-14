param(
    [ValidateSet('rest', 'rest-client', 'grpc', 'grpc-client', 'web', 'build')]
    [string]$Target = 'rest',
    [int]$RestPort = 8081,
    [int]$GrpcPort = 9090,
    [int]$WebPort = 5500
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ($Target -eq 'web') {
    Write-Host "Dashboard: http://localhost:$WebPort/?apiBase=http://localhost:$RestPort"
    python -m http.server $WebPort --bind 127.0.0.1 --directory (Join-Path $projectRoot 'Question1/web')
    exit $LASTEXITCODE
}

if (-not (Get-Command bal -ErrorAction SilentlyContinue)) {
    throw 'Ballerina is required. Install from https://ballerina.io/downloads/ and reopen PowerShell.'
}

$packages = @{
    'rest' = 'Question1/service'
    'rest-client' = 'Question1/client'
    'grpc' = 'Question2/server'
    'grpc-client' = 'Question2/client'
}

if ($Target -eq 'build') {
    foreach ($package in @('Question1/service', 'Question1/client', 'Question2/server', 'Question2/client')) {
        Push-Location (Join-Path $projectRoot $package)
        try {
            bal build
            if ($LASTEXITCODE -ne 0) { throw "Build failed: $package" }
        } finally { Pop-Location }
    }
    exit 0
}

$configArg = switch ($Target) {
    'rest' { "-CservicePort=$RestPort" }
    'rest-client' { "-CapiUrl=http://localhost:$RestPort" }
    'grpc' { "-CserverPort=$GrpcPort" }
    'grpc-client' { "-CserverUrl=http://localhost:$GrpcPort" }
}

Push-Location (Join-Path $projectRoot $packages[$Target])
try {
    bal run -- $configArg
    $runExitCode = $LASTEXITCODE
} finally { Pop-Location }
exit $runExitCode
