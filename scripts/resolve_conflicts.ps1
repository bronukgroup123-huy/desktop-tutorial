# resolve_conflicts.ps1 - strip git conflict markers, keeping one side per hunk.
# ASCII-only. Decisions: string of M/T per hunk in file order (M=ours/HEAD, T=theirs/origin).
param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Decisions
)
$ErrorActionPreference = 'Stop'
$bytes = [IO.File]::ReadAllBytes($Path)
$hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
$text = [IO.File]::ReadAllText($Path)
$nl = "`n"
if ($text.Contains("`r`n")) { $nl = "`r`n" }
$lines = $text -split "`r`n|`n"
$out = New-Object System.Collections.Generic.List[string]
$hunk = 0
$inC = $false
$side = 'ours'
for ($i = 0; $i -lt $lines.Count; $i++) {
    $l = $lines[$i]
    if (-not $inC -and $l.StartsWith('<<<<<<< ')) {
        $inC = $true
        $side = 'ours'
        if ($hunk -ge $Decisions.Length) { throw 'more hunks than decisions' }
        continue
    }
    if ($inC -and $l -eq '=======') { $side = 'theirs'; continue }
    if ($inC -and $l.StartsWith('>>>>>>> ')) {
        $inC = $false
        $hunk++
        continue
    }
    $take = $true
    if ($inC) {
        $d = $Decisions[$hunk]
        if ($d -eq 'T') { $take = ($side -eq 'theirs') }
        else { $take = ($side -eq 'ours') }
    }
    if ($take) { [void]$out.Add($l) }
}
if ($inC) { throw 'unterminated conflict block' }
if ($hunk -ne $Decisions.Length) {
    throw ('hunk count ' + $hunk + ' != decisions ' + $Decisions.Length)
}
$enc = New-Object System.Text.UTF8Encoding($hasBom)
[IO.File]::WriteAllText($Path, ($out -join $nl), $enc)
Write-Output ('resolved hunks=' + $hunk + ' lines=' + $out.Count + ' crlf=' + ($nl -eq "`r`n") + ' bom=' + $hasBom)
