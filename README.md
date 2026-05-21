# Camara

Prototipo estatico para acompanhar a producao legislativa da Camara dos Deputados,
com foco inicial nas proposicoes apresentadas em 2025 e 2026.

## O que o painel mostra

- volume de proposicoes por ano, mes, tipo e tema oficial;
- busca por ementa, palavras-chave, autor, sigla e numero;
- filtros por ano, tipo, tema e autor;
- lista detalhada de proposicoes com link para o inteiro teor;
- base preparada para evoluir para analise semantica com texto completo.

## Dados

Os dados sao baixados de:

- `https://dadosabertos.camara.leg.br/arquivos/proposicoes/csv/proposicoes-{ano}.csv`
- `https://dadosabertos.camara.leg.br/arquivos/proposicoesTemas/csv/proposicoesTemas-{ano}.csv`
- `https://dadosabertos.camara.leg.br/arquivos/proposicoesAutores/csv/proposicoesAutores-{ano}.csv`

Anos iniciais: 2025 e 2026. O gerador mantém apenas proposicoes com ementa,
pois a ementa sera o primeiro insumo para classificacao tematica e futuros
modelos BERT.

## Desenvolvimento local

```powershell
.\scripts\build-data.ps1
python -m http.server 8080 -d docs
```

Depois abra `http://localhost:8080`.

## GitHub Pages

O diretorio `docs/` pode ser publicado diretamente no GitHub Pages. O workflow
em `.github/workflows/update-data.yml` atualiza os dados diariamente e tambem
pode ser executado manualmente pela aba Actions.
