# sync_check.ps1 - extract GitHub compare summary + retry git fetch reliably.
# ASCII-only; Cyrillic paths arrive as parameters.
param(
    [Parameter(Mandatory = $true)][string]$RepoPath,
    [Parameter(Mandatory = $true)][string]$CompareJson
)
$ErrorActionPreference = 'Continue'
$summary = New-Object System.Collections.ArrayList

if (Test-Path $CompareJson) {
    $t = [IO.File]::ReadAllText($CompareJson)
    [void]$summary.Add('json len=' + $t.Length)
    $ms = [regex]::Match($t, '"status":"([a-z_]+)","ahead_by":(\d+),"behind_by":(\d+),"total_commits":(\d+)')
    [void]$summary.Add('status=' + $ms.Groups[1].Value + ' ahead=' + $ms.Groups[2].Value +
        ' behind=' + $ms.Groups[3].Value + ' total_commits=' + $ms.Groups[4].Value)
    $ci = $t.IndexOf('"commits":[')
    $fi = $t.IndexOf('"files":[')
    if ($ci -ge 0 -and $fi -gt $ci) {
        $sec = $t.Substring($ci, $fi - $ci)
        [void]$summary.Add('--- commits (remote ahead) ---')
        foreach ($m in [regex]::Matches($sec, '"message":"((?:[^"\\]|\\.)*)"')) {
            [void]$summary.Add('  * ' + $m.Groups[1].Value)
        }
    }
    if ($fi -ge 0) {
        $sec2 = $t.Substring($fi)
        $fn = [regex]::Matches($sec2, '"filename":"([^"]+)"')
        [void]$summary.Add('--- files changed (' + $fn.Count + ') ---')
        foreach ($x in $fn) { [void]$summary.Add('  ' + $x.Groups[1].Value) }
    }
} else {
    [void]$summary.Add('compare json NOT FOUND: ' + $CompareJson)
}
$summaryPath = Join-Path $env:TEMP 'opencode\compare.txt'
[IO.File]::WriteAllLines($summaryPath, $summary, (New-Object System.Text.UTF8Encoding($false)))
Write-Output ('summary written: ' + $summary.Count + ' lines -> ' + $summaryPath)

# --- fetch attempts ---
$env:GIT_TERMINAL_PROMPT = '0'
$env:GCM_INTERACTIVE = 'never'
$env:Path += ';C:\Program Files\Git\cmd'
Set-Location $RepoPath
$fetched = $false
for ($a = 1; $a -le 3; $a++) {
    Write-Output ('--- fetch attempt ' + $a + ' ---')
    & git -c http.version=HTTP/1.1 -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=30 fetch origin --no-tags
    if ($LASTEXITCODE -eq 0) { $fetched = $true; break }
    Write-Output ('fetch failed, exit=' + $LASTEXITCODE)
    Start-Sleep -Seconds 5
}
if ($fetched) {
    Write-Output 'FETCH OK'
    $ab = & git rev-list --left-right --count 'HEAD...origin/main'
    Write-Output ('ahead-behind HEAD...origin/main = ' + $ab)
} else {
    Write-Output 'FETCH FAILED after 3 attempts'
}
