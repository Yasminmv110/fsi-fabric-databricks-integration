[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('fabric-repo-check-' + [guid]::NewGuid().ToString('N'))
$checker = Join-Path $PSScriptRoot 'Test-Repository.ps1'

function Assert-Check {
    param([string]$ExpectedError)

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
    Write-Output 'PASS: six checker regression scenarios.'
} finally {
    if (Test-Path -LiteralPath $fixture) {
        Remove-Item -LiteralPath $fixture -Recurse -Force
    }
}
