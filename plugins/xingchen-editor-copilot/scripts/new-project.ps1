[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RootPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ProjectName,

    [string]$ClientName = "",

    [switch]$Repair
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

foreach ($invalidChar in [System.IO.Path]::GetInvalidFileNameChars()) {
    if ($ProjectName.Contains([string]$invalidChar)) {
        throw "ProjectName contains an invalid file-name character: $invalidChar"
    }
}

$cleanProjectName = $ProjectName.Trim()
if ([string]::IsNullOrWhiteSpace($cleanProjectName)) {
    throw "ProjectName cannot be empty."
}

$resolvedRoot = [System.IO.Path]::GetFullPath($RootPath)
if (-not (Test-Path -LiteralPath $resolvedRoot)) {
    New-Item -ItemType Directory -Path $resolvedRoot | Out-Null
}

$projectPath = Join-Path -Path $resolvedRoot -ChildPath $cleanProjectName
$projectAlreadyExists = Test-Path -LiteralPath $projectPath
if ($projectAlreadyExists -and -not $Repair) {
    throw "Project directory already exists. Run project validation before using -Repair: $projectPath"
}

if (-not $projectAlreadyExists) {
    New-Item -ItemType Directory -Path $projectPath | Out-Null
}

$visibleFolders = @("01_原始素材", "02_素材筛选结果")
$systemFolders = @(".xingchen", ".xingchen\imports", ".xingchen\logs", ".xingchen\thumbnails", ".xingchen\transcripts")
$createdFolders = New-Object System.Collections.Generic.List[string]

foreach ($relativePath in @($visibleFolders + $systemFolders)) {
    $fullPath = Join-Path $projectPath $relativePath
    if (-not (Test-Path -LiteralPath $fullPath)) {
        New-Item -ItemType Directory -Path $fullPath | Out-Null
        $createdFolders.Add($relativePath)
    }
}

$systemPath = Join-Path $projectPath ".xingchen"
try {
    $systemItem = Get-Item -LiteralPath $systemPath
    $systemItem.Attributes = $systemItem.Attributes -bor [System.IO.FileAttributes]::Hidden
} catch {
    # A leading dot already keeps this folder out of the normal workflow.
}

$projectConfigPath = Join-Path $systemPath "project.json"
if (-not (Test-Path -LiteralPath $projectConfigPath)) {
    $projectConfig = [ordered]@{
        schemaVersion = 1
        pluginVersion = "1.0.0"
        projectName = $cleanProjectName
        clientName = $ClientName
        status = "created"
        createdAt = (Get-Date).ToString("o")
        updatedAt = (Get-Date).ToString("o")
        sourceMediaPath = "01_原始素材"
        screeningOutputPath = "02_素材筛选结果"
        systemPath = ".xingchen"
    }
    $projectConfig | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $projectConfigPath -Encoding UTF8
}

$briefPath = Join-Path $systemPath "brief.json"
if (-not (Test-Path -LiteralPath $briefPath)) {
    [ordered]@{
        schemaVersion = 1
        confirmed = $false
        clientName = $ClientName
        projectType = ""
        purpose = ""
        targetDuration = ""
        aspectRatio = ""
        keyPeople = @()
        requiredContent = @()
        requiredSpeech = @()
        excludedContent = @()
        styleKeywords = @()
        deliveryDate = ""
        referenceNotes = ""
        updatedAt = (Get-Date).ToString("o")
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $briefPath -Encoding UTF8
}

[ordered]@{
    success = $true
    mode = if ($projectAlreadyExists) { "repair" } else { "create" }
    projectPath = $projectPath
    sourceMediaPath = (Join-Path $projectPath "01_原始素材")
    screeningOutputPath = (Join-Path $projectPath "02_素材筛选结果")
    createdFolders = @($createdFolders | ForEach-Object { $_ })
    projectConfigPath = $projectConfigPath
    briefPath = $briefPath
} | ConvertTo-Json -Depth 6
