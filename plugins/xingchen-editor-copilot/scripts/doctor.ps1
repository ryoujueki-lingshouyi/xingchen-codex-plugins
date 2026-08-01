[CmdletBinding()]
param(
    [string]$WorkingPath = (Get-Location).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Find-Executable {
    param([string]$Name)

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        return $null
    }
    return $command.Source
}

$resolvedPath = [System.IO.Path]::GetFullPath($WorkingPath)
$driveRoot = [System.IO.Path]::GetPathRoot($resolvedPath)
$driveInfo = New-Object System.IO.DriveInfo($driveRoot)

$premiereCandidates = @(
    "$env:ProgramFiles\Adobe",
    "${env:ProgramFiles(x86)}\Adobe"
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

$resolveCandidates = @(
    "$env:ProgramFiles\Blackmagic Design\DaVinci Resolve\Resolve.exe",
    "${env:ProgramFiles(x86)}\Blackmagic Design\DaVinci Resolve\Resolve.exe"
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

$result = [ordered]@{
    workingPath = $resolvedPath
    powershellVersion = $PSVersionTable.PSVersion.ToString()
    ffmpeg = Find-Executable "ffmpeg"
    ffprobe = Find-Executable "ffprobe"
    premiereAdobeFolders = @($premiereCandidates)
    davinciResolveExecutables = @($resolveCandidates)
    freeDiskGB = if ($driveInfo.IsReady) { [math]::Round($driveInfo.AvailableFreeSpace / 1GB, 2) } else { $null }
}

$result["readyForMediaInventory"] = ($null -ne $result.ffprobe)
$result["warnings"] = @(
    if ($null -eq $result.ffmpeg) { "FFmpeg was not found in PATH." }
    if ($null -eq $result.ffprobe) { "ffprobe was not found in PATH; media inventory will be limited." }
    if (($null -ne $result.freeDiskGB) -and $result.freeDiskGB -lt 100) { "Less than 100 GB free on the working drive." }
)

$result | ConvertTo-Json -Depth 5
