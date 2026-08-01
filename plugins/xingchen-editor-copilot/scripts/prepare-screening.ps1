[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,

    [ValidateRange(0.05, 0.95)]
    [double]$SceneThreshold = 0.32,

    [ValidateRange(1, 100)]
    [int]$MaxFramesPerVideo = 24,

    [ValidateRange(160, 1280)]
    [int]$ThumbnailWidth = 480
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Convert-Timecode {
    param([double]$Seconds)
    if ($Seconds -lt 0) { $Seconds = 0 }
    return [System.TimeSpan]::FromSeconds($Seconds).ToString("hh\:mm\:ss\.fff")
}

$resolvedProject = [System.IO.Path]::GetFullPath($ProjectPath)
$systemRoot = Join-Path $resolvedProject ".xingchen"
$indexPath = Join-Path $systemRoot "media-index.json"
$thumbnailRoot = Join-Path $systemRoot "thumbnails"
$manifestPath = Join-Path $systemRoot "screening-manifest.json"

if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
    throw "Media index is missing. Run index-media.ps1 first: $indexPath"
}

$index = Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8 | ConvertFrom-Json
$videoItems = @($index.items | Where-Object { $_.mediaType -eq "video" -and $_.readable -eq $true })
$imageItems = @($index.items | Where-Object { $_.mediaType -eq "image" -and $_.readable -eq $true })
$ffmpegCommand = Get-Command ffmpeg -ErrorAction SilentlyContinue
if ($videoItems.Count -gt 0 -and $null -eq $ffmpegCommand) {
    [ordered]@{
        success = $false
        error = "ffmpeg-not-found"
        message = "FFmpeg is required to extract screening previews."
    } | ConvertTo-Json -Depth 5
    return
}

if (-not (Test-Path -LiteralPath $thumbnailRoot)) {
    New-Item -ItemType Directory -Path $thumbnailRoot | Out-Null
}

$segments = New-Object System.Collections.Generic.List[object]
$errors = New-Object System.Collections.Generic.List[object]

foreach ($media in @($videoItems + $imageItems)) {
    $mediaThumbPath = Join-Path $thumbnailRoot $media.id
    if (-not (Test-Path -LiteralPath $mediaThumbPath)) {
        New-Item -ItemType Directory -Path $mediaThumbPath | Out-Null
    }
    $outputPattern = Join-Path $mediaThumbPath "frame-%04d.jpg"
    $sourcePath = $media.sourceFullPath
    $times = @()

    if ($media.mediaType -eq "image") {
        try {
            Add-Type -AssemblyName System.Drawing
            $sourceImage = [System.Drawing.Image]::FromFile($sourcePath)
            try {
                $targetHeight = [math]::Max(1, [int][math]::Round($sourceImage.Height * ($ThumbnailWidth / [double]$sourceImage.Width)))
                $thumbnail = New-Object System.Drawing.Bitmap($ThumbnailWidth, $targetHeight)
                try {
                    $graphics = [System.Drawing.Graphics]::FromImage($thumbnail)
                    try {
                        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                        $graphics.DrawImage($sourceImage, 0, 0, $ThumbnailWidth, $targetHeight)
                    } finally {
                        $graphics.Dispose()
                    }
                    $thumbnail.Save(($outputPattern -replace '%04d', '0001'), [System.Drawing.Imaging.ImageFormat]::Jpeg)
                } finally {
                    $thumbnail.Dispose()
                }
            } finally {
                $sourceImage.Dispose()
            }
            $times = @(0.0)
        } catch {
            $errors.Add([pscustomobject][ordered]@{ sourceRelativePath = $media.sourceRelativePath; error = $_.Exception.Message })
        }
    } else {
        $filter = "select=eq(n\,0)+gt(scene\,$SceneThreshold),scale=$ThumbnailWidth`:-2,showinfo"
        $arguments = @("-hide_banner", "-loglevel", "info", "-y", "-i", $sourcePath, "-vf", $filter, "-vsync", "vfr", "-frames:v", $MaxFramesPerVideo, $outputPattern)
        $log = & $ffmpegCommand.Source @arguments 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            $times = @(
                foreach ($match in [regex]::Matches($log, 'pts_time:([-0-9.]+)')) {
                    [double]$match.Groups[1].Value
                }
            )
        } else {
            $errors.Add([pscustomobject][ordered]@{ sourceRelativePath = $media.sourceRelativePath; error = $log.Trim() })
        }
    }

    $thumbnails = @(Get-ChildItem -LiteralPath $mediaThumbPath -Filter "frame-*.jpg" -File | Sort-Object Name)
    if ($thumbnails.Count -eq 0) { continue }
    if ($times.Count -lt $thumbnails.Count) {
        $duration = if ($null -ne $media.durationSeconds) { [double]$media.durationSeconds } else { 0.0 }
        $step = if ($thumbnails.Count -gt 1 -and $duration -gt 0) { $duration / $thumbnails.Count } else { 0.0 }
        $times = @(for ($i = 0; $i -lt $thumbnails.Count; $i++) { [math]::Round($i * $step, 3) })
    }

    for ($i = 0; $i -lt $thumbnails.Count; $i++) {
        $start = [double]$times[$i]
        $duration = if ($null -ne $media.durationSeconds) { [double]$media.durationSeconds } else { $start }
        $end = if ($i + 1 -lt $times.Count) { [double]$times[$i + 1] } else { $duration }
        if ($end -lt $start) { $end = $start }
        $thumbRelative = ".xingchen/thumbnails/{0}/{1}" -f $media.id, $thumbnails[$i].Name
        $segmentId = "{0}-{1:d4}" -f $media.id, ($i + 1)
        $segments.Add([pscustomobject][ordered]@{
            id = $segmentId
            mediaId = $media.id
            sourceRelativePath = $media.sourceRelativePath
            startSeconds = [math]::Round($start, 3)
            endSeconds = [math]::Round($end, 3)
            startTimecode = Convert-Timecode -Seconds $start
            endTimecode = Convert-Timecode -Seconds $end
            thumbnailRelativePath = $thumbRelative
            transcript = ""
            transcriptionStatus = "not-run"
            contentTags = @()
            technicalFlags = @($media.technicalFlags)
            selectionLevel = "待人工判断"
            recommendationReasons = @()
            confidence = 0.0
            reviewState = "未复核"
            reviewNote = ""
        })
    }
}

$manifest = [ordered]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToString("o")
    projectPath = $resolvedProject
    segmentCount = $segments.Count
    transcriptionAvailable = $false
    segments = @($segments | ForEach-Object { $_ })
    errors = @($errors | ForEach-Object { $_ })
}
$manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

[ordered]@{
    success = ($segments.Count -gt 0)
    manifestPath = $manifestPath
    segmentCount = $segments.Count
    errorCount = $errors.Count
    transcriptionUnavailable = $true
} | ConvertTo-Json -Depth 6
