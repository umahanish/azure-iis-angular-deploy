<#
.SYNOPSIS
    Downloads a zipped Angular release from an Azure Storage blob (via SAS URL)
    and deploys it to an IIS site, with a timestamped backup of the previous
    deployment and an app pool recycle.

.NOTES
    Runs ON THE VM via: az vm run-command invoke --command-id RunPowerShellScript
    Exit code non-zero => the GitHub Actions job fails.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$BlobSasUrl,

    [string]$SitePath = "C:\inetpub\wwwroot",

    [string]$AppPoolName = "DefaultAppPool",

    [string]$BackupRoot = "C:\iis-backups",

    [string]$WorkRoot = "C:\deploy-temp"
)

$ErrorActionPreference = "Stop"
Import-Module WebAdministration

$timestamp    = Get-Date -Format "yyyyMMdd-HHmmss"
$downloadZip  = Join-Path $WorkRoot "release-$timestamp.zip"
$extractPath  = Join-Path $WorkRoot "release-$timestamp"
$backupPath   = Join-Path $BackupRoot $timestamp

New-Item -ItemType Directory -Force -Path $WorkRoot    | Out-Null
New-Item -ItemType Directory -Force -Path $extractPath | Out-Null
New-Item -ItemType Directory -Force -Path $BackupRoot  | Out-Null

try {
    Write-Output "== Downloading release package =="
    Invoke-WebRequest -Uri $BlobSasUrl -OutFile $downloadZip -UseBasicParsing

    Write-Output "== Extracting package =="
    Expand-Archive -Path $downloadZip -DestinationPath $extractPath -Force

    Write-Output "== Stopping app pool: $AppPoolName =="
    if ((Get-WebAppPoolState -Name $AppPoolName).Value -ne "Stopped") {
        Stop-WebAppPool -Name $AppPoolName
        Start-Sleep -Seconds 5
    }

    if ((Test-Path $SitePath) -and (Get-ChildItem $SitePath -ErrorAction SilentlyContinue)) {
        Write-Output "== Backing up current site to $backupPath =="
        New-Item -ItemType Directory -Force -Path $backupPath | Out-Null
        Copy-Item -Path (Join-Path $SitePath '*') -Destination $backupPath -Recurse -Force
    }

    Write-Output "== Deploying new files to $SitePath =="
    New-Item -ItemType Directory -Force -Path $SitePath | Out-Null
    robocopy $extractPath $SitePath /MIR /NFL /NDL /NJH /NJS /R:3 /W:5
    if ($LASTEXITCODE -ge 8) {
        throw "robocopy failed with exit code $LASTEXITCODE"
    }

    Write-Output "== Starting app pool: $AppPoolName =="
    Start-WebAppPool -Name $AppPoolName

    Write-Output "== Deployment complete =="
}
catch {
    Write-Error "Deployment failed: $_"

    # Best-effort rollback if a backup exists
    if (Test-Path $backupPath) {
        Write-Output "== Attempting rollback from $backupPath =="
        robocopy $backupPath $SitePath /MIR /NFL /NDL /NJH /NJS
        if ((Get-WebAppPoolState -Name $AppPoolName).Value -eq "Stopped") {
            Start-WebAppPool -Name $AppPoolName
        }
    }
    throw
}
finally {
    Write-Output "== Cleaning up temp files =="
    Remove-Item -Path $downloadZip -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $extractPath -Recurse -Force -ErrorAction SilentlyContinue
}
