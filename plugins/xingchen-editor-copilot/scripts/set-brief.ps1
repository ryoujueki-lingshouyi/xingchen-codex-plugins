[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,

    [Parameter(Mandatory = $true)]
    [string]$BriefJson,

    [switch]$Confirmed
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$resolvedProject = [System.IO.Path]::GetFullPath($ProjectPath)
$systemPath = Join-Path $resolvedProject ".xingchen"
$projectConfigPath = Join-Path $systemPath "project.json"
$briefPath = Join-Path $systemPath "brief.json"

if (-not (Test-Path -LiteralPath $projectConfigPath -PathType Leaf)) {
    throw "Not a Xingchen project: $resolvedProject"
}

try {
    $briefObject = $BriefJson | ConvertFrom-Json
} catch {
    throw "BriefJson is not valid JSON: $($_.Exception.Message)"
}

if ($null -eq $briefObject -or $briefObject -is [System.Array]) {
    throw "BriefJson must contain one JSON object."
}

$preview = [ordered]@{
    success = $true
    writeRequired = (-not $Confirmed)
    projectPath = $resolvedProject
    briefPath = $briefPath
    brief = $briefObject
}

if (-not $Confirmed) {
    $preview | ConvertTo-Json -Depth 10
    return
}

$logsPath = Join-Path $systemPath "logs"
if (-not (Test-Path -LiteralPath $logsPath)) {
    New-Item -ItemType Directory -Path $logsPath | Out-Null
}

if (Test-Path -LiteralPath $briefPath -PathType Leaf) {
    $backupName = "brief-{0}.json" -f (Get-Date -Format "yyyyMMdd-HHmmss")
    Copy-Item -LiteralPath $briefPath -Destination (Join-Path $logsPath $backupName)
}

$briefObject | Add-Member -NotePropertyName schemaVersion -NotePropertyValue 1 -Force
$briefObject | Add-Member -NotePropertyName confirmed -NotePropertyValue $true -Force
$briefObject | Add-Member -NotePropertyName confirmedAt -NotePropertyValue (Get-Date).ToString("o") -Force
$briefObject | Add-Member -NotePropertyName updatedAt -NotePropertyValue (Get-Date).ToString("o") -Force
$briefObject | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $briefPath -Encoding UTF8

$preview.writeRequired = $false
$preview.brief = $briefObject
$preview | ConvertTo-Json -Depth 10
