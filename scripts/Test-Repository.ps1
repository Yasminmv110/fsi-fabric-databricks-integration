[CmdletBinding()]
param(
    [string]$Root
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}
$Root = (Resolve-Path -LiteralPath $Root).Path
$paths = @(& git -C $Root -c core.quotepath=false ls-files --cached --others --exclude-standard)
if ($LASTEXITCODE -ne 0) {
    throw "Cannot enumerate repository files under $Root."
}

$failures = [System.Collections.Generic.List[string]]::new()
$markdownCount = 0
$jsonCount = 0
$reportCount = 0

foreach ($relative in ($paths | Sort-Object -Unique)) {
    $path = Join-Path $Root $relative.Replace('/', '\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        continue
    }

    $extension = [IO.Path]::GetExtension($path).ToLowerInvariant()
    if ($extension -eq '.md') {
        $markdownCount++
        $fence = $null
        $lineNumber = 0
        foreach ($line in (Get-Content -LiteralPath $path)) {
            $lineNumber++
            if ($line -match '^\s{0,3}(`{3,}|~{3,})(.*)$') {
                $marker = $Matches[1]
                $suffix = $Matches[2]
                if ($null -eq $fence) {
                    $fence = $marker
                } elseif ($marker[0] -eq $fence[0] -and $marker.Length -ge $fence.Length -and [string]::IsNullOrWhiteSpace($suffix)) {
                    $fence = $null
                }
                continue
            }
            if ($null -ne $fence) {
                continue
            }

            foreach ($link in [regex]::Matches($line, '!?\[[^\]]*\]\((?<target><[^>]+>|[^)\s]+)\)')) {
                $target = $link.Groups['target'].Value.Trim('<', '>')
                if ($target -match '^(?:[a-z][a-z0-9+.-]*:|#|//)') {
                    continue
                }
                $target = [Uri]::UnescapeDataString(($target -split '[?#]', 2)[0])
                if ([string]::IsNullOrEmpty($target)) {
                    continue
                }
                $destination = Join-Path (Split-Path -Parent $path) $target.Replace('/', '\')
                if (-not (Test-Path -LiteralPath $destination)) {
                    $failures.Add("${relative}:${lineNumber}: missing Markdown target '$target'.")
                }
            }
        }
        if ($null -ne $fence) {
            $failures.Add("${relative}: unclosed Markdown fence.")
        }
        continue
    }

    if ($extension -notin @('.json', '.pbir', '.pbism') -and [IO.Path]::GetFileName($path) -ne '.platform') {
        continue
    }

    $jsonCount++
    try {
        $document = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        $failures.Add("${relative}: invalid JSON: $($_.Exception.Message)")
        continue
    }
    if ($extension -eq '.pbir') {
        $reportCount++
        $reference = $document.datasetReference.byPath.path
        if (-not [string]::IsNullOrWhiteSpace($reference)) {
            $modelPath = Join-Path (Split-Path -Parent $path) $reference.Replace('/', '\')
            if (-not (Test-Path -LiteralPath $modelPath -PathType Container)) {
                $failures.Add("${relative}: missing report model '$reference'.")
            }
        }
    }
}

if ($failures.Count -gt 0) {
    throw ("Repository validation failed ({0} issue(s)):`n{1}" -f $failures.Count, ($failures -join "`n"))
}

Write-Output "PASS: $markdownCount Markdown files, $jsonCount JSON-format files, $reportCount report references checked."
Write-Output 'Offline structure checks only; cloud behavior, SQL, item schemas, secrets and Mermaid rendering are not validated.'
