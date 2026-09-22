$root = Split-Path -Parent $PSScriptRoot
$jp = Join-Path $root 'mushroom_catalog.json'
$out = Join-Path $env:TEMP 'opencode\stats.txt'
$lines = @()
function L($k, $v) { $script:lines += ($k + ' = ' + $v) }

$txt = [IO.File]::ReadAllText($jp)
$c = $txt | ConvertFrom-Json

$ph = @($c.species | Where-Object { $_.has_photo })
L 'photo_species' $ph.Count
$rb = @($ph | Where-Object { $_.red_listed })
L 'photo_red_listed' $rb.Count

$allFeat = @($c.species | Where-Object { $_.features -and $_.features.Length -gt 5 })
L 'all_with_features' $allFeat.Count
$noPhFeat = @($c.species | Where-Object { (-not $_.has_photo) -and $_.features -and ($_.features.Length -gt 5) })
L 'photoless_with_features' $noPhFeat.Count
$phFeat = @($c.species | Where-Object { $_.has_photo -and $_.features -and ($_.features.Length -gt 5) })
L 'photo_with_features' $phFeat.Count
$ai = @($c.species | Where-Object { $_.ai_recognition })
L 'ai_species' $ai.Count
$aiPhoto = @($ai | Where-Object { $_.has_photo })
L 'ai_with_photo' $aiPhoto.Count
$aiFeat = @($ai | Where-Object { $_.features -and ($_.features.Length -gt 5) })
L 'ai_with_features' $aiFeat.Count

# descriptions_200.csv vs JSON
$d = Import-Csv (Join-Path $root 'descriptions_200.csv') -Encoding UTF8
L 'desc_rows' $d.Count
$descLatin = @{}
foreach ($r in $d) { $descLatin[$r.scientific_name.Trim()] = $true }
$inJson = 0; $inJsonPhoto = 0; $inJsonMasterFeat = 0
foreach ($x in $c.species) {
    if ($descLatin.ContainsKey($x.latin)) {
        $inJson++
        if ($x.has_photo) { $inJsonPhoto++ }
        if ($x.features -and $x.features.Length -gt 5) { $inJsonMasterFeat++ }
    }
}
L 'desc_in_json' $inJson
L 'desc_in_json_with_photo' $inJsonPhoto
L 'desc_in_json_and_master_feat' $inJsonMasterFeat

$ag = $c.species | Where-Object { $_.latin -eq 'Agaricus arvensis' } | Select-Object -First 1
if ($ag) {
    $fl = 0
    if ($ag.features) { $fl = $ag.features.Length }
    L 'agaricus_arvensis' ('photo=' + $ag.has_photo + ' feat_len=' + $fl + ' ai=' + $ag.ai_recognition)
} else {
    L 'agaricus_arvensis' 'NOT_IN_JSON'
}

# master.csv: rows with features - photo/ai split
$csv = Import-Csv (Join-Path $root 'master.csv') -Encoding UTF8
$mf = @($csv | Where-Object { $_.key_features_ai -and $_.key_features_ai.Trim() })
L 'master_features_rows' $mf.Count
$mfAi = @($mf | Where-Object { $_.in_ai_recognition -eq '1' })
L 'master_feat_and_ai' $mfAi.Count

foreach ($f in (Get-ChildItem $root -File -Filter '*.txt')) { L 'root_txt' $f.Name }

if ($allFeat.Count) {
    $f0 = $allFeat[0]
    L 'feat_sample_name' ($f0.name + ' photo=' + $f0.has_photo + ' ai=' + $f0.ai_recognition)
    L 'feat_sample_text' $f0.features.Substring(0, [Math]::Min(200, $f0.features.Length))
}

[IO.File]::WriteAllLines($out, $lines, (New-Object System.Text.UTF8Encoding($false)))
Write-Output ('lines=' + $lines.Count + ' -> ' + $out)
