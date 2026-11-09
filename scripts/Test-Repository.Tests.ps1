[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('fabric-repo-check-' + [guid]::NewGuid().ToString('N'))
$checker = Join-Path $PSScriptRoot 'Test-Repository.ps1'

function Assert-Check {
    param([string]$ExpectedError, [string]$ForbiddenValue)

    $failure = $null
    try {
        & $checker -Root $fixture | Out-Null
    } catch {
        $failure = $_.Exception.Message
    }
    if ([string]::IsNullOrEmpty($ExpectedError)) {
        if ($null -ne $failure) { throw "Expected success, got: $failure" }
    } elseif ($null -eq $failure -or -not $failure.Contains($ExpectedError)) {
        throw "Expected '$ExpectedError', got: $failure"
    }
    if ($ForbiddenValue -and $failure -and $failure.Contains($ForbiddenValue)) {
        throw 'A privacy diagnostic exposed the original identifier.'
    }
}

try {
    New-Item -ItemType Directory -Path $fixture | Out-Null
    & git -C $fixture init --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Cannot initialize validation fixture.' }
    $readme = Join-Path $fixture 'README.md'
    $json = Join-Path $fixture 'sample.json'
    $report = Join-Path $fixture 'definition.pbir'
    New-Item -ItemType Directory -Path (Join-Path $fixture 'Model.SemanticModel') | Out-Null
    [IO.File]::WriteAllText((Join-Path $fixture 'with space.md'), '# Target')
    [IO.File]::WriteAllText($readme, '[Target](with%20space.md)')
    [IO.File]::WriteAllText($json, '{"valid":true}')
    [IO.File]::WriteAllText($report, '{"datasetReference":{"byPath":{"path":"Model.SemanticModel"}}}')
    Assert-Check

    [IO.File]::WriteAllText($readme, '[Missing](missing.md)')
    Assert-Check 'missing Markdown target'
    [IO.File]::WriteAllText($readme, '```text')
    Assert-Check 'unclosed Markdown fence'
    [IO.File]::WriteAllText($readme, '```text' + "`n[Example](not-a-real-target)`n" + '```')
    Assert-Check
    [IO.File]::WriteAllText($json, '{"invalid":')
    Assert-Check 'invalid JSON'
    [IO.File]::WriteAllText($json, '{"valid":true}')
    [IO.File]::WriteAllText($report, '{"datasetReference":{"byPath":{"path":"Missing.SemanticModel"}}}')
    Assert-Check 'missing report model'
    [IO.File]::WriteAllText($report, '{"datasetReference":{"byPath":{"path":"Model.SemanticModel"}}}')
    [IO.File]::WriteAllText($json, ('{"workspaceId":"' + [guid]::NewGuid().ToString() + '"}'))
    Assert-Check 'original GUID detected'
    [IO.File]::WriteAllText($json, '{"workspaceId":"00000000-0000-0000-0000-000000000000"}')
    Assert-Check
    [IO.File]::WriteAllText($json, ('{"endpoint":"test-source.' + 'datawarehouse.fabric.microsoft.com"}'))
    Assert-Check 'environment hostname detected'
    [IO.File]::WriteAllText($json, '{"endpoint":"HOST_PLACEHOLDER.datawarehouse.fabric.microsoft.com"}')
    Assert-Check
    $credential = @{}
    $credential[('pass' + 'word')] = 'fixture-value'
    [IO.File]::WriteAllText($json, ($credential | ConvertTo-Json))
    Assert-Check 'credential value detected'
    [IO.File]::WriteAllText($json, '{"valid":true}')
    $identifier = [guid]::NewGuid().ToString()
    $identifierPath = Join-Path $fixture ($identifier + '.txt')
    [IO.File]::WriteAllText($identifierPath, 'fixture')
    Assert-Check 'original GUID detected' -ForbiddenValue $identifier
    Remove-Item -LiteralPath $identifierPath
    [IO.File]::WriteAllText($json, ('{"token":"' + 'ghp_' + ('x' * 30) + '"}'))
    Assert-Check 'credential signature detected'
    [IO.File]::WriteAllText($json, ('{"name":"' + [guid]::NewGuid().ToString('N').Substring(0,20) + '"}'))
    Assert-Check 'original object ID detected'
    [IO.File]::WriteAllText($json, ('{"name":"' + ('0' * 10) + ('a' * 10) + '"}'))
    Assert-Check
    $deletedPath = Join-Path $fixture 'deleted.md'
    [IO.File]::WriteAllText($deletedPath, '# Deleted fixture')
    & git -C $fixture add -- deleted.md
    if ($LASTEXITCODE -ne 0) { throw 'Cannot stage deletion fixture.' }
    Remove-Item -LiteralPath $deletedPath
    Assert-Check
    Write-Output 'PASS: sixteen checker regression scenarios.'
} finally {
    if (Test-Path -LiteralPath $fixture) {
        Remove-Item -LiteralPath $fixture -Recurse -Force
    }
}

