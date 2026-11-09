#Requires -Version 7.0
<#
.SYNOPSIS
  Creates (or reuses) an Azure Databricks Storage item in a Fabric workspace
  and prints the ID-based OneLake ABFSS path that Databricks needs.

.NOTES
  Why this script exists: Fabric Git integration does not yet support the
  Azure Databricks Storage item, so it is never committed by Source control.
  This script is the source-controlled way to recreate it.

  Prerequisites: PowerShell 7+, Azure CLI signed in (az login) as a user with
  Contributor (or higher) on the target Fabric workspace.
#>
param(
  [string]$ConfigPath = (Join-Path $PSScriptRoot '..' 'config.local.json')
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $ConfigPath)) {
  throw "Config not found: $ConfigPath. Copy config.example.json to config.local.json and fill it in."
}
$cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$api = 'https://api.fabric.microsoft.com/v1'

# --- Auth -------------------------------------------------------------------
$token = az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv
if (-not $token) { throw 'Could not get a Fabric token. Run: az login' }
$headers = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }

function Get-FabricAll([string]$Uri) {
  $all = @()
  while ($Uri) {
    $page = Invoke-RestMethod -Uri $Uri -Headers $headers -Method Get
    $all += $page.value
    $Uri  = $page.continuationUri
  }
  return $all
}

# --- 1. Resolve the workspace ----------------------------------------------
$ws = Get-FabricAll "$api/workspaces" | Where-Object { $_.displayName -eq $cfg.fabricWorkspaceName }
if (-not $ws) { throw "Workspace '$($cfg.fabricWorkspaceName)' not found, or you have no access to it." }
$workspaceId = $ws.id
Write-Host "Workspace: $($cfg.fabricWorkspaceName)"

# --- 2. Reuse the item if it already exists (safe to re-run) ----------------
$item = Get-FabricAll "$api/workspaces/$workspaceId/items?type=AzureDatabricksStorage" |
        Where-Object { $_.displayName -eq $cfg.storageItemName }

if ($item) {
  Write-Host "Item '$($cfg.storageItemName)' already exists - reusing it."
}
else {
  Write-Host "Creating Azure Databricks Storage item '$($cfg.storageItemName)'..."
  $body = @{
    displayName = $cfg.storageItemName
    description = $cfg.storageItemDescription
  } | ConvertTo-Json

  $resp = Invoke-WebRequest -Uri "$api/workspaces/$workspaceId/azureDatabricksStorages" `
                            -Headers $headers -Method Post -Body $body

  if ($resp.StatusCode -eq 201) {
    $item = $resp.Content | ConvertFrom-Json
  }
  elseif ($resp.StatusCode -eq 202) {
    # Long-running operation: poll until it finishes, then read the result
    $opUrl = @($resp.Headers['Location'])[0]
    do {
      Start-Sleep -Seconds 5
      $op = Invoke-RestMethod -Uri $opUrl -Headers $headers -Method Get
      Write-Host "  provisioning... $($op.status)"
    } while ($op.status -in @('NotStarted', 'Running'))
    if ($op.status -ne 'Succeeded') { throw "Item creation failed: $($op | ConvertTo-Json -Depth 5)" }
    $item = Invoke-RestMethod -Uri "$opUrl/result" -Headers $headers -Method Get
  }
  else {
    throw "Unexpected response $($resp.StatusCode): $($resp.Content)"
  }
}

# --- 3. Build the ID-based ABFSS path (display names are rejected) ----------
$abfssPath = "abfss://$workspaceId@onelake.dfs.fabric.microsoft.com/$($item.id)/Files/"

# Save IDs locally (config.local.json is git-ignored)
$cfg | Add-Member -NotePropertyName workspaceId   -NotePropertyValue $workspaceId -Force
$cfg | Add-Member -NotePropertyName storageItemId -NotePropertyValue $item.id     -Force
$cfg | Add-Member -NotePropertyName abfssPath     -NotePropertyValue $abfssPath   -Force
$cfg | ConvertTo-Json -Depth 5 | Set-Content -Path $ConfigPath -Encoding utf8

Write-Host ''
Write-Host 'Done. Use this path for the Databricks external location (Step 5):' -ForegroundColor Green
Write-Host "  $abfssPath"
Write-Host ''
Write-Host 'Saved workspaceId, storageItemId and abfssPath to config.local.json (not committed).'
