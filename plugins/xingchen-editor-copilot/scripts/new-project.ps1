[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RootPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ProjectName,

    [string]$ClientName = "",

    [ValidateSet("commercial-promo", "event-highlight", "store-promo", "other")]
    [string]$ProjectType = "commercial-promo",

    [ValidateSet("16:9", "9:16", "1:1", "4:5")]
    [string]$AspectRatio = "16:9",

    [ValidateRange(1, 3600)]
    [int]$TargetDurationSeconds = 30,

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

foreach ($invalidChar in [System.IO.Path]::GetInvalidFileNameChars()) {
    if ($ProjectName.Contains([string]$invalidChar)) {
        throw "ProjectName contains an invalid file-name character: $invalidChar"
    }
}

$resolvedRoot = [System.IO.Path]::GetFullPath($RootPath)
$projectPath = Join-Path -Path $resolvedRoot -ChildPath $ProjectName

if ((Test-Path -LiteralPath $projectPath) -and -not $Force) {
    throw "Project directory already exists. Review it first or rerun with -Force: $projectPath"
}

New-Item -ItemType Directory -Path $projectPath -Force | Out-Null

$folders = @(
    "00_Brief",
    "01_SourceMedia",
    "02_AudioMusic",
    "03_NLEProject",
    "04_Proxies",
    "05_AIReports",
    "06_ReviewExports",
    "07_Deliverables",
    "99_Cache"
)

foreach ($folder in $folders) {
    New-Item -ItemType Directory -Path (Join-Path $projectPath $folder) -Force | Out-Null
}

$profile = [ordered]@{
    schemaVersion = 1
    projectName = $ProjectName
    clientName = $ClientName
    projectType = $ProjectType
    targetDurationSeconds = $TargetDurationSeconds
    aspectRatio = $AspectRatio
    status = "created"
    createdAt = (Get-Date).ToString("o")
    sourceMediaPath = "01_SourceMedia"
    nleProjectPath = "03_NLEProject"
    aiOutputPath = "05_AIReports"
    deliveryPath = "07_Deliverables"
}

$profilePath = Join-Path $projectPath "00_Brief\project-profile.json"
$profile | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $profilePath -Encoding UTF8

[ordered]@{
    projectPath = $projectPath
    profilePath = $profilePath
    sourceMediaPath = (Join-Path $projectPath "01_SourceMedia")
    folderCount = $folders.Count
} | ConvertTo-Json -Depth 3
