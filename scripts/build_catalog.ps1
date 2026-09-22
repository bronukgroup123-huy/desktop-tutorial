# build_catalog.ps1 — генерує mushroom_catalog.json та вбудовує його в mushroom-radar.html
#
# Джерела даних:
#   1. master.csv                       — базовий список видів (назви, їстівність, прапорці)
#   2. пошук/baza200_json_*.json        — атрибути 200 видів (колір шапки, кільце/піхва, сезон, мікориза)
#   3. таблиця грибів.txt               — дерево/ліс і сезон для топ-20 (частина 1 таблиці)
#   4. папки фото (webp)                — наявність фото per species
#
# Результат:
#   - desktop-tutorial/mushroom_catalog.json      (готовий для Flutter/Supabase)
#   - вставка в mushroom-radar.html між маркерами <!-- CATALOG:START/END -->
#   - лог: scripts/build_catalog.log
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)
$ErrorActionPreference = 'Stop'
$Project = Split-Path -Parent $Root
$logPath = Join-Path $PSScriptRoot 'build_catalog.log'

function Log([string]$msg) {
    $line = '{0:HH:mm:ss} {1}' -f (Get-Date), $msg
    Add-Content -Path $logPath -Value $line -Encoding UTF8
    Write-Host $line
}

# ============================================================
# [1] master.csv
# ============================================================
Log '[1] chytaiu master.csv ...'
$master = Import-Csv (Join-Path $Root 'master.csv') -Encoding UTF8
Log ('[1] riadkiv: ' + $master.Count)

# --- зведення дублікатів (однакова латинська назва) ---
$dupMerged = 0
$merged = New-Object System.Collections.ArrayList
$idxByLatin = @{}
foreach ($row in $master) {
    $ln = [string]$row.scientific_name
    if ($idxByLatin.ContainsKey($ln)) {
        $first = $merged[$idxByLatin[$ln]]
        foreach ($f in @('in_top20', 'is_popular', 'in_ai_recognition', 'is_red_listed', 'is_poisonous', 'is_deadly', 'has_photos')) {
            if ($row.$f -eq '1') { $first.$f = '1' }
        }
        if ((-not $first.photo_path) -and $row.photo_path) { $first.photo_path = $row.photo_path }
        if ((-not $first.rarity_label_uk) -and $row.rarity_label_uk) { $first.rarity_label_uk = $row.rarity_label_uk }
        if ((-not $first.key_features_ai) -and $row.key_features_ai) { $first.key_features_ai = $row.key_features_ai }
        if ((-not $first.season) -and $row.season) { $first.season = $row.season }
        if ((-not $first.zones) -and $row.zones) { $first.zones = $row.zones }
        $dupMerged++
    } else {
        $idxByLatin[$ln] = $merged.Count
        [void]$merged.Add($row)
    }
}
Log ('[1] unikalnyh: ' + $merged.Count + ' (zvedeno dubl: ' + $dupMerged + ')')

# --- backfill описів із descriptions_200.csv (канонічне джерело описів бази ШІ) ---
$descMap = @{}
$descPath = Join-Path $Root 'descriptions_200.csv'
if (Test-Path $descPath) {
    foreach ($drow in (Import-Csv $descPath -Encoding UTF8)) {
        $dl = ([string]$drow.scientific_name).Trim()
        if ($dl -and $drow.key_features_ai) { $descMap[$dl] = [string]$drow.key_features_ai }
    }
    Log ('[1] opysiv u descriptions_200: ' + $descMap.Count)
    $descBackfilled = 0
    foreach ($row in $merged) {
        if (-not $row.key_features_ai -or -not $row.key_features_ai.Trim()) {
            $ln2 = ([string]$row.scientific_name).Trim()
            if ($descMap.ContainsKey($ln2)) { $row.key_features_ai = $descMap[$ln2]; $descBackfilled++ }
        }
    }
    Log ('[1] backfill opysiv u merged: ' + $descBackfilled)
} else {
    Log '[1] descriptions_200.csv NEMAIE (backfill vymkneno)'
}

# ============================================================
# [2] фото: скануємо папки, будуємо latin -> relpath
# ============================================================
Log '[2] skanuiu papky foto ...'
$alias = @{
    'Suillellus luridus'   = 'Boletus luridus'
    'Leccinum rufum'       = 'Leccinum albostipitatum'
    'Collybia personata'   = 'Lepista personata'
    'Collybia nuda'        = 'Lepista nuda'
    'Lactifluus vellereus' = 'Lactarius vellereus'
    'Lactifluus piperatus' = 'Lactarius piperatus'
    'Cerioporus squamosus' = 'Polyporus squamosus'
}
# Червона книга — першою, щоб наявні фото з інших папок не перезаписувалися
$photoDirs = @('Червона книга (webp)', 'фото Топ-20 грибів (webp)', 'фото популярні 55 грибів (webp)', 'Отруйні та смертельно отруйні (webp)')
$photoByTarget = @{}
$dirProblems = @()
foreach ($d in $photoDirs) {
    $base = Join-Path $Root $d
    if (-not (Test-Path $base)) { Log ('[2] NEMAIE papky: ' + $d); continue }
    foreach ($dir in (Get-ChildItem $base -Directory)) {
        $lat = @()
        foreach ($tk in ($dir.Name -split ' ')) {
            if ($tk -match '^[A-Za-z][A-Za-z\.\-]*$') { $lat += $tk }
            elseif ($lat.Count -gt 0) { break }
        }
        if ($lat.Count -lt 2) { $dirProblems += $dir.Name; continue }
        $folderLatin = $lat -join ' '
        $target = $folderLatin
        if ($alias.ContainsKey($folderLatin)) { $target = $alias[$folderLatin] }
        $file = Join-Path $dir.FullName 'large.webp'
        if (-not (Test-Path $file)) {
            $any = Get-ChildItem $dir.FullName -Filter '*.webp' -File | Select-Object -First 1
            if ($any) { $file = $any.FullName } else { $dirProblems += ($dir.Name + ' (nemaie webp)'); continue }
        }
        $rel = $d + '/' + $dir.Name + '/' + (Split-Path -Leaf $file)
        if ($photoByTarget.ContainsKey($target)) { Log ('[2] koliziya papok: ' + $target) }
        $photoByTarget[$target] = $rel
    }
}
Log ('[2] foto zistavleno: ' + $photoByTarget.Count)
if ($dirProblems.Count) { Log ('[2] problemni papky: ' + ($dirProblems -join ' | ')) }

# ============================================================
# [3] baza200 JSON — атрибути для 200 видів
# ============================================================
Log '[3] chytaiu baza200 JSON ...'
$bazaFile = Get-ChildItem (Join-Path $Project 'пошук') -Filter 'baza200_json_*.json' | Sort-Object Name | Select-Object -Last 1
if (-not $bazaFile) { throw 'baza200_json_*.json ne znaideno' }
Log ('[3] fajl: ' + $bazaFile.Name)
$raw = [IO.File]::ReadAllText($bazaFile.FullName)
$baza = $raw | ConvertFrom-Json
Log ('[3] zapysiv: ' + $baza.Count)

# --- мапи токенів -------------------------------------------------------
$colorTok = @{
    'white' = 'white'; 'cream' = 'white'; 'whitish' = 'white'; 'ivory' = 'white'
    'grey' = 'grey'; 'gray' = 'grey'; 'greyish' = 'grey'; 'silvery' = 'grey'
    'brown' = 'brown'; 'brownish' = 'brown'; 'chestnut' = 'brown'; 'sepia' = 'brown'; 'leather' = 'brown'
    'yellow' = 'yellow'; 'yellowish' = 'yellow'; 'lemon' = 'yellow'; 'sulphur' = 'yellow'; 'golden' = 'yellow'; 'gold' = 'yellow'
    'ochre' = 'ochre'
    'orange' = 'orange'
    'red' = 'red'; 'reddish' = 'red'; 'brick' = 'red'; 'blood' = 'red'; 'scarlet' = 'red'; 'crimson' = 'red'
    'pink' = 'pink'; 'rose' = 'pink'
    'purple' = 'purple'; 'violet' = 'purple'; 'lilac' = 'purple'; 'wine' = 'purple'
    'blue' = 'blue'; 'bluish' = 'blue'
    'green' = 'green'; 'greenish' = 'green'
    'olive' = 'olive'
    'black' = 'black'; 'blackish' = 'black'
    'rust' = 'russet'; 'rusty' = 'russet'; 'russet' = 'russet'
    'beige' = 'beige'; 'buff' = 'beige'; 'tan' = 'beige'
}
$treeTok = @{
    'pine' = 'pine'; 'spruce' = 'spruce'; 'fir' = 'spruce'; 'larch' = 'larch'; 'oak' = 'oak'; 'birch' = 'birch'
    'aspen' = 'aspen'; 'poplar' = 'poplar'; 'willow' = 'willow'; 'alder' = 'alder'; 'hornbeam' = 'hornbeam'
    'beech' = 'beech'; 'lime' = 'lime'; 'maple' = 'maple'; 'elm' = 'elm'; 'ash' = 'ash'; 'hazel' = 'hazel'; 'chestnut' = 'chestnut'
    'mixed' = 'mixed'; 'deciduous' = 'deciduous'; 'broadleaf' = 'deciduous'
    'coniferous' = 'coniferous'; 'conifer' = 'coniferous'; 'conifers' = 'coniferous'
    'any' = 'any'
}
$mycoTok = @{
    'pinus' = 'pine'; 'picea' = 'spruce'; 'abies' = 'spruce'; 'larix' = 'larch'; 'quercus' = 'oak'; 'betula' = 'birch'
    'salix' = 'willow'; 'alnus' = 'alder'; 'carpinus' = 'hornbeam'; 'fagus' = 'beech'; 'tilia' = 'lime'; 'acer' = 'maple'
    'ulmus' = 'elm'; 'fraxinus' = 'ash'; 'corylus' = 'hazel'; 'aesculus' = 'chestnut'
    'populus' = 'aspen,poplar'; 'tremula' = 'aspen'
}
$monthEn = @{
    'january' = 1; 'february' = 2; 'march' = 3; 'april' = 4; 'may' = 5; 'june' = 6
    'july' = 7; 'august' = 8; 'september' = 9; 'october' = 10; 'november' = 11; 'december' = 12
}
$monthUk = @{
    'січень' = 1; 'лютий' = 2; 'березень' = 3; 'квітень' = 4; 'травень' = 5; 'червень' = 6
    'липень' = 7; 'серпень' = 8; 'вересень' = 9; 'жовтень' = 10; 'листопад' = 11; 'грудень' = 12
}
# слоти місць/середовищ, які НЕ є деревами (щоб не смітити в лог невідомих)
$notTree = @(
    'forest', 'forests', 'woods', 'woodland', 'edges', 'edge', 'grassland', 'meadows', 'meadow', 'pasture', 'pastures'
    'gardens', 'garden', 'parks', 'park', 'roadsides', 'roadside', 'dunes', 'dune', 'field', 'fields'
    'swamps', 'swamp', 'streamside', 'bog', 'bogs', 'boggy', 'hedgerows', 'clearings', 'clearing'
    'banks', 'bank', 'sandy', 'decayed', 'rotten', 'damp', 'humus', 'soil', 'soils', 'ground', 'litter'
    'deadwood', 'stumps', 'stump', 'trunks', 'trunk', 'bark', 'lawn', 'lawns', 'waste', 'places'
    'manured', 'rich', 'nutrient', 'dry', 'wet', 'dung', 'moss', 'mosses', 'sphagnum', 'peat'
    'leaf', 'leaves', 'needles', 'branches', 'debris', 'fallen', 'wood', 'tree', 'trees'
    'mountain', 'steppe', 'steppes', 'ruderal', 'orchard', 'orchards', 'plantations', 'shelterbelts'
    'grass', 'grassy', 'glades', 'sites', 'treated', 'virgin', 'rarely', 'acid', 'petioles'
    'rhizomes', 'plant', 'plants', 'eryngium', 'frangula', 'vaccinium', 'prunus', 'apricot'
    'armeniaca', 'sleepers', 'railway', 'clusters', 'large', 'with', 'of', 'on', 'and', 'in', 'for', 'from'
)

$unknownColor = @{}
$unknownHabitat = @{}
$unknownMyco = @{}
$ringStat = @{}
$volvaStat = @{}
$noLatin = @()
$bazaByLatin = @{}

foreach ($e in $baza) {
    # --- латина з промпту ---
    $en = ''
    if ($e.ai_prompts) { $en = [string]$e.ai_prompts.en }
    $m = [regex]::Match($en, ' of ([A-Z][a-z]+\s+[a-z][a-z\.\-]*)')
    if (-not $m.Success -and $e.ai_prompts) {
        $m = [regex]::Match([string]$e.ai_prompts.uk, '\(([A-Z][a-z]+\s+[a-z][a-z\.\-]*)\)')
    }
    if (-not $m.Success) { $noLatin += [string]$e.id; continue }
    $latin = $m.Groups[1].Value
    if ($bazaByLatin.ContainsKey($latin)) { continue }

    $color = @(); $stem = @(); $tree = @(); $months = @()

    # --- колір шапки та середовище з ai_tags ---
    foreach ($t in $e.ai_tags) {
        $ts = [string]$t
        if ($ts.StartsWith('cap_color:')) {
            foreach ($tok in ($ts.Substring(10) -split '[_\-\s]+')) {
                if ($tok -eq '') { continue }
                if ($colorTok.ContainsKey($tok)) { $color += $colorTok[$tok] }
                else { $unknownColor[$tok] = 1 }
            }
        }
        if ($ts.StartsWith('habitat:')) {
            foreach ($tok in ($ts.Substring(8) -split '[_\-\s]+')) {
                if ($tok -eq '') { continue }
                if ($treeTok.ContainsKey($tok)) { $tree += $treeTok[$tok] }
                elseif ($tok -notin $notTree) { $unknownHabitat[$tok] = 1 }
            }
        }
    }
    # --- кільце / піхва ---
    $ringVal = ''; $volvaVal = ''
    if ($e.morphology -and $e.morphology.stem) {
        $ringVal = ([string]$e.morphology.stem.ring).ToLower()
        $volvaVal = ([string]$e.morphology.stem.volva).ToLower()
    }
    $ringStat[$ringVal] = 1 + $ringStat[$ringVal]
    $volvaStat[$volvaVal] = 1 + $volvaStat[$volvaVal]
    if ($ringVal -in @('absent', 'none', 'null', 'no', 'missing')) { $stem += 'no_ring' }
    elseif ($ringVal -ne '') { $stem += 'ring' }
    if ($volvaVal -ne '' -and $volvaVal -notin @('absent', 'none', 'null', 'no')) { $stem += 'volva' }
    # --- мікориза / дерево ---
    if ($e.distribution) {
        foreach ($t in @($e.distribution.mycorrhiza_partner)) {
            foreach ($tok in ([string]$t -split '[_\-\s,()]+')) {
                if ($tok -eq '') { continue }
                $tl = $tok.ToLower()
                if ($mycoTok.ContainsKey($tl)) { $tree += ($mycoTok[$tl] -split ',') }
                elseif ($tl -notin $notTree -and $tl -match '^[a-z]+$' -and $tl -notin @('sp', 'spp', 'species')) { $unknownMyco[$tl] = 1 }
            }
        }
        foreach ($t in @($e.distribution.habitat)) {
            foreach ($tok in ([string]$t -split '[_\-\s,()]+')) {
                if ($tok -eq '') { continue }
                $tl = $tok.ToLower()
                if ($treeTok.ContainsKey($tl)) { $tree += $treeTok[$tl] }
                elseif ($tl -notin $notTree) { $unknownMyco[$tl] = 1 }
            }
        }
    }
    # --- сезон ---
    foreach ($mn in @($e.season)) {
        $ml = ([string]$mn).ToLower()
        if ($monthEn.ContainsKey($ml)) { $months += $monthEn[$ml] }
    }

    $bazaByLatin[$latin] = @{
        color  = @($color | Sort-Object -Unique)
        stem   = @($stem | Sort-Object -Unique)
        tree   = @($tree | Sort-Object -Unique)
        months = @($months | Sort-Object -Unique)
    }
}
Log ('[3] zistavleno latyn: ' + $bazaByLatin.Count + ', bez latyny: ' + $noLatin.Count)
if ($noLatin.Count) { Log ('[3] id bez latyny: ' + ($noLatin -join ',')) }
Log ('[3] ring: ' + (($ringStat.GetEnumerator() | ForEach-Object { $_.Key + '=' + $_.Value }) -join ', '))
Log ('[3] volva: ' + (($volvaStat.GetEnumerator() | ForEach-Object { $_.Key + '=' + $_.Value }) -join ', '))
if ($unknownColor.Count) { Log ('[3] nevidomi tokeny koloru: ' + (($unknownColor.Keys | Sort-Object) -join ', ')) }
if ($unknownHabitat.Count) { Log ('[3] nevidomi tokeny habitat(tag): ' + (($unknownHabitat.Keys | Sort-Object) -join ', ')) }
if ($unknownMyco.Count) { Log ('[3] nevidomi tokeny myco/habitat: ' + (($unknownMyco.Keys | Sort-Object) -join ', ')) }

# ============================================================
# [4] таблиця грибів.txt — дерево і сезон (лише частина 1 має латину)
# ============================================================
Log '[4] chytaiu tablytsiu hrybiv ...'
$tbPath = Join-Path $Project 'таблиця грибів.txt'
$tbLines = [IO.File]::ReadAllLines($tbPath)
$tableByLatin = @{}
$tbRows = 0; $tbBadCols = 0; $tbGenus = 0; $tbSeasonHit = 0
foreach ($l in $tbLines) {
    if ($l -notmatch '^\d+\t') { continue }
    $c = $l -split "`t"
    if ($c.Count -lt 17) { continue }   # частини 2–10 — правила/без латини, пропускаємо
    $tbRows++
    if ($c.Count -ne 21) { $tbBadCols++ }
    $latin = $c[2].Trim()
    if ($latin -notmatch '^[A-Z][a-z]+\s+[a-z]') { $tbGenus++; continue }

    $tree = @(); $months = @()
    foreach ($field in @($c[11], $c[12])) {
        foreach ($tok in ([string]$field -split '[\s,;]+')) {
            if ($tok -eq '') { continue }
            $tl = $tok.ToLower()
            if ($treeTok.ContainsKey($tl)) { $tree += $treeTok[$tl] }
            elseif ($tl -notmatch '^\d' -and $tl -notin $notTree) { $unknownMyco[$tl] = 1 }
        }
    }
    # діапазон сезону: 'MM-DD – MM-DD' (розділювач може бути -, – або —)
    $mm = [regex]::Match($l, '\b(\d{2})-(\d{2})\s*[\-–—]\s*(\d{2})-(\d{2})\b')
    if ($mm.Success) {
        $tbSeasonHit++
        $startM = [int]$mm.Groups[1].Value
        $endM = [int]$mm.Groups[3].Value
        $cur = $startM
        for ($k = 0; $k -lt 12; $k++) {
            $months += $cur
            if ($cur -eq $endM) { break }
            $cur = ($cur % 12) + 1
        }
    }
    $months = @($months | Sort-Object -Unique)

    if ($tableByLatin.ContainsKey($latin)) {
        $prev = $tableByLatin[$latin]
        $tableByLatin[$latin] = @{
            tree   = @(($prev.tree + $tree) | Sort-Object -Unique)
            months = @(($prev.months + $months) | Sort-Object -Unique)
        }
    } else {
        $tableByLatin[$latin] = @{ tree = @($tree | Sort-Object -Unique); months = $months }
    }
}
Log ('[4] riadkiv tabeli: ' + $tbRows + ' (genus: ' + $tbGenus + ', ne 21 kolonka: ' + $tbBadCols + ', sezoni znaideno: ' + $tbSeasonHit + ')')
Log ('[4] unikalnyh latyn u tabeli: ' + $tableByLatin.Count)
$tbSeasonEmpty = @($tableByLatin.Keys | Where-Object { -not $tableByLatin[$_].months }).Count
if ($tbSeasonEmpty) { Log ('[4] latyn bez sezonu: ' + $tbSeasonEmpty) }

# ============================================================
# [5] збирання каталогу
# ============================================================
Log '[5> zbiraiu katalog ...'
$ukMonthRange = '([А-Яа-яіїєґ]+)\s*[-–—]\s*([А-Яа-яіїєґ]+)'
$edLabel = @{
    'edible'               = @('Їстівний', 'Їстівна')
    'conditionally_edible' = @('Умовно їстівний', 'Умовно їстівна')
    'inedible'             = @('Неїстівний', 'Неїстівна')
    'poisonous'            = @('Отруйний', 'Отруйна')
    'deadly_poisonous'     = @('Смертельно отруйний', 'Смертельно отруйна')
    'controversial'        = @('Дискусійний', 'Дискусійна')
}
$monthGroups = @{ spring = @(3, 4, 5); summer = @(6, 7, 8); autumn = @(9, 10, 11); winter = @(12, 1, 2) }

$cntColor = @{}; $cntStem = @{}; $cntTree = @{}; $cntSeason = @{}
$cover = @{ color = 0; stem = 0; tree = 0; season = 0 }
$photoFound = 0
$speciesOut = @()
$masterLatin = @{}
foreach ($mrow in $merged) { $masterLatin[$mrow.scientific_name] = $true }

foreach ($row in $merged) {
    $latin = $row.scientific_name
    $name = $row.common_name_uk

    # --- джерела атрибутів ---
    $color = @(); $stem = @(); $tree = @(); $months = @()
    if ($bazaByLatin.ContainsKey($latin)) {
        $b = $bazaByLatin[$latin]
        $color += $b.color; $stem += $b.stem; $tree += $b.tree; $months += $b.months
    }
    if ($tableByLatin.ContainsKey($latin)) {
        $t = $tableByLatin[$latin]
        $tree += $t.tree; $months += $t.months
    }
    # fallback: текстовий сезон із master.csv (напр. "Травень - Жовтень.")
    if (-not $months -and $row.season) {
        $mm = [regex]::Match([string]$row.season, $ukMonthRange)
        if ($mm.Success) {
            $a = $mm.Groups[1].Value.ToLower(); $b2 = $mm.Groups[2].Value.ToLower()
            if ($monthUk.ContainsKey($a) -and $monthUk.ContainsKey($b2)) {
                $cur = $monthUk[$a]; $endM = $monthUk[$b2]
                for ($k = 0; $k -lt 12; $k++) {
                    $months += $cur
                    if ($cur -eq $endM) { break }
                    $cur = ($cur % 12) + 1
                }
            }
        } else {
            foreach ($tk in ([string]$row.season -split '[^\wа-яіїєґ]+')) {
                $tl = $tk.ToLower()
                if ($monthUk.ContainsKey($tl)) { $months += $monthUk[$tl] }
            }
        }
    }

    $color = @($color | Sort-Object -Unique)
    $stem = @($stem | Sort-Object -Unique)
    $tree = @($tree | Sort-Object -Unique)
    $months = @($months | Sort-Object -Unique)

    $seasonFacets = @()
    foreach ($g in $monthGroups.Keys) {
        foreach ($mn in $monthGroups[$g]) { if ($months -contains $mn) { $seasonFacets += $g; break } }
    }
    $seasonFacets = @($seasonFacets | Sort-Object)

    # --- фото (раніше за фасети: у довіднику рахуються лише види з фото) ---
    $photo = ''
    if ($photoByTarget.ContainsKey($latin)) { $photo = $photoByTarget[$latin]; $photoFound++ }
    $hasPhoto = $photo -ne ''

    if ($hasPhoto) {
        foreach ($v in $color) { $cntColor[$v] = 1 + $cntColor[$v] }
        foreach ($v in $stem) { $cntStem[$v] = 1 + $cntStem[$v] }
        foreach ($v in $tree) { $cntTree[$v] = 1 + $cntTree[$v] }
        foreach ($v in $seasonFacets) { $cntSeason[$v] = 1 + $cntSeason[$v] }
        if ($color.Count) { $cover.color++ }
        if ($stem.Count) { $cover.stem++ }
        if ($tree.Count) { $cover.tree++ }
        if ($seasonFacets.Count) { $cover.season++ }
    }

    # --- їстівність (з урахуванням роду назви) ---
    $status = [string]$row.edibility_status
    $fem = $name -match '(а|я)$'
    $label = $status
    if ($edLabel.ContainsKey($status)) {
        $forms = $edLabel[$status]
        if ($fem) { $label = $forms[1] } else { $label = $forms[0] }
    }

    $slug = $latin.ToLower()
    $slug = ($slug -replace '\s+', '-')
    $slug = ($slug -replace '[^\w\-]', '')

    $speciesOut += [ordered]@{
        id              = $slug
        name            = $name
        latin           = $latin
        edibility       = $status
        edibility_label = $label
        red_listed      = ($row.is_red_listed -eq '1')
        rarity          = [string]$row.rarity_label_uk
        has_photo       = $hasPhoto
        photo           = $photo
        top20           = ($row.in_top20 -eq '1')
        popular         = ($row.is_popular -eq '1')
        ai_recognition  = ($row.in_ai_recognition -eq '1')
        features        = [string]$row.key_features_ai
        months          = $months
        attrs           = [ordered]@{
            color  = $color
            stem   = $stem
            tree   = $tree
            season = $seasonFacets
        }
    }
}
Log ('[5] vydiv: ' + $speciesOut.Count + ', z foto: ' + $photoFound)
Log ('[5] pokryttya atributiv — kolir: ' + $cover.color + ', nizhka: ' + $cover.stem +
     ', derevo: ' + $cover.tree + ', sezon: ' + $cover.season)
$bazaMiss = @($bazaByLatin.Keys | Where-Object { -not $masterLatin.ContainsKey($_) })
if ($bazaMiss.Count) { Log ('[5] baza-latyny poza master.csv: ' + ($bazaMiss -join ', ')) }
$tbMiss = @($tableByLatin.Keys | Where-Object { -not $masterLatin.ContainsKey($_) })
if ($tbMiss.Count) { Log ('[5] tabela-latyny poza master.csv: ' + ($tbMiss -join ', ')) }

# ============================================================
# [6] фасети
# ============================================================
Log '[6] buduiu fasety ...'
function New-Facet([hashtable]$counts, $labels, [string[]]$order) {
    $items = @()
    foreach ($k in $counts.Keys) {
        $lbl = $k
        if ($labels.Contains($k)) { $lbl = $labels[$k] }
        $items += [ordered]@{ value = $k; label = $lbl; count = $counts[$k] }
    }
    if ($order -and $order.Count) {
        return @($items | Sort-Object { [array]::IndexOf($order, $_.value) }, { -$_.count })
    }
    return @($items | Sort-Object { -$_.count }, { $_.label })
}

$colorLabels = [ordered]@{
    white = 'Білий'; grey = 'Сірий'; brown = 'Коричневий'; yellow = 'Жовтий'; ochre = 'Охра'
    orange = 'Оранжевий'; red = 'Червоний'; pink = 'Рожевий'; purple = 'Фіолетовий'
    blue = 'Синій'; green = 'Зелений'; olive = 'Оливковий'; black = 'Чорний'
    russet = 'Рудий'; beige = 'Бежевий'
}
$stemLabels = [ordered]@{ ring = 'З кільцем'; no_ring = 'Без кільця'; volva = 'З піхвою' }
$stemOrder = @('ring', 'no_ring', 'volva')
$treeLabels = [ordered]@{
    pine = 'Сосна'; spruce = 'Ялина'; larch = 'Модрина'; oak = 'Дуб'; birch = 'Береза'
    aspen = 'Осика'; poplar = 'Тополя'; willow = 'Верба'; alder = 'Вільха'; hornbeam = 'Граб'
    beech = 'Бук'; lime = 'Липа'; maple = 'Клен'; elm = "В'яз"; ash = 'Ясен'
    hazel = 'Ліщина'; chestnut = 'Каштан'
    mixed = 'Мішаний ліс'; deciduous = 'Листяний ліс'; coniferous = 'Хвойний ліс'; any = 'Будь-який ліс'
}
$treeOrder = @('pine', 'spruce', 'larch', 'oak', 'birch', 'aspen', 'poplar', 'willow', 'alder',
    'hornbeam', 'beech', 'lime', 'maple', 'elm', 'ash', 'hazel', 'chestnut',
    'mixed', 'deciduous', 'coniferous', 'any')
$seasonLabels = [ordered]@{ spring = 'Весна'; summer = 'Літо'; autumn = 'Осінь'; winter = 'Зима' }
$seasonOrder = @('spring', 'summer', 'autumn', 'winter')

$facets = [ordered]@{
    color  = New-Facet $cntColor $colorLabels @()
    stem   = New-Facet $cntStem $stemLabels $stemOrder
    tree   = New-Facet $cntTree $treeLabels $treeOrder
    season = New-Facet $cntSeason $seasonLabels $seasonOrder
}
foreach ($f in @('color', 'stem', 'tree', 'season')) {
    Log ('[6] faseta ' + $f + ': ' + (($facets[$f] | ForEach-Object { $_.label + '=' + $_.count }) -join ', '))
}

# ============================================================
# [7] JSON + вставка в HTML
# ============================================================
Log '[7] serializuiu JSON ...'
$catalog = [ordered]@{
    meta = [ordered]@{
        generated   = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
        rows_total  = $master.Count
        total       = $speciesOut.Count
        with_photos = $photoFound
        cover       = $cover
        sources     = @('master.csv', $bazaFile.Name, 'таблиця грибів.txt', 'фото webp-папки')
    }
    facets  = $facets
    species = $speciesOut
}
$json = $catalog | ConvertTo-Json -Depth 8

# розкодовуємо \uXXXX для не-ASCII (читабельність файлу)
$uniq = [regex]::Matches($json, '\\u([0-9a-fA-F]{4})') | ForEach-Object { $_.Value } | Sort-Object -Unique
foreach ($esc in $uniq) {
    $code = [Convert]::ToInt32($esc.Substring(2), 16)
    if ($code -ge 128) { $json = $json.Replace($esc, [string][char]$code) }
}
$jsonPath = Join-Path $Root 'mushroom_catalog.json'
[IO.File]::WriteAllText($jsonPath, $json, (New-Object System.Text.UTF8Encoding($false)))
Log ('[7] zapysano ' + $jsonPath + ' (' + [math]::Round($json.Length / 1024, 1) + ' KB)')

# вставка в HTML: маркери CATALOG:START/END, '<' тікає як \u003c
$Html = Join-Path $Root 'mushroom-radar.html'
$htmlText = [IO.File]::ReadAllText($Html)
$startTok = '<!-- CATALOG:START -->'
$endTok = '<!-- CATALOG:END -->'
$i = $htmlText.IndexOf($startTok)
$j = $htmlText.IndexOf($endTok)
if ($i -lt 0 -or $j -lt $i) { throw 'Markery CATALOG:START/END ne znaineo v mushroom-radar.html' }
$jsonHtml = $json -replace '<', '\u003c'
$block = $startTok + "`n<script type=`"application/json`" id=`"mushroom-catalog`">" + $jsonHtml + "</script>`n" + $endTok
$newHtml = $htmlText.Substring(0, $i) + $block + $htmlText.Substring($j + $endTok.Length)
[IO.File]::WriteAllText($Html, $newHtml, (New-Object System.Text.UTF8Encoding($false)))
Log '[7] katalog vbudivano v mushroom-radar.html'

# перевірка: JSON парситься
$check = [IO.File]::ReadAllText($jsonPath) | ConvertFrom-Json
Log ('[7] perevirka JSON: species=' + $check.species.Count + ', facets=' +
     ($check.facets.PSObject.Properties.Name -join '/'))
Log 'DONE'
