# diag_table.ps1 — структура таблиця грибів.txt по секціях → scripts/_diag.txt
$ErrorActionPreference = 'Stop'
$Project = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$out = New-Object System.Collections.ArrayList
$lines = [IO.File]::ReadAllLines((Join-Path $Project 'таблиця грибів.txt'))

$sec = 0
$stats = @{}   # sec -> colcount -> count
$samples = @{} # sec -> перший рядок
foreach ($l in $lines) {
    if ($l -eq '') { continue }
    if ($l -notmatch '^\d+\t') {
        # заголовок секції: шукаємо перше число в рядку-заголовку
        $m = [regex]::Match($l, '(\d+)\.')
        if ($m.Success -and $l.Trim().Length -lt 90 -and $l -notmatch '^\d+\t') {
            $maybe = [int]$m.Groups[1].Value
            if ($maybe -ge 1 -and $maybe -le 10) { $sec = $maybe }
        }
        continue
    }
    $c = $l -split "`t"
    $n = $c.Count
    if (-not $stats.ContainsKey($sec)) { $stats[$sec] = @{} }
    if (-not $stats[$sec].ContainsKey($n)) { $stats[$sec][$n] = 0 }
    $stats[$sec][$n] = 1 + $stats[$sec][$n]
    if (-not $samples.ContainsKey($sec)) { $samples[$sec] = $l }
}

[void]$out.Add('=== колонок у рядках по секціях ===')
foreach ($k in ($stats.Keys | Sort-Object)) {
    $parts = $stats[$k].GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name)cols x $($_.Value)" }
    [void]$out.Add("section ${k}: " + ($parts -join ', '))
}
[void]$out.Add('')
[void]$out.Add('=== перший рядок кожної секції (колонки через |) ===')
foreach ($k in ($samples.Keys | Sort-Object)) {
    $c = $samples[$k] -split "`t"
    [void]$out.Add("section $k ($($c.Count) cols):")
    for ($i = 0; $i -lt $c.Count; $i++) {
        [void]$out.Add(("  [{0}] {1}" -f $i, $c[$i]))
    }
    [void]$out.Add('')
}

# --- також: дублікати латин у master.csv та фактичні фото ---
[void]$out.Add('=== master.csv: дублікати scientific_name ===')
$master = Import-Csv (Join-Path $Project 'desktop-tutorial\master.csv') -Encoding UTF8
$dups = $master | Group-Object scientific_name | Where-Object { $_.Count -gt 1 }
if ($dups) {
    foreach ($d in $dups) { [void]$out.Add("  DUPE: $($d.Name) x$($d.Count)") }
} else { [void]$out.Add('  немає') }

[void]$out.Add('')
[void]$out.Add('=== photo-папки: унікальні latin ===')
$dirNames = @()
foreach ($pd in @('фото Топ-20 грибів (webp)', 'фото популярні 55 грибів (webp)')) {
    $base = Join-Path (Join-Path $Project 'desktop-tutorial') $pd
    if (Test-Path $base) { foreach ($d in (Get-ChildItem $base -Directory)) { $dirNames += $d.Name } }
}
[void]$out.Add(("папок: {0}" -f $dirNames.Count))

[IO.File]::WriteAllLines((Join-Path $PSScriptRoot '_diag.txt'), $out, (New-Object System.Text.UTF8Encoding($false)))
Write-Output 'diag written'
