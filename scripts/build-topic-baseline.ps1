$ErrorActionPreference = "Stop"

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$InputFile = Join-Path $Root "docs\data\proposicoes.json"
$OutFile = Join-Path $Root "docs\data\topic-model.json"
$ModelTypes = New-Object System.Collections.Generic.HashSet[string]
@("PL", "PLP", "PEC", "PDL", "PRC", "MPV", "PLV", "PLN") | ForEach-Object { [void] $ModelTypes.Add($_) }

$Stopwords = New-Object System.Collections.Generic.HashSet[string]
@(
  "sobre", "para", "pela", "pelo", "pelos", "pelas", "como", "esta", "este",
  "essa", "esse", "aquele", "aquela", "dispõe", "dispoe", "altera", "alteração",
  "alteracao", "federal", "nacional", "brasil", "brasileiro", "brasileira",
  "providências", "providencias", "outras", "forma", "termos", "institui",
  "estabelece", "cria", "fica", "lei", "projeto", "decreto", "legislativo",
  "complementar", "constituição", "constituicao", "código", "codigo", "artigo",
  "inciso", "parágrafo", "paragrafo", "redação", "redacao", "âmbito", "ambito",
  "união", "uniao", "estado", "municipio", "município", "pública", "publica",
  "público", "publico", "administracao", "administração", "requer",
  "requerimento", "requerimentos", "solicita", "informacoes", "informação",
  "informacao", "pauta", "retirada", "votacao", "votação", "nominal",
  "adiamento", "sessao", "sessão", "solene", "audiencia", "audiência",
  "ministro", "ministra", "apreciacao", "apreciação", "materia", "matéria",
  "realizacao", "realização", "convite", "urgencia", "urgência", "tramitação",
  "tramitacao", "plenário", "plenario", "comissão", "comissao"
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
  return $builder.ToString()
}

function Get-Tokens {
  param([object] $Proposition)

  $text = Normalize-Text -Value (($Proposition.ementa + " " + (($Proposition.keywords | ForEach-Object { $_ }) -join " ")))
  return @(
    [regex]::Matches($text, "[a-z0-9]{4,}") |
      ForEach-Object { $_.Value } |
      Where-Object { -not $Stopwords.Contains($_) -and -not ($_ -match "^\d+$") }
  )
}

$data = Get-Content -Raw -LiteralPath $InputFile | ConvertFrom-Json
$docs = New-Object System.Collections.ArrayList
$documentFrequency = @{}

foreach ($proposition in $data.proposicoes) {
  if (-not $ModelTypes.Contains([string] $proposition.siglaTipo)) {
    continue
  }

  $tokens = @(Get-Tokens -Proposition $proposition)
  if ($tokens.Count -eq 0) {
    continue
  }

  $unique = New-Object System.Collections.Generic.HashSet[string]
  foreach ($token in $tokens) {
    [void] $unique.Add($token)
  }

  foreach ($token in $unique) {
    if (-not $documentFrequency.ContainsKey($token)) {
      $documentFrequency[$token] = 0
    }
    $documentFrequency[$token] += 1
  }

  $doc = New-Object PSObject
  $doc | Add-Member -MemberType NoteProperty -Name "id" -Value $proposition.id
  $doc | Add-Member -MemberType NoteProperty -Name "sigla" -Value "$($proposition.siglaTipo) $($proposition.numero)/$($proposition.ano)"
  $doc | Add-Member -MemberType NoteProperty -Name "ementa" -Value $proposition.ementa
  $doc | Add-Member -MemberType NoteProperty -Name "temas" -Value @($proposition.temas)
  $doc | Add-Member -MemberType NoteProperty -Name "tokens" -Value $tokens
  [void] $docs.Add($doc)
}

$clusterTerms = @(
  $documentFrequency.GetEnumerator() |
    Where-Object { $_.Value -ge 8 -and $_.Value -le [Math]::Max(20, [Math]::Floor($docs.Count * 0.25)) } |
    Sort-Object -Property Value -Descending |
    Select-Object -First 14
)

$clusters = @{}
foreach ($term in $clusterTerms) {
  $clusters[$term.Key] = New-Object System.Collections.ArrayList
}

foreach ($doc in $docs) {
  $tokenCounts = @{}
  foreach ($token in $doc.tokens) {
    if (-not $tokenCounts.ContainsKey($token)) {
      $tokenCounts[$token] = 0
    }
    $tokenCounts[$token] += 1
  }

  $bestTerm = $null
  $bestScore = 0
  foreach ($term in $clusterTerms) {
    if ($tokenCounts.ContainsKey($term.Key)) {
      $score = $tokenCounts[$term.Key] / [Math]::Log(2 + $term.Value)
      if ($score -gt $bestScore) {
        $bestScore = $score
        $bestTerm = $term.Key
      }
    }
  }

  if ($bestTerm) {
    [void] $clusters[$bestTerm].Add($doc)
  }
}

$clusterObjects = New-Object System.Collections.ArrayList
foreach ($term in ($clusters.Keys | Sort-Object)) {
  $members = @($clusters[$term])
  if ($members.Count -lt 4) {
    continue
  }

  $termCounts = @{}
  $themeCounts = @{}
  foreach ($member in $members) {
    foreach ($token in $member.tokens) {
      if (-not $termCounts.ContainsKey($token)) {
        $termCounts[$token] = 0
      }
      $termCounts[$token] += 1
    }
    foreach ($theme in $member.temas) {
      if (-not $themeCounts.ContainsKey($theme)) {
        $themeCounts[$theme] = 0
      }
      $themeCounts[$theme] += 1
    }
  }

  $topTerms = @($termCounts.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 8 | ForEach-Object { $_.Key })
  $topThemes = @($themeCounts.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 5 | ForEach-Object {
    [ordered]@{ name = $_.Key; count = $_.Value }
  })
  $examples = @($members | Select-Object -First 5 | ForEach-Object {
    [ordered]@{ id = $_.id; sigla = $_.sigla; ementa = $_.ementa }
  })

  [void] $clusterObjects.Add([ordered]@{
    label = $term
    count = $members.Count
    topTerms = $topTerms
    topThemes = $topThemes
    examples = $examples
  })
}

$orderedClusters = @($clusterObjects | Sort-Object -Property count -Descending)

[ordered]@{
  generatedAt = (Get-Date).ToUniversalTime().ToString("o")
  method = "Baseline lexical leve sobre ementa + keywords oficiais"
  corpus = [ordered]@{
    documents = $docs.Count
    source = "docs/data/proposicoes.json"
    includedTypes = @($ModelTypes | Sort-Object)
  }
  clusters = $orderedClusters
} | ConvertTo-Json -Depth 12 -Compress | Set-Content -Encoding UTF8 -Path $OutFile

Write-Host "Gerados $($orderedClusters.Count) clusters em $OutFile"
