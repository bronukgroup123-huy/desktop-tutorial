# move_catalog_block.ps1 - move the CATALOG marker block from inside the main
# <script> (wrong place) to just BEFORE the main <script> tag.
# ASCII-only script; the HTML path arrives as a parameter (contains Cyrillic).
param([Parameter(Mandatory = $true)][string]$Path)
$ErrorActionPreference = 'Stop'
$enc = New-Object System.Text.UTF8Encoding($false)
$t = [IO.File]::ReadAllText($Path, $enc)
$startTok = '<!-- CATALOG:START -->'
$endTok = '<!-- CATALOG:END -->'
$i = $t.IndexOf($startTok)
$j = $t.IndexOf($endTok)
if ($i -lt 0 -or $j -lt $i) { throw 'markers not found' }
$block = $t.Substring($i, ($j + $endTok.Length) - $i)
$rest = $t.Substring(0, $i) + $t.Substring($j + $endTok.Length)
$cm = $rest.IndexOf('// ---------- Tab switching ----------')
if ($cm -lt 0) { throw 'tab switching comment not found' }
$si = $rest.LastIndexOf('<script>', $cm)
if ($si -lt 0) { throw 'main script open not found' }
$le = "`r`n"
if (-not $rest.Contains("`r`n")) { $le = "`n" }
$new = $rest.Substring(0, $si) + $block + $le + $rest.Substring($si)
[IO.File]::WriteAllText($Path, $new, $enc)
Write-Output ('moved: block=' + $block.Length + ' at pos ' + $si + '; html=' + $new.Length)
