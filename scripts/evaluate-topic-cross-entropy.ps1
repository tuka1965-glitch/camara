$ErrorActionPreference = "Stop"

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$DataFile = Join-Path $Root "docs\data\proposicoes.json"
$TopicFile = Join-Path $Root "docs\data\bertopic-model.json"
$OutFile = Join-Path $Root "docs\data\bertopic-cross-entropy.json"

$data = Get-Content -Raw -LiteralPath $DataFile | ConvertFrom-Json
$model = Get-Content -Raw -LiteralPath $TopicFile | ConvertFrom-Json

$byId = @{}
foreach ($p in $data.proposicoes) {
  $byId[[string] $p.id] = $p
}

$themeSet = New-Object "System.Collections.Generic.HashSet[string]"
foreach ($p in $data.proposicoes) {
  foreach ($theme in @($p.temas)) {
    if ($theme) {
      [void] $themeSet.Add([string] $theme)
    }
  }
}

$themes = @($themeSet | Sort-Object)
$themeCount = $themes.Count
$alpha = 1.0

$globalCounts = @{}
foreach ($theme in $themes) {
  $globalCounts[$theme] = 0
}

foreach ($cluster in @($model.clusters)) {
  foreach ($id in @($cluster.memberIds)) {
    $p = $byId[[string] $id]
    if ($null -eq $p) {
      continue
    }
    foreach ($theme in @($p.temas)) {
      if ($theme) {
        $globalCounts[[string] $theme]++
      }
    }
  }
}

$globalTotal = ($globalCounts.Values | Measure-Object -Sum).Sum
$assignedDocuments = 0
$documentsWithOfficialTheme = 0
$sumCrossEntropy = 0.0
$sumBaselineCrossEntropy = 0.0
$sumTargetEntropy = 0.0
$rows = New-Object System.Collections.ArrayList

foreach ($cluster in @($model.clusters)) {
  $memberIds = @($cluster.memberIds)
  if ($memberIds.Count -eq 0) {
    continue
  }

  $clusterCounts = @{}
  foreach ($theme in $themes) {
    $clusterCounts[$theme] = 0
  }

  foreach ($id in $memberIds) {
    $p = $byId[[string] $id]
    if ($null -eq $p) {
      continue
    }
    foreach ($theme in @($p.temas)) {
      if ($theme) {
        $clusterCounts[[string] $theme]++
      }
    }
  }

  $clusterLabelTotal = ($clusterCounts.Values | Measure-Object -Sum).Sum
  $clusterCrossEntropy = 0.0
  $clusterDocuments = 0

  foreach ($id in $memberIds) {
    $assignedDocuments++
    $p = $byId[[string] $id]
    if ($null -eq $p) {
      continue
    }

    $docThemes = @($p.temas) | Where-Object { $_ }
    if ($docThemes.Count -eq 0) {
      continue
    }

    $documentsWithOfficialTheme++
    $clusterDocuments++
    $docCrossEntropy = 0.0
    $baselineCrossEntropy = 0.0

    foreach ($theme in $docThemes) {
      $clusterProbability = ([double] $clusterCounts[[string] $theme] + $alpha) / ([double] $clusterLabelTotal + ($alpha * $themeCount))
      $globalProbability = ([double] $globalCounts[[string] $theme] + $alpha) / ([double] $globalTotal + ($alpha * $themeCount))
      $docCrossEntropy += -[Math]::Log($clusterProbability) / $docThemes.Count
      $baselineCrossEntropy += -[Math]::Log($globalProbability) / $docThemes.Count
    }

    $sumCrossEntropy += $docCrossEntropy
    $sumBaselineCrossEntropy += $baselineCrossEntropy
    $sumTargetEntropy += [Math]::Log($docThemes.Count)
    $clusterCrossEntropy += $docCrossEntropy
  }

  if ($clusterDocuments -gt 0) {
    [void] $rows.Add([pscustomobject]@{
      label = $cluster.label
      documents = $clusterDocuments
      crossEntropyNats = [Math]::Round($clusterCrossEntropy / $clusterDocuments, 3)
      perplexity = [Math]::Round([Math]::Exp($clusterCrossEntropy / $clusterDocuments), 2)
      topOfficialThemes = $cluster.topThemes
      topTerms = $cluster.topTerms
    })
  }
}

$crossEntropy = 0.0
$baselineCrossEntropy = 0.0
$targetEntropy = 0.0
if ($documentsWithOfficialTheme -gt 0) {
  $crossEntropy = $sumCrossEntropy / $documentsWithOfficialTheme
  $baselineCrossEntropy = $sumBaselineCrossEntropy / $documentsWithOfficialTheme
  $targetEntropy = $sumTargetEntropy / $documentsWithOfficialTheme
}

$relativeImprovement = 0.0
if ($baselineCrossEntropy -gt 0) {
  $relativeImprovement = ($baselineCrossEntropy - $crossEntropy) / $baselineCrossEntropy
}

$payload = [ordered]@{
  generatedAt = (Get-Date).ToUniversalTime().ToString("o")
  modelGeneratedAt = $model.generatedAt
  method = "Entropia cruzada exploratoria entre distribuicao de temas oficiais por cluster BERTopic e temas oficiais multilabel de cada proposicao."
  officialThemes = $themeCount
  bertDocuments = [int] $model.corpus.documents
  assignedToClusters = $assignedDocuments
  outliers = [int] $model.outliers
  evaluatedDocumentsWithOfficialTheme = $documentsWithOfficialTheme
  crossEntropyNats = [Math]::Round($crossEntropy, 3)
  perplexity = [Math]::Round([Math]::Exp($crossEntropy), 2)
  baselineGlobalCrossEntropyNats = [Math]::Round($baselineCrossEntropy, 3)
  baselineGlobalPerplexity = [Math]::Round([Math]::Exp($baselineCrossEntropy), 2)
  relativeImprovementVsBaseline = [Math]::Round($relativeImprovement, 3)
  targetEntropyNats = [Math]::Round($targetEntropy, 3)
  klDivergenceNats = [Math]::Round($crossEntropy - $targetEntropy, 3)
  bestClusters = @($rows | Sort-Object -Property crossEntropyNats | Select-Object -First 8)
  worstClusters = @($rows | Sort-Object -Property crossEntropyNats -Descending | Select-Object -First 8)
}

$payload | ConvertTo-Json -Depth 12 -Compress | Set-Content -Encoding UTF8 -Path $OutFile

Write-Host "Entropia cruzada BERTopic: $($payload.crossEntropyNats)"
Write-Host "Baseline global: $($payload.baselineGlobalCrossEntropyNats)"
Write-Host "Melhora relativa: $($payload.relativeImprovementVsBaseline)"
