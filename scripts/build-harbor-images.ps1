[CmdletBinding()]
param(
    [string]$Repository = "harbor.trscd.com.cn/baseapp/bigbodycobain-shadowbroker",
    [string]$Tag = "",
    [switch]$Push,
    [switch]$PrintOnly
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

if ([string]::IsNullOrWhiteSpace($Tag)) {
    $shortSha = ""
    if (Get-Command git -ErrorAction SilentlyContinue) {
        try {
            git rev-parse --is-inside-work-tree *> $null
            if ($LASTEXITCODE -eq 0) {
                $shortSha = (git rev-parse --short HEAD).Trim()
            }
        } catch {
            $shortSha = ""
        }
    }

    if ([string]::IsNullOrWhiteSpace($shortSha)) {
        $shortSha = $env:CI_COMMIT_SHORT_SHA
    }

    if ([string]::IsNullOrWhiteSpace($shortSha)) {
        $shortSha = $env:SHADOWBROKER_GIT_SHORT_SHA
    }

    if ([string]::IsNullOrWhiteSpace($shortSha)) {
        throw "Could not determine short git SHA. Install git, run inside a git checkout, or set SHADOWBROKER_GIT_SHORT_SHA/CI_COMMIT_SHORT_SHA."
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $Tag = "$shortSha-$timestamp"
}

$env:SHADOWBROKER_IMAGE_REPOSITORY = $Repository
$env:SHADOWBROKER_IMAGE_TAG = $Tag

$backendImage = "${Repository}:backend-${Tag}"
$frontendImage = "${Repository}:frontend-${Tag}"

Write-Host "SHADOWBROKER_IMAGE_TAG=$Tag"
Write-Host "Backend image:  $backendImage"
Write-Host "Frontend image: $frontendImage"

if ($PrintOnly) {
    return
}

$composeCommand = $null
try {
    docker compose version *> $null
    if ($LASTEXITCODE -eq 0) {
        $composeCommand = @("docker", "compose")
    }
} catch {
    $composeCommand = $null
}

if (-not $composeCommand -and (Get-Command docker-compose -ErrorAction SilentlyContinue)) {
    $composeCommand = @("docker-compose")
}

if (-not $composeCommand) {
    throw "Could not find docker compose or docker-compose."
}

function Invoke-Compose {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

    if ($composeCommand.Length -eq 1) {
        & $composeCommand[0] @Arguments
    } else {
        & $composeCommand[0] $composeCommand[1] @Arguments
    }
}

Invoke-Compose -f docker-compose.yml -f docker-compose.harbor.yml build

if ($Push) {
    Invoke-Compose -f docker-compose.yml -f docker-compose.harbor.yml push
}
