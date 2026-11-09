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

$guidPattern = '(?i)(?<![0-9a-f])[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(?![0-9a-f])'
$hostPattern = '(?i)[a-z0-9_-]+(?:\.[a-z0-9_-]+)*\.(?:azuredatabricks\.net|datawarehouse\.fabric\.microsoft\.com|dfs\.core\.windows\.net|blob\.core\.windows\.net)'
$tokenPattern = '(?i)\b(?:gh[pousr]_[a-z0-9]{20,}|github_pat_[a-z0-9_]{20,}|dapi[0-9a-f]{24,}|AKIA[0-9A-Z]{16})\b|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|\beyJ[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}\b'
$assignmentPattern = '(?im)["'']?\b(?:password|passwd|client[_-]?secret|accountkey|sharedaccesskey|sas[_-]?token|access[_-]?token|api[_-]?key)\b["'']?\s*[:=]\s*["'']?(?<value>[^"''\s,;]+)'
$urlSecretPattern = '(?i)[?&](?:sig|client_secret|access_token|token)=(?<value>[^&\s"''<>]+)'
$failures = [System.Collections.Generic.List[string]]::new()
$fileCount = 0

function Test-Placeholder {
    param([string]$Value)
    return $Value -match '(?i)placeholder|^<|^\$|^null$|^none$|^\*+$'
}

foreach ($relative in ($paths | Sort-Object -Unique)) {
    $path = Join-Path $Root $relative.Replace('/', '\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        continue
    }
    $fileCount++
    $lines = @($relative) + @(Get-Content -LiteralPath $path)
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        $location = if ($index -eq 0) { 'filename' } else { "line $index" }
        foreach ($match in [regex]::Matches($line, $guidPattern)) {
            if ($match.Value -notmatch '^00000000-0000-0000-0000-') {
                $failures.Add("${relative}: ${location}: original GUID detected (value redacted).")
            }
        }
        foreach ($match in [regex]::Matches($line, $hostPattern)) {
            if (-not (Test-Placeholder $match.Value)) {
                $failures.Add("${relative}: ${location}: environment hostname detected (value redacted).")
            }
        }
        if ($line -match $tokenPattern) {
            $failures.Add("${relative}: ${location}: credential signature detected (value redacted).")
        }
        foreach ($pattern in @($assignmentPattern, $urlSecretPattern)) {
            foreach ($match in [regex]::Matches($line, $pattern)) {
                if (-not (Test-Placeholder $match.Groups['value'].Value)) {
                    $failures.Add("${relative}: ${location}: credential value detected (value redacted).")
                }
            }
        }
    }
}

if ($failures.Count -gt 0) {
    throw ("Privacy validation failed ({0} issue(s)):`n{1}" -f $failures.Count, ($failures -join "`n"))
}
Write-Output "PASS: $fileCount repository files checked for original GUIDs, cloud hostnames and common credential signatures."
Write-Output 'Pattern-based check only; Git history, ignored files and arbitrary identifier formats require separate review.'
