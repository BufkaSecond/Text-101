<#
.SYNOPSIS
    Generates State .asset files (rooms) from a draw.io storyboard.

.DESCRIPTION
    Reads a draw.io XML export where:
      - every room is a vertex whose value starts with <h1>ID. Title</h1>
      - every edge is labelled with the button number (1, 2, 3)
      - rooms with no outgoing edges (endings / game over) loop back to the start room
    Writes one .asset + .meta per room into Assets/States/<Section>/.

    GUIDs are derived from the room ID, so re-running the script overwrites the
    same assets and keeps every reference (scene, other rooms) intact.
    The start room reuses the GUID of Assets/States/StartingState.asset so the
    AdventureGame component in the scene stays wired.

.EXAMPLE
    ./Tools/Generate-Rooms.ps1 -Diagram "C:\path\Cyberpunk_Game_Diagram_100.xml"
#>
param(
    [Parameter(Mandatory = $true)] [string] $Diagram,
    [string] $ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string] $StartRoom = "P1",
    [switch] $DryRun
)

$ErrorActionPreference = "Stop"

# GUID of State.cs (Assets/Scripts/State.cs.meta)
$StateScriptGuid = "3d942913cfea0194881cc2c7f239e0ff"
# GUID the scene's AdventureGame.startingState already points at
$StartingStateGuid = "33d341c14f24c6c40af9c4b7471f3405"

# Room ID prefix -> folder under Assets/States
$Sections = [ordered]@{
    "P" = "0 Prologue"
    "W" = "1 Watson"
    "V" = "2A Pacifica"
    "R" = "2B Arasaka"
    "N" = "2C Badlands"
    "F" = "3 Blackwall"
    "S" = "Endings"
    "X" = "GameOver"
}

$StatesDir = Join-Path $ProjectRoot "Assets/States"
$Utf8 = New-Object System.Text.UTF8Encoding($false)

function Get-Guid([string] $seed) {
    if ($seed -eq "room:$StartRoom") { return $StartingStateGuid }
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $bytes = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("cyberpunk-text-adventure/$seed"))
    return -join ($bytes | ForEach-Object { $_.ToString("x2") })
}

function Convert-HtmlToText([string] $html) {
    $t = $html
    # "<h1>P1. Just Another Night</h1>" -> "Just Another Night" (room ID is for the diagram only)
    $t = $t -replace '(?i)<h1>\s*[A-Z]+\d+\.\s*(.*?)</h1>', ('$1' + "`n`n")
    $t = $t -replace '(?i)<br\s*/?>', "`n"
    $t = $t -replace '(?i)</p>\s*', "`n`n"
    $t = $t -replace '<[^>]+>', ''
    $t = [System.Net.WebUtility]::HtmlDecode($t)
    $t = $t -replace "`r", ''
    $t = $t.Replace([string][char]0xA0, ' ')
    return $t.Trim()
}

function ConvertTo-YamlString([string] $s) {
    $s = $s.Replace('\', '\\').Replace('"', '\"').Replace("`n", '\n').Replace("`t", '\t')
    return '"' + $s + '"'
}

function Write-File([string] $path, [string] $content) {
    if ($DryRun) { Write-Host "[dry-run] $path"; return }
    $dir = Split-Path -Parent $path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    [System.IO.File]::WriteAllText($path, $content.Replace("`r`n", "`n"), $Utf8)
}

# ---------- parse ----------
[xml] $xml = [System.IO.File]::ReadAllText((Resolve-Path $Diagram), [System.Text.Encoding]::UTF8)
$cells = $xml.SelectNodes("//mxCell")

$rooms = [ordered]@{}
foreach ($c in $cells) {
    if ($c.vertex -ne "1" -or $c.value -notmatch '^\s*<h1>') { continue }
    $rooms[$c.id] = [pscustomobject]@{
        Id    = $c.id
        Text  = Convert-HtmlToText $c.value
        Exits = @{}
    }
}

$problems = New-Object System.Collections.Generic.List[string]
foreach ($c in $cells) {
    if ($c.edge -ne "1") { continue }
    $src = $c.source; $dst = $c.target; $label = "$($c.value)".Trim()
    if (-not $rooms.Contains($src) -or -not $rooms.Contains($dst)) {
        $problems.Add("Edge $($c.id): unknown room ($src -> $dst)"); continue
    }
    if ($label -notmatch '^\d+$') { $problems.Add("Edge $($c.id) ($src -> $dst): label '$label' is not a number"); continue }
    $n = [int] $label
    if ($rooms[$src].Exits.ContainsKey($n)) { $problems.Add("$src has two edges labelled $n"); continue }
    $rooms[$src].Exits[$n] = $dst
}

if (-not $rooms.Contains($StartRoom)) { throw "Start room '$StartRoom' not found in diagram." }

# ---------- validate ----------
foreach ($r in $rooms.Values) {
    $choicesInText = ([regex]::Matches($r.Text, '(?m)^\s*(\d+)\.\s')).Count
    if ($r.Exits.Count -eq 0) {
        $r.Exits[1] = $StartRoom   # ending / game over -> restart
    } else {
        $keys = @($r.Exits.Keys | Sort-Object)
        for ($i = 0; $i -lt $keys.Count; $i++) {
            if ($keys[$i] -ne $i + 1) { $problems.Add("$($r.Id): buttons are $($keys -join ',') (gap)"); break }
        }
    }
    if ($choicesInText -ne $r.Exits.Count) {
        $problems.Add("$($r.Id): text lists $choicesInText choices, diagram has $($r.Exits.Count) exits")
    }
}

$reachable = @{}; $queue = New-Object System.Collections.Generic.Queue[string]
$queue.Enqueue($StartRoom)
while ($queue.Count) {
    $id = $queue.Dequeue(); if ($reachable[$id]) { continue }; $reachable[$id] = $true
    foreach ($t in $rooms[$id].Exits.Values) { $queue.Enqueue($t) }
}
foreach ($id in $rooms.Keys) { if (-not $reachable[$id]) { $problems.Add("$id is unreachable from $StartRoom") } }

# ---------- write ----------
function Get-Folder([string] $id) {
    $prefix = ($id -replace '\d+$', '')
    if ($Sections.Contains($prefix)) { return $Sections[$prefix] }
    return "Other"
}

$folders = @{}
foreach ($r in $rooms.Values) {
    $folder = Get-Folder $r.Id
    $folders[$folder] = $true
    $assetPath = Join-Path $StatesDir "$folder/$($r.Id).asset"

    $next = ($r.Exits.Keys | Sort-Object | ForEach-Object {
        "  - {fileID: 11400000, guid: $(Get-Guid "room:$($r.Exits[$_])"), type: 2}"
    }) -join "`n"

    $asset = @"
%YAML 1.1
%TAG !u! tag:unity3d.com,2011:
--- !u!114 &11400000
MonoBehaviour:
  m_ObjectHideFlags: 0
  m_CorrespondingSourceObject: {fileID: 0}
  m_PrefabInstance: {fileID: 0}
  m_PrefabAsset: {fileID: 0}
  m_GameObject: {fileID: 0}
  m_Enabled: 1
  m_EditorHideFlags: 0
  m_Script: {fileID: 11500000, guid: $StateScriptGuid, type: 3}
  m_Name: $($r.Id)
  m_EditorClassIdentifier: Assembly-CSharp::State
  storyText: $(ConvertTo-YamlString $r.Text)
  nextStates:
$next

"@
    $meta = @"
fileFormatVersion: 2
guid: $(Get-Guid "room:$($r.Id)")
NativeFormatImporter:
  externalObjects: {}
  mainObjectFileID: 11400000
  userData:
  assetBundleName:
  assetBundleVariant:

"@
    Write-File $assetPath $asset
    Write-File "$assetPath.meta" $meta
}

foreach ($folder in $folders.Keys) {
    $metaPath = Join-Path $StatesDir "$folder.meta"
    if (Test-Path $metaPath) { continue }
    Write-File $metaPath @"
fileFormatVersion: 2
guid: $(Get-Guid "folder:$folder")
folderAsset: yes
DefaultImporter:
  externalObjects: {}
  userData:
  assetBundleName:
  assetBundleVariant:

"@
}

# The start room now owns StartingState's GUID; remove the old file so Unity sees no duplicate.
$oldStart = Join-Path $StatesDir "StartingState.asset"
if ((Test-Path $oldStart) -and -not $DryRun) {
    Remove-Item $oldStart, "$oldStart.meta" -Force
    Write-Host "Removed StartingState.asset ($StartRoom took over its GUID)."
}

Write-Host "Rooms written: $($rooms.Count) into $($folders.Count) folders under $StatesDir"
if ($problems.Count) {
    Write-Warning "$($problems.Count) storyboard issue(s):"
    $problems | ForEach-Object { Write-Warning "  $_" }
} else {
    Write-Host "Storyboard checks passed: every room reachable, choices match exits."
}
