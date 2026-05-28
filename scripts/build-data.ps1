$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Years = @(2024, 2025, 2026)
$IncludedTypes = @("PL", "PLP", "PEC", "PDL", "PRC", "MPV", "PLV", "PLN")
$BaseUrl = "http://dadosabertos.camara.leg.br/arquivos"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$OutDir = Join-Path $Root "docs\data"
$OutFile = Join-Path $OutDir "proposicoes.json"

function Get-CsvFile {
  param(
    [string] $Kind,
    [int] $Year
  )

  $url = "$BaseUrl/$Kind/csv/$Kind-$Year.csv"
  $tmpFile = Join-Path ([System.IO.Path]::GetTempPath()) "$Kind-$Year.csv"
  if (-not (Test-Path $tmpFile)) {
    Write-Host "Baixando $url"
    & curl.exe -L --fail --silent --show-error --max-time 300 -o $tmpFile $url
    if ($LASTEXITCODE -ne 0) {
      throw "Falha ao baixar $url"
    }
  }
  return $tmpFile
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

function Get-PropositionId {
  param([object] $Row)

  $id = Get-FirstValue -Row $Row -Names @("idProposicao", "id")
  if ($id) {
    return $id
  }

  $uri = Get-FirstValue -Row $Row -Names @("uriProposicao", "uri")
  if ($uri -match "/proposicoes/(\d+)") {
    return $Matches[1]
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

$selectedRows = New-Object System.Collections.ArrayList
$selectedIds = New-Object System.Collections.Generic.HashSet[string]
$typeDescriptions = @{}
$monthlyTotals = @{}
$yearSet = New-Object System.Collections.Generic.HashSet[string]
foreach ($year in $Years) {
  [void] $yearSet.Add([string] $year)
}

foreach ($year in $Years) {
  $file = Get-CsvFile -Kind "proposicoes" -Year $year
  Write-Host "Selecionando proposicoes legislativas de $year com ementa"

  Import-Csv -Path $file -Delimiter ";" | ForEach-Object {
    $id = Get-PropositionId -Row $_
    $date = Get-DateOnly -Value (Get-FirstValue -Row $_ -Names @("dataApresentacao"))
    $ementa = Get-FirstValue -Row $_ -Names @("ementa")
    if (-not $id -or -not $date -or [string]::IsNullOrWhiteSpace($ementa)) {
      return
    }

    $siglaTipo = Get-FirstValue -Row $_ -Names @("siglaTipo")
    if (-not ($IncludedTypes -contains $siglaTipo)) {
      return
    }

    $presentationYear = $date.Substring(0, 4)
    if (-not $yearSet.Contains($presentationYear) -or $selectedIds.Contains($id)) {
      return
    }

    $month = $date.Substring(0, 7)
    if (-not $monthlyTotals.ContainsKey($month)) {
      $monthlyTotals[$month] = 0
    }
    $monthlyTotals[$month] += 1

    $descricaoTipo = Get-FirstValue -Row $_ -Names @("descricaoTipo")
    if ($siglaTipo -and $descricaoTipo -and -not $typeDescriptions.ContainsKey($siglaTipo)) {
      $typeDescriptions[$siglaTipo] = $descricaoTipo
    }

    [void] $selectedRows.Add($_)
    [void] $selectedIds.Add($id)
  }
}

$themesById = @{}
foreach ($year in $Years) {
  $file = Get-CsvFile -Kind "proposicoesTemas" -Year $year
  Write-Host "Lendo temas de $year"
  Import-Csv -Path $file -Delimiter ";" | ForEach-Object {
    $id = Get-PropositionId -Row $_
    if (-not $id -or -not $selectedIds.Contains($id)) {
      return
    }

    $theme = Get-FirstValue -Row $_ -Names @("tema", "temaPredominante", "codTema")
    if ($theme) {
      if (-not $themesById.ContainsKey($id)) {
        $themesById[$id] = New-Object System.Collections.Generic.HashSet[string]
      }
      [void] $themesById[$id].Add($theme)
    }
  }
}

$authorsById = @{}
foreach ($year in $Years) {
  $file = Get-CsvFile -Kind "proposicoesAutores" -Year $year
  Write-Host "Lendo autores de $year"
  Import-Csv -Path $file -Delimiter ";" | ForEach-Object {
    $id = Get-PropositionId -Row $_
    if (-not $id -or -not $selectedIds.Contains($id)) {
      return
    }

    $name = (Get-FirstValue -Row $_ -Names @("nomeAutor", "autor", "nome")).Trim()
    if ($name) {
      if (-not $authorsById.ContainsKey($id)) {
        $authorsById[$id] = New-Object System.Collections.ArrayList
      }

      $author = New-Object PSObject
      $author | Add-Member -MemberType NoteProperty -Name "nome" -Value $name
      $author | Add-Member -MemberType NoteProperty -Name "partido" -Value (Get-FirstValue -Row $_ -Names @("siglaPartidoAutor", "siglaPartido", "partido"))
      $author | Add-Member -MemberType NoteProperty -Name "uf" -Value (Get-FirstValue -Row $_ -Names @("siglaUFAutor", "siglaUF", "uf"))
      [void] $authorsById[$id].Add($author)
    }
  }
}

$propositions = New-Object System.Collections.ArrayList
foreach ($row in $selectedRows) {
  $id = Get-PropositionId -Row $row
  $yearValue = Get-FirstValue -Row $row -Names @("ano")
  if (-not $id -or -not $yearValue) {
    continue
  }

  $uniqueAuthors = New-Object System.Collections.ArrayList
  $seenAuthors = New-Object System.Collections.Generic.HashSet[string]
  if ($authorsById.ContainsKey($id)) {
    foreach ($author in $authorsById[$id]) {
      if ($seenAuthors.Add($author.nome)) {
        [void] $uniqueAuthors.Add($author)
      }
    }
  }

  $themes = @()
  if ($themesById.ContainsKey($id)) {
    $themes = @($themesById[$id] | Sort-Object)
  }

  $proposal = New-Object PSObject
  $proposal | Add-Member -MemberType NoteProperty -Name "id" -Value $id
  $proposal | Add-Member -MemberType NoteProperty -Name "siglaTipo" -Value (Get-FirstValue -Row $row -Names @("siglaTipo"))
  $proposal | Add-Member -MemberType NoteProperty -Name "numero" -Value (Get-FirstValue -Row $row -Names @("numero"))
  $proposal | Add-Member -MemberType NoteProperty -Name "ano" -Value ([int] $yearValue)
  $proposal | Add-Member -MemberType NoteProperty -Name "descricaoTipo" -Value (Get-FirstValue -Row $row -Names @("descricaoTipo"))
  $proposal | Add-Member -MemberType NoteProperty -Name "ementa" -Value (Get-FirstValue -Row $row -Names @("ementa"))
  $proposal | Add-Member -MemberType NoteProperty -Name "keywords" -Value @(Split-Keywords -Value (Get-FirstValue -Row $row -Names @("keywords", "indexacao")))
  $dataApresentacao = Get-DateOnly -Value (Get-FirstValue -Row $row -Names @("dataApresentacao"))
  $proposal | Add-Member -MemberType NoteProperty -Name "dataApresentacao" -Value $dataApresentacao
  $proposal | Add-Member -MemberType NoteProperty -Name "urlInteiroTeor" -Value (Get-FirstValue -Row $row -Names @("urlInteiroTeor", "linkInteiroTeor"))
  $proposal | Add-Member -MemberType NoteProperty -Name "temas" -Value $themes
  $proposal | Add-Member -MemberType NoteProperty -Name "autores" -Value @($uniqueAuthors.ToArray())
  [void] $propositions.Add($proposal)
}

$orderedPropositions = @($propositions | Sort-Object -Property @{ Expression = "dataApresentacao"; Descending = $true }, @{ Expression = "id"; Descending = $true })
$typeDescriptionsObject = New-Object PSObject
foreach ($key in ($typeDescriptions.Keys | Sort-Object)) {
  $typeDescriptionsObject | Add-Member -MemberType NoteProperty -Name $key -Value $typeDescriptions[$key]
}
$monthlyTotalsRows = @($monthlyTotals.Keys | Sort-Object | ForEach-Object {
  [ordered]@{ month = $_; count = $monthlyTotals[$_] }
})

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
[ordered]@{
  generatedAt = (Get-Date).ToUniversalTime().ToString("o")
  years = $Years
  selection = [ordered]@{
    strategy = "Universo de proposicoes legislativas com ementa no periodo"
    requiresEmenta = $true
    includedTypes = $IncludedTypes
  }
  source = "Dados Abertos da Camara dos Deputados"
  monthlyTotals = $monthlyTotalsRows
  typeDescriptions = $typeDescriptionsObject
  proposicoes = $orderedPropositions
} | ConvertTo-Json -Depth 12 -Compress | Set-Content -Encoding UTF8 -Path $OutFile

Write-Host "Geradas $($orderedPropositions.Count) proposicoes em $OutFile"
