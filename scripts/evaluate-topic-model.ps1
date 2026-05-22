$ErrorActionPreference = "Stop"

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$TopicFile = Join-Path $Root "docs\data\bertopic-model.json"
$OutFile = Join-Path $Root "docs\data\bertopic-evaluation.json"

$model = Get-Content -Raw -LiteralPath $TopicFile | ConvertFrom-Json
$clusters = @($model.clusters)

$weightedPurityNumerator = 0
$assignedDocuments = 0
$rows = New-Object System.Collections.ArrayList

foreach ($cluster in $clusters) {
  $count = [int] $cluster.count
  if ($count -le 0) {
    continue
  }

  $dominantTheme = $null
  $dominantCount = 0
  if ($cluster.topThemes -and $cluster.topThemes.Count -gt 0) {
    $dominantTheme = $cluster.topThemes[0].name
    $dominantCount = [int] $cluster.topThemes[0].count
  }

  $purity = 0
  if ($dominantCount -gt 0) {
    $purity = [Math]::Round($dominantCount / $count, 3)
  }

  $assignedDocuments += $count
  $weightedPurityNumerator += $dominantCount

  [void] $rows.Add([ordered]@{
    label = $cluster.label
    count = $count
    dominantTheme = $dominantTheme
    dominantThemeCount = $dominantCount
    purity = $purity
    topThemes = $cluster.topThemes
    topTerms = $cluster.topTerms
  })
}

$weightedPurity = 0
if ($assignedDocuments -gt 0) {
  $weightedPurity = [Math]::Round($weightedPurityNumerator / $assignedDocuments, 3)
}

$outliers = 0
if ($null -ne $model.outliers) {
  $outliers = [int] $model.outliers
}
$documents = [int] $model.corpus.documents
$coverage = 0
if ($documents -gt 0) {
  $coverage = [Math]::Round($assignedDocuments / $documents, 3)
}

$payload = [ordered]@{
  generatedAt = (Get-Date).ToUniversalTime().ToString("o")
  model = "BERTopic"
  documents = $documents
  assignedDocuments = $assignedDocuments
  outliers = $outliers
  clusterCount = $rows.Count
  coverage = $coverage
  weightedPurityAgainstOfficialThemes = $weightedPurity
  note = "Pureza mede a proporcao do tema oficial dominante dentro de cada cluster. Como uma proposicao pode ter multiplos temas oficiais, esta metrica e exploratoria, nao uma acuracia supervisionada estrita."
  clusters = @($rows | Sort-Object -Property purity, count -Descending)
}

$payload | ConvertTo-Json -Depth 12 -Compress | Set-Content -Encoding UTF8 -Path $OutFile

Write-Host "Avaliados $($rows.Count) clusters em $OutFile"
Write-Host "Documentos: $documents"
Write-Host "Atribuidos a clusters: $assignedDocuments"
Write-Host "Outliers: $outliers"
Write-Host "Cobertura: $coverage"
Write-Host "Pureza ponderada: $weightedPurity"
