#Requires -Version 7.0
<#
.SYNOPSIS
  Deletes the Azure Databricks Storage item from the Fabric workspace.

.WARNING
  This permanently deletes the OneLake data that Unity Catalog stored in the
  item. Drop the Databricks catalog first (databricks/03-teardown.sql).
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
  [string]$ConfigPath = (Join-Path $PSScriptRoot '..' 'config.local.json')
)
$ErrorActionPreference = 'Stop'
$cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
if (-not $cfg.storageItemId) { throw 'storageItemId missing in config.local.json - nothing to delete.' }

$token   = az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv
$headers = @{ Authorization = "Bearer $token" }

if ($PSCmdlet.ShouldProcess($cfg.storageItemName, 'Delete Azure Databricks Storage item and all of its data')) {
  Invoke-RestMethod -Method Delete -Headers $headers `
    -Uri "https://api.fabric.microsoft.com/v1/workspaces/$($cfg.workspaceId)/items/$($cfg.storageItemId)" | Out-Null
  Write-Host "Deleted '$($cfg.storageItemName)'." -ForegroundColor Yellow
}
