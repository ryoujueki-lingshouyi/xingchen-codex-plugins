[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Convert-HtmlText {
    param($Value)
    if ($null -eq $Value) { return "" }
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function Join-Values {
    param($Value)
    if ($null -eq $Value) { return "" }
    return (@($Value) -join "、")
}

$resolvedProject = [System.IO.Path]::GetFullPath($ProjectPath)
$systemRoot = Join-Path $resolvedProject ".xingchen"
$resultRoot = Join-Path $resolvedProject "02_素材筛选结果"
$selectionPath = Join-Path $systemRoot "selection.json"
$manifestPath = Join-Path $systemRoot "screening-manifest.json"

if (-not (Test-Path -LiteralPath $resultRoot -PathType Container)) {
    throw "Screening output directory is missing: $resultRoot"
}

$dataPath = if (Test-Path -LiteralPath $selectionPath -PathType Leaf) { $selectionPath } else { $manifestPath }
if (-not (Test-Path -LiteralPath $dataPath -PathType Leaf)) {
    throw "No screening data was found. Run prepare-screening.ps1 first."
}

$data = Get-Content -LiteralPath $dataPath -Raw -Encoding UTF8 | ConvertFrom-Json
$records = @()
if ($null -ne $data.segments) {
    $records = @($data.segments)
} elseif ($data -is [System.Array]) {
    $records = @($data)
} else {
    $records = @($data)
}

$candidateRecords = @($records | Where-Object { $_.selectionLevel -eq "重点候选" -or $_.selectionLevel -eq "普通候选" })
$issueRecords = @($records | Where-Object { @($_.technicalFlags).Count -gt 0 })

$candidatePath = Join-Path $resultRoot "候选镜头.csv"
$issuePath = Join-Path $resultRoot "问题素材.csv"
$htmlPath = Join-Path $resultRoot "素材筛选台.html"

$candidateRecords | Select-Object id, sourceRelativePath, startTimecode, endTimecode, selectionLevel, @{Name="contentTags";Expression={Join-Values $_.contentTags}}, @{Name="recommendationReasons";Expression={Join-Values $_.recommendationReasons}}, confidence, reviewState, reviewNote |
    Export-Csv -LiteralPath $candidatePath -NoTypeInformation -Encoding UTF8
$issueRecords | Select-Object id, sourceRelativePath, startTimecode, endTimecode, selectionLevel, @{Name="technicalFlags";Expression={Join-Values $_.technicalFlags}}, reviewState, reviewNote |
    Export-Csv -LiteralPath $issuePath -NoTypeInformation -Encoding UTF8

$cards = New-Object System.Text.StringBuilder
foreach ($record in $records) {
    $level = Convert-HtmlText $record.selectionLevel
    $source = Convert-HtmlText $record.sourceRelativePath
    $start = Convert-HtmlText $record.startTimecode
    $end = Convert-HtmlText $record.endTimecode
    $tags = Convert-HtmlText (Join-Values $record.contentTags)
    $flags = Convert-HtmlText (Join-Values $record.technicalFlags)
    $reasons = Convert-HtmlText (Join-Values $record.recommendationReasons)
    $transcript = Convert-HtmlText $record.transcript
    $confidence = if ($null -ne $record.confidence) { [math]::Round(([double]$record.confidence * 100), 0) } else { 0 }
    $thumb = [string]$record.thumbnailRelativePath
    $thumb = $thumb.Replace('\', '/')
    if ($thumb.StartsWith(".xingchen/")) { $thumb = "../" + $thumb }
    $thumb = Convert-HtmlText $thumb
    $searchText = Convert-HtmlText ("$source $tags $flags $reasons $transcript")

    [void]$cards.AppendLine(@"
<article class="card" data-level="$level" data-search="$searchText">
  <img src="$thumb" alt="$source $start" loading="lazy">
  <div class="card-body">
    <div class="level">$level · 置信度 $confidence%</div>
    <h2>$source</h2>
    <p class="time">$start — $end</p>
    <p><strong>标签：</strong>$tags</p>
    <p><strong>推荐理由：</strong>$reasons</p>
    <p><strong>技术提示：</strong>$flags</p>
    <p><strong>转写：</strong>$transcript</p>
  </div>
</article>
"@)
}

$generatedAt = Convert-HtmlText (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$totalCount = @($records).Count
$candidateCount = @($candidateRecords).Count
$reviewCount = @($records | Where-Object { $_.selectionLevel -eq "待人工判断" }).Count
$issueCount = @($issueRecords).Count

$html = @"
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>星辰素材筛选台</title>
<style>
:root{color-scheme:light;font-family:"Microsoft YaHei",system-ui,sans-serif;background:#f5f7fb;color:#17233c}
body{margin:0}.header{background:#0b132b;color:white;padding:28px 5vw}.header h1{margin:0 0 8px;font-size:28px}.stats{color:#c9d7ef}.toolbar{position:sticky;top:0;z-index:2;display:flex;gap:12px;padding:14px 5vw;background:#fff;border-bottom:1px solid #dce3ee}.toolbar input,.toolbar select{font:inherit;padding:9px 12px;border:1px solid #cbd5e1;border-radius:8px}.toolbar input{flex:1}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(320px,1fr));gap:18px;padding:24px 5vw}.card{background:white;border:1px solid #dce3ee;border-radius:12px;overflow:hidden;box-shadow:0 5px 18px rgba(11,19,43,.06)}.card img{width:100%;height:190px;object-fit:cover;background:#0b132b}.card-body{padding:16px}.card h2{font-size:15px;word-break:break-all}.card p{font-size:13px;line-height:1.55}.level{display:inline-block;background:#eaf3ff;color:#175db5;padding:4px 8px;border-radius:999px;font-size:12px}.time{color:#65728a}.hidden{display:none}
</style>
</head>
<body>
<header class="header"><h1>星辰素材筛选台</h1><div class="stats">生成：$generatedAt　片段：$totalCount　候选：$candidateCount　待人工判断：$reviewCount　技术提示：$issueCount</div></header>
<div class="toolbar"><input id="query" placeholder="搜索人物、场景、动作、讲话或文件名"><select id="level"><option value="">全部等级</option><option>重点候选</option><option>普通候选</option><option>低相关</option><option>待人工判断</option></select></div>
<main class="grid">$($cards.ToString())</main>
<script>
const q=document.querySelector('#query'),l=document.querySelector('#level'),cards=[...document.querySelectorAll('.card')];
function filter(){const text=q.value.trim().toLowerCase(),level=l.value;for(const c of cards){const okText=!text||c.dataset.search.toLowerCase().includes(text);const okLevel=!level||c.dataset.level===level;c.classList.toggle('hidden',!(okText&&okLevel));}}
q.addEventListener('input',filter);l.addEventListener('change',filter);
</script>
</body>
</html>
"@
$html | Set-Content -LiteralPath $htmlPath -Encoding UTF8

$projectConfigPath = Join-Path $systemRoot "project.json"
if (Test-Path -LiteralPath $projectConfigPath -PathType Leaf) {
    $projectConfig = Get-Content -LiteralPath $projectConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $projectConfig.status = "screened"
    $projectConfig.updatedAt = (Get-Date).ToString("o")
    $projectConfig | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $projectConfigPath -Encoding UTF8
}

[ordered]@{
    success = $true
    sourceDataPath = $dataPath
    htmlPath = $htmlPath
    candidateCsvPath = $candidatePath
    issueCsvPath = $issuePath
    recordCount = $totalCount
    candidateCount = $candidateCount
    manualReviewCount = $reviewCount
    issueCount = $issueCount
} | ConvertTo-Json -Depth 6
