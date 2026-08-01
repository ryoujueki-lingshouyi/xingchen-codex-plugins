[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-StableId {
    param([string]$Value)
    $sha = [System.Security.Cryptography.SHA1]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value.ToLowerInvariant())
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Convert-FrameRate {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -eq "0/0") { return $null }
    if ($Value -match '^([0-9.]+)/([0-9.]+)$') {
        $denominator = [double]$Matches[2]
        if ($denominator -eq 0) { return $null }
        return [math]::Round(([double]$Matches[1] / $denominator), 3)
    }
    $parsed = 0.0
    if ([double]::TryParse($Value, [ref]$parsed)) { return $parsed }
    return $null
}

$resolvedProject = [System.IO.Path]::GetFullPath($ProjectPath)
$validationScript = Join-Path $PSScriptRoot "validate-project.ps1"
$validationJson = & $validationScript -ProjectPath $resolvedProject | Out-String
$validation = $validationJson | ConvertFrom-Json
if (-not $validation.readyForScreening) {
    [ordered]@{
        success = $false
        error = "Project is not ready for screening"
        blockers = @($validation.blockers)
        warnings = @($validation.warnings)
    } | ConvertTo-Json -Depth 8
    return
}

$sourceRoot = Join-Path $resolvedProject "01_原始素材"
$systemRoot = Join-Path $resolvedProject ".xingchen"
$resultRoot = Join-Path $resolvedProject "02_素材筛选结果"
$supportedExtensions = @(".mp4", ".mov", ".mxf", ".avi", ".mkv", ".mts", ".m2ts", ".wav", ".mp3", ".aif", ".aiff", ".jpg", ".jpeg", ".png", ".heic", ".tif", ".tiff")
$videoExtensions = @(".mp4", ".mov", ".mxf", ".avi", ".mkv", ".mts", ".m2ts")
$audioExtensions = @(".wav", ".mp3", ".aif", ".aiff")
$imageExtensions = @(".jpg", ".jpeg", ".png", ".heic", ".tif", ".tiff")
$ffprobeCommand = Get-Command ffprobe -ErrorAction SilentlyContinue

$items = New-Object System.Collections.Generic.List[object]
$errors = New-Object System.Collections.Generic.List[object]
$mediaFiles = @(Get-ChildItem -LiteralPath $sourceRoot -File -Recurse -Force | Where-Object { $supportedExtensions -contains $_.Extension.ToLowerInvariant() })

foreach ($file in $mediaFiles) {
    $relativeWithinSource = $file.FullName.Substring($sourceRoot.TrimEnd('\').Length).TrimStart('\')
    $projectRelativePath = "01_原始素材/" + $relativeWithinSource.Replace('\', '/')
    $extension = $file.Extension.ToLowerInvariant()
    $kind = if ($videoExtensions -contains $extension) { "video" } elseif ($audioExtensions -contains $extension) { "audio" } elseif ($imageExtensions -contains $extension) { "image" } else { "other" }
    $item = [pscustomobject][ordered]@{
        id = Get-StableId -Value $projectRelativePath
        sourceRelativePath = $projectRelativePath
        sourceFullPath = $file.FullName
        fileName = $file.Name
        extension = $extension
        mediaType = $kind
        sizeBytes = [int64]$file.Length
        modifiedAt = $file.LastWriteTime.ToString("o")
        readable = ($file.Length -gt 0)
        durationSeconds = $null
        width = $null
        height = $null
        frameRate = $null
        videoCodec = $null
        audioCodec = $null
        hasAudio = $false
        technicalFlags = @()
        probeError = $null
    }

    if (($kind -eq "video" -or $kind -eq "audio") -and $file.Length -gt 0) {
        if ($null -eq $ffprobeCommand) {
            $item.readable = $false
            $item.probeError = "ffprobe-not-found"
        } else {
            $probeText = & $ffprobeCommand.Source -v error -show_format -show_streams -print_format json $file.FullName 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) {
                $item.readable = $false
                $item.probeError = $probeText.Trim()
            } else {
                try {
                    $probe = $probeText | ConvertFrom-Json
                    if ($null -ne $probe.format.duration) { $item.durationSeconds = [math]::Round([double]$probe.format.duration, 3) }
                    $videoStream = @($probe.streams | Where-Object { $_.codec_type -eq "video" } | Select-Object -First 1)
                    $audioStream = @($probe.streams | Where-Object { $_.codec_type -eq "audio" } | Select-Object -First 1)
                    if ($videoStream.Count -gt 0) {
                        $item.width = $videoStream[0].width
                        $item.height = $videoStream[0].height
                        $item.frameRate = Convert-FrameRate -Value $videoStream[0].avg_frame_rate
                        $item.videoCodec = $videoStream[0].codec_name
                    }
                    if ($audioStream.Count -gt 0) {
                        $item.hasAudio = $true
                        $item.audioCodec = $audioStream[0].codec_name
                    } elseif ($kind -eq "video") {
                        $item.technicalFlags = @("无音轨")
                    }
                } catch {
                    $item.readable = $false
                    $item.probeError = $_.Exception.Message
                }
            }
        }
    }

    if (-not $item.readable) {
        $errors.Add([pscustomobject][ordered]@{ sourceRelativePath = $projectRelativePath; error = $item.probeError })
    }
    $items.Add($item)
}

$totalDurationSeconds = 0.0
$durationItems = @($items | Where-Object { $null -ne $_.durationSeconds })
foreach ($durationItem in $durationItems) {
    $totalDurationSeconds += [double]$durationItem.durationSeconds
}
$totalDurationSeconds = [math]::Round($totalDurationSeconds, 3)

$index = [ordered]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToString("o")
    projectPath = $resolvedProject
    itemCount = $items.Count
    readableCount = @($items | Where-Object { $_.readable }).Count
    errorCount = $errors.Count
    totalDurationSeconds = $totalDurationSeconds
    items = @($items | ForEach-Object { $_ })
    errors = @($errors | ForEach-Object { $_ })
}

$indexPath = Join-Path $systemRoot "media-index.json"
$index | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $indexPath -Encoding UTF8

$csvPath = Join-Path $resultRoot "素材索引.csv"
$items | Select-Object id, sourceRelativePath, fileName, mediaType, sizeBytes, durationSeconds, width, height, frameRate, videoCodec, audioCodec, hasAudio, readable, @{Name="technicalFlags";Expression={$_.technicalFlags -join '|'}}, probeError |
    Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

$projectConfigPath = Join-Path $systemRoot "project.json"
$projectConfig = Get-Content -LiteralPath $projectConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$projectConfig.status = "indexed"
$projectConfig.updatedAt = (Get-Date).ToString("o")
$projectConfig | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $projectConfigPath -Encoding UTF8

[ordered]@{
    success = $true
    indexPath = $indexPath
    csvPath = $csvPath
    itemCount = $index.itemCount
    readableCount = $index.readableCount
    errorCount = $index.errorCount
    totalDurationSeconds = $index.totalDurationSeconds
} | ConvertTo-Json -Depth 6
