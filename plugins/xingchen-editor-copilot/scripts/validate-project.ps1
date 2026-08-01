[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,

    [switch]$Repair
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-ProjectFilesSafely {
    param([string]$Root)

    $files = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    $links = New-Object System.Collections.Generic.List[string]
    $pending = New-Object System.Collections.Generic.Stack[string]
    $pending.Push($Root)

    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        foreach ($item in Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop) {
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                $links.Add($item.FullName)
                continue
            }
            if ($item.PSIsContainer) {
                $pending.Push($item.FullName)
            } else {
                $files.Add($item)
            }
        }
    }

    return [ordered]@{ files = @($files); links = @($links) }
}

$resolvedProject = [System.IO.Path]::GetFullPath($ProjectPath)
if (-not (Test-Path -LiteralPath $resolvedProject -PathType Container)) {
    throw "Project path does not exist: $resolvedProject"
}

$requiredDirectories = @("01_原始素材", "02_素材筛选结果", ".xingchen")
$missingDirectories = @(
    foreach ($relative in $requiredDirectories) {
        if (-not (Test-Path -LiteralPath (Join-Path $resolvedProject $relative) -PathType Container)) {
            $relative
        }
    }
)

$repairedDirectories = @()
if ($Repair -and $missingDirectories.Count -gt 0) {
    foreach ($relative in $missingDirectories) {
        New-Item -ItemType Directory -Path (Join-Path $resolvedProject $relative) | Out-Null
        $repairedDirectories += $relative
    }
    $missingDirectories = @()
}

$blockers = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

foreach ($relative in $missingDirectories) {
    $blockers.Add("缺少必要目录：$relative")
}

$projectConfigPath = Join-Path $resolvedProject ".xingchen\project.json"
if (-not (Test-Path -LiteralPath $projectConfigPath -PathType Leaf)) {
    $blockers.Add("缺少项目配置：.xingchen/project.json")
}

$sourcePath = Join-Path $resolvedProject "01_原始素材"
$mediaFiles = @()
$reparsePoints = @()
if (Test-Path -LiteralPath $sourcePath -PathType Container) {
    $scan = Get-ProjectFilesSafely -Root $sourcePath
    $reparsePoints = @($scan.links)
    if ($reparsePoints.Count -gt 0) {
        foreach ($link in $reparsePoints) {
            $blockers.Add("原始素材目录包含链接，已拒绝跟随：$link")
        }
    }
    $supportedExtensions = @(".mp4", ".mov", ".mxf", ".avi", ".mkv", ".mts", ".m2ts", ".wav", ".mp3", ".aif", ".aiff", ".jpg", ".jpeg", ".png", ".heic", ".tif", ".tiff")
    $mediaFiles = @($scan.files | Where-Object { $supportedExtensions -contains $_.Extension.ToLowerInvariant() })
}

if ($mediaFiles.Count -eq 0) {
    $blockers.Add("01_原始素材中没有发现支持的视频、音频或图片")
}

$zeroByteFiles = @($mediaFiles | Where-Object { $_.Length -eq 0 } | ForEach-Object { $_.FullName })
foreach ($file in $zeroByteFiles) {
    $blockers.Add("发现零字节素材：$file")
}

$outputPath = Join-Path $resolvedProject "02_素材筛选结果"
$outputWritable = $false
if (Test-Path -LiteralPath $outputPath -PathType Container) {
    $probePath = Join-Path $outputPath (".write-test-{0}.tmp" -f [guid]::NewGuid().ToString("N"))
    try {
        [System.IO.File]::WriteAllText($probePath, "xingchen")
        [System.IO.File]::Delete($probePath)
        $outputWritable = $true
    } catch {
        $blockers.Add("02_素材筛选结果不可写：$($_.Exception.Message)")
    }
}

$videoExtensions = @(".mp4", ".mov", ".mxf", ".avi", ".mkv", ".mts", ".m2ts")
$videoFiles = @($mediaFiles | Where-Object { $videoExtensions -contains $_.Extension.ToLowerInvariant() -and $_.Length -gt 0 })
$ffprobeCommand = Get-Command ffprobe -ErrorAction SilentlyContinue
$readableVideoCount = 0
$unreadableVideos = @()
if ($videoFiles.Count -gt 0 -and $null -eq $ffprobeCommand) {
    $blockers.Add("检测到视频素材，但未找到 FFprobe；无法验证视频并开始筛选")
} elseif ($videoFiles.Count -gt 0) {
    foreach ($video in $videoFiles) {
        $probeOutput = & $ffprobeCommand.Source -v error -show_entries format=duration -of "default=noprint_wrappers=1:nokey=1" $video.FullName 2>&1
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($probeOutput | Out-String))) {
            $readableVideoCount++
        } else {
            $unreadableVideos += $video.FullName
        }
    }
    if ($readableVideoCount -eq 0) {
        $blockers.Add("没有任何视频能够被 FFprobe 正常读取")
    } elseif ($unreadableVideos.Count -gt 0) {
        $warnings.Add("有 $($unreadableVideos.Count) 条视频无法读取，筛选时必须单独列出")
    }
}

$briefPath = Join-Path $resolvedProject ".xingchen\brief.json"
$briefConfirmed = $false
if (Test-Path -LiteralPath $briefPath -PathType Leaf) {
    try {
        $brief = Get-Content -LiteralPath $briefPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $briefConfirmed = ($brief.confirmed -eq $true)
    } catch {
        $blockers.Add("项目 Brief 无法读取：$($_.Exception.Message)")
    }
}
if (-not $briefConfirmed) {
    $warnings.Add("项目 Brief 尚未确认；开始 AI 筛选前必须汇总并确认")
}

$totalBytes = [int64]0
if ($mediaFiles.Count -gt 0) {
    $totalBytes = [int64](($mediaFiles | Measure-Object -Property Length -Sum).Sum)
}

$result = [ordered]@{
    schemaVersion = 1
    checkedAt = (Get-Date).ToString("o")
    projectPath = $resolvedProject
    readyForScreening = ($blockers.Count -eq 0)
    briefConfirmed = $briefConfirmed
    mediaFileCount = $mediaFiles.Count
    videoFileCount = $videoFiles.Count
    readableVideoCount = $readableVideoCount
    totalBytes = $totalBytes
    outputWritable = $outputWritable
    repairedDirectories = @($repairedDirectories)
    blockers = @($blockers)
    warnings = @($warnings)
    zeroByteFiles = @($zeroByteFiles)
    unreadableVideos = @($unreadableVideos)
    reparsePoints = @($reparsePoints)
}

$validationPath = Join-Path $resolvedProject ".xingchen\validation.json"
if (Test-Path -LiteralPath (Split-Path -Parent $validationPath) -PathType Container) {
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $validationPath -Encoding UTF8
}

$result | ConvertTo-Json -Depth 8
