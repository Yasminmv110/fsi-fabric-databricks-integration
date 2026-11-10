#Requires -Version 7.0
<#
.SYNOPSIS
  Gives the Azure Databricks Access Connector's managed identity the Viewer
  role on the Fabric workspace. The OneLake security role on the storage item
  is a manual step - see README Step 3b.

.NOTES
  Requires: Azure CLI signed in, and Admin on the Fabric workspace
  (adding role assignments needs workspace Admin).
#>
param(
  [string]$ConfigPath = (Join-Path $PSScriptRoot '..' 'config.local.json')
)
$ErrorActionPreference = 'Stop'
$cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$api = 'https://api.fabric.microsoft.com/v1'
if (-not $cfg.workspaceId) { throw 'workspaceId missing - run 01-create-storage-item.ps1 first.' }

# --- 1. Find the managed identity's object (principal) ID -------------------
$principalId = $cfg.accessConnectorPrincipalId
if (-not $principalId) {
  # Works for a system-assigned identity on the access connector.
  # For a user-assigned identity, put its principal (object) ID in config.local.json.
  $principalId = az resource show --ids $cfg.accessConnectorResourceId --query identity.principalId -o tsv
}
if (-not $principalId) { throw 'Could not resolve the access connector managed identity. Set accessConnectorPrincipalId in config.local.json.' }

$token   = az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv
if (-not $token) { throw 'Could not get a Fabric token. Run: az login' }
$headers = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }

# --- 2. Skip if already assigned ------------------------------------------
$existing = @()
$uri = "$api/workspaces/$($cfg.workspaceId)/roleAssignments"
while ($uri) {
  $page = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
  $existing += $page.value
  $uri = $page.continuationUri
}
$match = $existing | Where-Object { $_.principal.id -eq $principalId }

if ($match) {
  Write-Host "Managed identity already has the '$($match.role)' role on the workspace."
}
else {
  $body = @{ principal = @{ id = $principalId; type = 'ServicePrincipal' }; role = 'Viewer' } | ConvertTo-Json
  Invoke-RestMethod -Uri "$api/workspaces/$($cfg.workspaceId)/roleAssignments" -Headers $headers -Method Post -Body $body | Out-Null
  Write-Host 'Granted the Viewer role on the Fabric workspace.' -ForegroundColor Green
}

Write-Host ''
Write-Host 'NEXT (manual, README Step 3b): open the storage item > Manage OneLake security >'
Write-Host 'create a role with ReadWrite and add ONLY this managed identity as its member.'
