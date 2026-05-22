$ErrorActionPreference = "Stop"

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$InputFile = Join-Path $Root "docs\data\proposicoes.json"
$OutFile = Join-Path $Root "docs\data\topic-model.json"

$ModelTypes = New-Object System.Collections.Generic.HashSet[string]
@("PL", "PLP", "PEC", "PDL", "PRC", "MPV", "PLV", "PLN") | ForEach-Object { [void] $ModelTypes.Add($_) }

$GenericDescriptors = New-Object System.Collections.Generic.HashSet[string]
@(
  "alteracao", "criacao", "criterio", "diretrizes", "obrigatoriedade",
  "proibicao", "sustacao", "lei federal", "decreto legislativo", "lei",
  "programa", "dezembro", "pessoa", "servico", "servicos", "oficial",
  "parecer", "aprovacao", "submete", "constante", "congresso", "susta",
  "resolucao", "requerimento", "retirada", "pauta", "votacao", "nominal",
  "informacoes", "ministro", "ministra", "materia", "plenario", "comissao"
) | ForEach-Object { [void] $GenericDescriptors.Add($_) }

$Stopwords = New-Object System.Collections.Generic.HashSet[string]
@(
  "sobre", "para", "pela", "pelo", "pelos", "pelas", "como", "esta", "este",
  "essa", "esse", "aquele", "aquela", "dispoe", "altera", "alteracao",
  "federal", "nacional", "brasil", "brasileiro", "brasileira", "providencias",
  "outras", "forma", "termos", "institui", "estabelece", "cria", "fica",
  "lei", "projeto", "decreto", "legislativo", "complementar", "constituicao",
  "codigo", "artigo", "inciso", "paragrafo", "redacao", "ambito", "uniao",
  "estado", "municipio", "publica", "publico", "administracao"
) | ForEach-Object { [void] $Stopwords.Add($_) }

function Normalize-Text {
  param([string] $Value)

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return ""
  }

  $normalized = $Value.ToLowerInvariant().Normalize([Text.NormalizationForm]::FormD)
  $builder = New-Object System.Text.StringBuilder
  foreach ($char in $normalized.ToCharArray()) {
    if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($char) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
      [void] $builder.Append($char)
    }
  }
  return ($builder.ToString() -replace "[^a-z0-9 ]+", " " -replace "\s+", " ").Trim()
}

function Get-InformativeTokens {
  param([string] $Value)

  $normalized = Normalize-Text -Value $Value
  return @(
    [regex]::Matches($normalized, "[a-z0-9]{4,}") |
      ForEach-Object { $_.Value } |
      Where-Object { -not $Stopwords.Contains($_) -and -not ($_ -match "^\d+$") }
  )
}

function Get-Descriptors {
  param([object] $Proposition)

  $items = New-Object System.Collections.ArrayList
  foreach ($keyword in $Proposition.keywords) {
    $display = (([string] $keyword).Trim() -replace "^_+", "" -replace "[\.;:,\s]+$", "")
    $normalized = Normalize-Text -Value $display
    $tokens = @(Get-InformativeTokens -Value $display)

    if (-not $display -or -not $normalized -or $GenericDescriptors.Contains($normalized)) {
      continue
    }

    if ($tokens.Count -lt 2) {
      continue
    }

    [void] $items.Add([ordered]@{
      display = $display
      normalized = $normalized
      tokens = $tokens
    })
  }
  return @($items)
}

$data = Get-Content -Raw -LiteralPath $InputFile | ConvertFrom-Json
$docs = New-Object System.Collections.ArrayList
$descriptorFrequency = @{}
$descriptorDisplay = @{}

foreach ($proposition in $data.proposicoes) {
  if (-not $ModelTypes.Contains([string] $proposition.siglaTipo)) {
    continue
  }

  $descriptors = @(Get-Descriptors -Proposition $proposition)
  if ($descriptors.Count -eq 0) {
    continue
  }

  $seenDescriptors = New-Object System.Collections.Generic.HashSet[string]
  foreach ($descriptor in $descriptors) {
    if ($seenDescriptors.Add($descriptor.normalized)) {
      if (-not $descriptorFrequency.ContainsKey($descriptor.normalized)) {
        $descriptorFrequency[$descriptor.normalized] = 0
        $descriptorDisplay[$descriptor.normalized] = $descriptor.display
      }
      $descriptorFrequency[$descriptor.normalized] += 1
    }
  }

  $doc = New-Object PSObject
  $doc | Add-Member -MemberType NoteProperty -Name "id" -Value $proposition.id
  $doc | Add-Member -MemberType NoteProperty -Name "sigla" -Value "$($proposition.siglaTipo) $($proposition.numero)/$($proposition.ano)"
  $doc | Add-Member -MemberType NoteProperty -Name "ementa" -Value $proposition.ementa
  $doc | Add-Member -MemberType NoteProperty -Name "temas" -Value @($proposition.temas)
  $doc | Add-Member -MemberType NoteProperty -Name "descriptors" -Value $descriptors
  [void] $docs.Add($doc)
}

$clusterDescriptors = @(
  $descriptorFrequency.GetEnumerator() |
    Where-Object { $_.Value -ge 3 -and $_.Value -le [Math]::Max(8, [Math]::Floor($docs.Count * 0.18)) } |
    Sort-Object -Property Value -Descending |
    Select-Object -First 18
)

$clusters = @{}
foreach ($descriptor in $clusterDescriptors) {
  $clusters[$descriptor.Key] = New-Object System.Collections.ArrayList
}

foreach ($doc in $docs) {
  $bestDescriptor = $null
  $bestScore = 0
  foreach ($descriptor in $doc.descriptors) {
    if (-not $descriptorFrequency.ContainsKey($descriptor.normalized)) {
      continue
    }
    if (-not $clusters.ContainsKey($descriptor.normalized)) {
      continue
    }

    $tokenBoost = [Math]::Min(2.2, 1 + ($descriptor.tokens.Count * 0.25))
    $score = $tokenBoost / [Math]::Log(2 + $descriptorFrequency[$descriptor.normalized])
    if ($score -gt $bestScore) {
      $bestScore = $score
      $bestDescriptor = $descriptor.normalized
    }
  }

  if ($bestDescriptor) {
    [void] $clusters[$bestDescriptor].Add($doc)
  }
}

$clusterObjects = New-Object System.Collections.ArrayList
foreach ($descriptorKey in ($clusters.Keys | Sort-Object)) {
  $members = @($clusters[$descriptorKey])
  if ($members.Count -lt 3) {
    continue
  }

  $descriptorCounts = @{}
  $themeCounts = @{}
  foreach ($member in $members) {
    foreach ($descriptor in $member.descriptors) {
      if (-not $descriptorCounts.ContainsKey($descriptor.normalized)) {
        $descriptorCounts[$descriptor.normalized] = 0
        $descriptorDisplay[$descriptor.normalized] = $descriptor.display
      }
      $descriptorCounts[$descriptor.normalized] += 1
    }
    foreach ($theme in $member.temas) {
      if (-not $themeCounts.ContainsKey($theme)) {
        $themeCounts[$theme] = 0
      }
      $themeCounts[$theme] += 1
    }
  }

  $topDescriptors = @(
    $descriptorCounts.GetEnumerator() |
      Sort-Object -Property Value -Descending |
      Select-Object -First 8 |
      ForEach-Object { $descriptorDisplay[$_.Key] }
  )
  $topThemes = @($themeCounts.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 5 | ForEach-Object {
    [ordered]@{ name = $_.Key; count = $_.Value }
  })
  $examples = @($members | Select-Object -First 5 | ForEach-Object {
    [ordered]@{ id = $_.id; sigla = $_.sigla; ementa = $_.ementa }
  })

  [void] $clusterObjects.Add([ordered]@{
    label = $descriptorDisplay[$descriptorKey]
    count = $members.Count
    topTerms = $topDescriptors
    topThemes = $topThemes
    examples = $examples
  })
}

$orderedClusters = @($clusterObjects | Sort-Object -Property count -Descending)

[ordered]@{
  generatedAt = (Get-Date).ToUniversalTime().ToString("o")
  method = "Baseline por descritores oficiais compostos sobre ementa + keywords"
  corpus = [ordered]@{
    documents = $docs.Count
    source = "docs/data/proposicoes.json"
    includedTypes = @($ModelTypes | Sort-Object)
  }
  clusters = $orderedClusters
} | ConvertTo-Json -Depth 12 -Compress | Set-Content -Encoding UTF8 -Path $OutFile

Write-Host "Gerados $($orderedClusters.Count) clusters em $OutFile"
