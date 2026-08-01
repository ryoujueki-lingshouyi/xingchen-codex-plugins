[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,

    [Parameter(Mandatory = $true)]
    [string[]]$SourcePath,

    [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-PathInside {
    param([string]$ChildPath, [string]$ParentPath)
    $child = [System.IO.Path]::GetFullPath($ChildPath).TrimEnd('\') + '\'
    $parent = [System.IO.Path]::GetFullPath($ParentPath).TrimEnd('\') + '\'
    return $child.StartsWith($parent, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-SourceLabel {
    param([string]$ResolvedPath)
    $item = Get-Item -LiteralPath $ResolvedPath
    $drive = [System.IO.Path]::GetPathRoot($ResolvedPath).TrimEnd('\').TrimEnd(':')
    $leaf = if ($item.PSIsContainer) { $item.Name } else { $item.Directory.Name }
    if ([string]::IsNullOrWhiteSpace($leaf)) { $leaf = "ROOT" }
    $label = "{0}_{1}" -f $drive, $leaf
    foreach ($invalidChar in [System.IO.Path]::GetInvalidFileNameChars()) {
        $label = $label.Replace([string]$invalidChar, "_")
    }
    return $label
}

$resolvedProject = [System.IO.Path]::GetFullPath($ProjectPath)
$projectConfigPath = Join-Path $resolvedProject ".xingchen\project.json"
$destinationRoot = Join-Path $resolvedProject "01_原始素材"
if (-not (Test-Path -LiteralPath $projectConfigPath -PathType Leaf)) {
    throw "Not a Xingchen project: $resolvedProject"
}
if (-not (Test-Path -LiteralPath $destinationRoot -PathType Container)) {
    throw "Missing source media directory: $destinationRoot"
}

$entries = New-Object System.Collections.Generic.List[object]
$sourceSummaries = New-Object System.Collections.Generic.List[object]
$preflightConflicts = New-Object System.Collections.Generic.List[object]

foreach ($sourceInput in $SourcePath) {
    $resolvedSource = [System.IO.Path]::GetFullPath($sourceInput)
    if (-not (Test-Path -LiteralPath $resolvedSource)) {
        throw "Source path does not exist: $resolvedSource"
    }
    if (Test-PathInside -ChildPath $resolvedSource -ParentPath $resolvedProject) {
        throw "Import source is already inside the project. Use project validation instead: $resolvedSource"
    }

    $sourceItem = Get-Item -LiteralPath $resolvedSource
    if (($sourceItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Import source cannot be a symbolic link or junction: $resolvedSource"
    }

    $sourceLabel = Get-SourceLabel -ResolvedPath $resolvedSource
    $destinationBase = Join-Path $destinationRoot $sourceLabel
    $files = @()
    if ($sourceItem.PSIsContainer) {
        $files = @(Get-ChildItem -LiteralPath $resolvedSource -File -Recurse -Force)
    } else {
        $files = @($sourceItem)
    }

    foreach ($file in $files) {
        if (($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            $preflightConflicts.Add([pscustomobject][ordered]@{ source = $file.FullName; reason = "link-not-allowed" })
            continue
        }

        $relative = if ($sourceItem.PSIsContainer) {
            $file.FullName.Substring($resolvedSource.TrimEnd('\').Length).TrimStart('\')
        } else {
            $file.Name
        }
        $destination = Join-Path $destinationBase $relative
        $state = "new"
        if (Test-Path -LiteralPath $destination -PathType Leaf) {
            $destinationItem = Get-Item -LiteralPath $destination
            if ($destinationItem.Length -ne $file.Length) {
                $state = "conflict"
                $preflightConflicts.Add([pscustomobject][ordered]@{ source = $file.FullName; destination = $destination; reason = "different-size" })
            } else {
                $sourceHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
                $destinationHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
                if ($sourceHash -eq $destinationHash) {
                    $state = "verified-existing"
                } else {
                    $state = "conflict"
                    $preflightConflicts.Add([pscustomobject][ordered]@{ source = $file.FullName; destination = $destination; reason = "different-hash" })
                }
            }
        }
        $entries.Add([pscustomobject][ordered]@{
            source = $file.FullName
            destination = $destination
            relativePath = $relative
            sizeBytes = [int64]$file.Length
            state = $state
        })
    }

    $sourceTotalBytes = [int64]0
    if ($files.Count -gt 0) {
        $sourceTotalBytes = [int64](($files | Measure-Object -Property Length -Sum).Sum)
    }
    $sourceSummaries.Add([pscustomobject][ordered]@{
        source = $resolvedSource
        destination = $destinationBase
        fileCount = $files.Count
        totalBytes = $sourceTotalBytes
    })
}

$newEntries = @($entries | Where-Object { $_.state -eq "new" })
$bytesToCopy = [int64]0
foreach ($newEntry in $newEntries) {
    $bytesToCopy += [int64]$newEntry.sizeBytes
}
$driveRoot = [System.IO.Path]::GetPathRoot($destinationRoot)
$driveInfo = New-Object System.IO.DriveInfo($driveRoot)
$freeBytes = if ($driveInfo.IsReady) { [int64]$driveInfo.AvailableFreeSpace } else { 0 }
$spaceEnough = ($freeBytes -gt $bytesToCopy)
$verifiedExistingCount = @($entries | Where-Object { $_.state -eq "verified-existing" }).Count

$plan = [ordered]@{
    success = $true
    mode = if ($Execute) { "execute" } else { "preview" }
    projectPath = $resolvedProject
    sources = @($sourceSummaries | ForEach-Object { $_ })
    totalFileCount = $entries.Count
    newFileCount = $newEntries.Count
    verifiedExistingCount = $verifiedExistingCount
    conflictCount = $preflightConflicts.Count
    bytesToCopy = $bytesToCopy
    freeBytes = $freeBytes
    spaceEnough = $spaceEnough
    conflicts = @($preflightConflicts | ForEach-Object { $_ })
}

if (-not $Execute) {
    $plan | ConvertTo-Json -Depth 8
    return
}

if ($preflightConflicts.Count -gt 0) {
    $plan.success = $false
    $plan | ConvertTo-Json -Depth 8
    return
}
if (-not $spaceEnough) {
    $plan.success = $false
    $plan | Add-Member -NotePropertyName error -NotePropertyValue "Insufficient free disk space"
    $plan | ConvertTo-Json -Depth 8
    return
}

$copied = New-Object System.Collections.Generic.List[object]
$failed = New-Object System.Collections.Generic.List[object]
foreach ($entry in $newEntries) {
    try {
        $destinationDirectory = Split-Path -Parent $entry.destination
        if (-not (Test-Path -LiteralPath $destinationDirectory)) {
            New-Item -ItemType Directory -Path $destinationDirectory | Out-Null
        }
        Copy-Item -LiteralPath $entry.source -Destination $entry.destination
        $sourceHash = (Get-FileHash -LiteralPath $entry.source -Algorithm SHA256).Hash
        $destinationHash = (Get-FileHash -LiteralPath $entry.destination -Algorithm SHA256).Hash
        if ($sourceHash -ne $destinationHash) {
            throw "SHA-256 verification failed"
        }
        $copied.Add([pscustomobject][ordered]@{
            source = $entry.source
            destination = $entry.destination
            sizeBytes = $entry.sizeBytes
            sha256 = $sourceHash
        })
    } catch {
        $failed.Add([pscustomobject][ordered]@{
            source = $entry.source
            destination = $entry.destination
            error = $_.Exception.Message
        })
    }
}

$record = [ordered]@{
    schemaVersion = 1
    importedAt = (Get-Date).ToString("o")
    status = if ($failed.Count -eq 0) { "completed" } else { "failed" }
    projectPath = $resolvedProject
    sources = @($sourceSummaries | ForEach-Object { $_ })
    copied = @($copied | ForEach-Object { $_ })
    verifiedExistingCount = $plan.verifiedExistingCount
    failed = @($failed | ForEach-Object { $_ })
}

$importsPath = Join-Path $resolvedProject ".xingchen\imports"
if (-not (Test-Path -LiteralPath $importsPath)) {
    New-Item -ItemType Directory -Path $importsPath | Out-Null
}
$recordPath = Join-Path $importsPath ("import-{0}.json" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
$record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $recordPath -Encoding UTF8

if ($failed.Count -eq 0) {
    $projectConfig = Get-Content -LiteralPath $projectConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $projectConfig.status = "media-imported"
    $projectConfig.updatedAt = (Get-Date).ToString("o")
    $projectConfig | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $projectConfigPath -Encoding UTF8
}

$record | Add-Member -NotePropertyName recordPath -NotePropertyValue $recordPath
$record | ConvertTo-Json -Depth 10
