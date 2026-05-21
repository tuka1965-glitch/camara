$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Years = @(2025, 2026)
$RowsPerFile = 1000
$BaseUrl = "http://dadosabertos.camara.leg.br/arquivos"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$OutDir = Join-Path $Root "docs\data"
$OutFile = Join-Path $OutDir "proposicoes.json"

function Get-CsvData {
  param(
    [string] $Kind,
    [int] $Year
  )

  $url = "$BaseUrl/$Kind/csv/$Kind-$Year.csv"
  $tmpFile = Join-Path ([System.IO.Path]::GetTempPath()) "$Kind-$Year.csv"
  if (-not (Test-Path $tmpFile)) {
    Write-Host "Baixando $url"
    & curl.exe -L --fail --silent --show-error --max-time 240 -o $tmpFile $url
    if ($LASTEXITCODE -ne 0) {
      throw "Falha ao baixar $url"
    }
  }
  Write-Host "Lendo $Kind-$Year.csv"
  return Import-Csv -Path $tmpFile -Delimiter ";" | Select-Object -First $RowsPerFile
}

function Get-FirstValue {
  param(
    [object] $Row,
    [string[]] $Names
  )

  foreach ($name in $Names) {
    if ($Row.PSObject.Properties.Name -contains $name) {
      $value = [string] $Row.$name
      if (-not [string]::IsNullOrWhiteSpace($value)) {
        return $value
      }
    }
  }
  return ""
}

function Split-Keywords {
  param([string] $Value)

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return @()
  }

  return @(
    $Value -split "[;,]" |
      ForEach-Object { $_.Trim() } |
      Where-Object { $_ } |
      Select-Object -First 16
  )
}

function Get-DateOnly {
  param([string] $Value)

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return ""
  }

  if ($Value.Length -ge 10) {
    return $Value.Substring(0, 10)
  }

  return $Value
}

function Get-PropositionId {
  param([object] $Row)

  $id = Get-FirstValue $Row @("idProposicao", "id")
  if ($id) {
    return $id
  }

  $uri = Get-FirstValue $Row @("uriProposicao", "uri")
  if ($uri -match "/proposicoes/(\d+)") {
    return $Matches[1]
  }

  return ""
}

$allPropositions = New-Object System.Collections.Generic.List[object]
$allThemes = New-Object System.Collections.Generic.List[object]
$allAuthors = New-Object System.Collections.Generic.List[object]

foreach ($year in $Years) {
  Get-CsvData "proposicoes" $year | ForEach-Object { $allPropositions.Add($_) }
  Get-CsvData "proposicoesTemas" $year | ForEach-Object { $allThemes.Add($_) }
  Get-CsvData "proposicoesAutores" $year | ForEach-Object { $allAuthors.Add($_) }
}

$themesById = @{}
foreach ($row in $allThemes) {
  $id = Get-PropositionId $row
  $theme = Get-FirstValue $row @("tema", "temaPredominante", "codTema")
  if ($id -and $theme) {
    if (-not $themesById.ContainsKey($id)) {
      $themesById[$id] = New-Object System.Collections.Generic.HashSet[string]
    }
    [void] $themesById[$id].Add($theme)
  }
}

$authorsById = @{}
foreach ($row in $allAuthors) {
  $id = Get-PropositionId $row
  $name = (Get-FirstValue $row @("nomeAutor", "autor", "nome")).Trim()
  if ($id -and $name) {
    if (-not $authorsById.ContainsKey($id)) {
      $authorsById[$id] = New-Object System.Collections.Generic.List[object]
    }
    $authorsById[$id].Add([ordered]@{
      nome = $name
      tipo = (Get-FirstValue $row @("tipoAutor", "tipo")).Trim()
      partido = (Get-FirstValue $row @("siglaPartidoAutor", "siglaPartido")).Trim()
      uf = (Get-FirstValue $row @("siglaUFAutor", "siglaUf")).Trim()
    })
  }
}

$propositions = New-Object System.Collections.ArrayList
foreach ($row in $allPropositions) {
  $id = Get-PropositionId $row
  $yearValue = Get-FirstValue $row @("ano")
  if (-not $id -or -not $yearValue) {
    continue
  }

  $uniqueAuthors = New-Object System.Collections.Generic.List[object]
  $seenAuthors = New-Object System.Collections.Generic.HashSet[string]
  if ($authorsById.ContainsKey($id)) {
    foreach ($author in $authorsById[$id]) {
      if ($seenAuthors.Add($author.nome)) {
        $uniqueAuthors.Add($author)
      }
    }
  }

  $themes = @()
  if ($themesById.ContainsKey($id)) {
    $themes = @($themesById[$id] | Sort-Object)
  }

  $uri = Get-FirstValue -Row $row -Names @("uri")
  $siglaTipo = Get-FirstValue -Row $row -Names @("siglaTipo")
  $numero = Get-FirstValue -Row $row -Names @("numero")
  $descricaoTipo = Get-FirstValue -Row $row -Names @("descricaoTipo")
  $ementa = Get-FirstValue -Row $row -Names @("ementa")
  $keywords = @(Split-Keywords -Value (Get-FirstValue -Row $row -Names @("keywords", "indexacao")))
  $dataApresentacao = Get-DateOnly -Value (Get-FirstValue -Row $row -Names @("dataApresentacao"))
  $urlInteiroTeor = Get-FirstValue -Row $row -Names @("urlInteiroTeor", "linkInteiroTeor")
  $status = Get-FirstValue -Row $row -Names @("ultimoStatus_descricaoSituacao", "statusProposicao_descricaoSituacao", "descricaoSituacao")

  $proposal = New-Object PSObject
  $proposal | Add-Member -MemberType NoteProperty -Name "id" -Value $id
  $proposal | Add-Member -MemberType NoteProperty -Name "uri" -Value $uri
  $proposal | Add-Member -MemberType NoteProperty -Name "siglaTipo" -Value $siglaTipo
  $proposal | Add-Member -MemberType NoteProperty -Name "numero" -Value $numero
  $proposal | Add-Member -MemberType NoteProperty -Name "ano" -Value ([int] $yearValue)
  $proposal | Add-Member -MemberType NoteProperty -Name "descricaoTipo" -Value $descricaoTipo
  $proposal | Add-Member -MemberType NoteProperty -Name "ementa" -Value $ementa
  $proposal | Add-Member -MemberType NoteProperty -Name "keywords" -Value $keywords
  $proposal | Add-Member -MemberType NoteProperty -Name "dataApresentacao" -Value $dataApresentacao
  $proposal | Add-Member -MemberType NoteProperty -Name "urlInteiroTeor" -Value $urlInteiroTeor
  $proposal | Add-Member -MemberType NoteProperty -Name "status" -Value $status
  $proposal | Add-Member -MemberType NoteProperty -Name "temas" -Value $themes
  $proposal | Add-Member -MemberType NoteProperty -Name "autores" -Value @($uniqueAuthors.ToArray())
  [void] $propositions.Add($proposal)
}

$orderedPropositions = @($propositions | Sort-Object -Property @{ Expression = "dataApresentacao"; Descending = $true }, @{ Expression = "id"; Descending = $true })

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
[ordered]@{
  generatedAt = (Get-Date).ToUniversalTime().ToString("o")
  years = $Years
  source = "Dados Abertos da Camara dos Deputados"
  proposicoes = $orderedPropositions
} | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 -Path $OutFile

Write-Host "Geradas $($orderedPropositions.Count) proposicoes em $OutFile"
