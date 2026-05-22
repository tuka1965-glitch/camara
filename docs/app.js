const state = {
  data: null,
  filtered: [],
  topicModel: null,
  bertopicModel: null,
  activeClusterModel: "official",
};

const collator = new Intl.Collator("pt-BR");
const dateFormatter = new Intl.DateTimeFormat("pt-BR", { dateStyle: "medium" });
const monthFormatter = new Intl.DateTimeFormat("pt-BR", { month: "short", year: "numeric", timeZone: "UTC" });
const genericDescriptors = new Set([
  "alteracao",
  "criacao",
  "criterio",
  "diretrizes",
  "obrigatoriedade",
  "proibicao",
  "sustacao",
  "lei federal",
  "decreto legislativo",
  "lei",
  "programa",
  "dezembro",
  "pessoa",
  "servico",
  "servicos",
  "oficial",
  "parecer",
  "aprovacao",
  "submete",
  "constante",
  "congresso",
  "susta",
  "resolucao",
  "requerimento",
  "retirada",
  "pauta",
  "votacao",
  "nominal",
  "informacoes",
  "ministro",
  "ministra",
  "materia",
  "plenario",
  "comissao",
]);
const descriptorStopwords = new Set([
  "sobre",
  "para",
  "pela",
  "pelo",
  "pelos",
  "pelas",
  "como",
  "dispoe",
  "altera",
  "alteracao",
  "federal",
  "nacional",
  "brasil",
  "brasileiro",
  "brasileira",
  "providencias",
  "outras",
  "forma",
  "termos",
  "institui",
  "estabelece",
  "cria",
  "fica",
  "lei",
  "projeto",
  "decreto",
  "legislativo",
  "complementar",
  "constituicao",
  "codigo",
  "artigo",
  "inciso",
  "paragrafo",
  "redacao",
  "ambito",
  "uniao",
  "estado",
  "municipio",
  "publica",
  "publico",
  "administracao",
]);

function normalize(value) {
  return String(value ?? "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase();
}

function formatDate(value) {
  if (!value) return "sem data";
  const date = new Date(`${value}T00:00:00`);
  if (Number.isNaN(date.getTime())) return value;
  return dateFormatter.format(date);
}

function countBy(items, getter) {
  const map = new Map();
  for (const item of items) {
    const values = getter(item);
    for (const value of Array.isArray(values) ? values : [values]) {
      if (!value) continue;
      map.set(value, (map.get(value) ?? 0) + 1);
    }
  }
  return [...map.entries()].sort((a, b) => b[1] - a[1] || collator.compare(a[0], b[0]));
}

function setOptions(select, values, label) {
  select.innerHTML = [`<option value="">${label}</option>`]
    .concat(values.map((value) => `<option value="${escapeHtml(value)}">${escapeHtml(value)}</option>`))
    .join("");
}

function setLabeledOptions(select, entries, label) {
  select.innerHTML = [`<option value="">${label}</option>`]
    .concat(
      entries.map(
        ([value, text]) => `<option value="${escapeHtml(value)}">${escapeHtml(text)}</option>`,
      ),
    )
    .join("");
}

function escapeHtml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function cleanDescriptor(value) {
  return String(value ?? "")
    .trim()
    .replace(/^_+/, "")
    .replace(/[\.;:,\s]+$/g, "");
}

function descriptorTokens(value) {
  return normalize(value)
    .replace(/[^a-z0-9 ]+/g, " ")
    .split(/\s+/)
    .filter((token) => token.length >= 4 && !descriptorStopwords.has(token) && !/^\d+$/.test(token));
}

function informativeKeyword(value) {
  const display = cleanDescriptor(value);
  const normalized = normalize(display).replace(/[^a-z0-9 ]+/g, " ").replace(/\s+/g, " ").trim();
  const tokens = descriptorTokens(display);
  if (!display || !normalized || genericDescriptors.has(normalized)) return null;
  if (tokens.length < 2) return null;
  return display;
}

function countKeywords(items) {
  const map = new Map();
  for (const item of items) {
    for (const keyword of item.keywords) {
      const display = informativeKeyword(keyword);
      if (!display) continue;
      map.set(display, (map.get(display) ?? 0) + 1);
    }
  }
  return [...map.entries()].sort((a, b) => b[1] - a[1] || collator.compare(a[0], b[0]));
}

function renderSummary(items) {
  const themes = countBy(items, (item) => item.temas);
  const authors = countBy(items, (item) => item.autores.map((author) => author.nome));
  const withFullText = items.filter((item) => item.urlInteiroTeor).length;
  const cards = [
    ["Proposicoes", items.length.toLocaleString("pt-BR")],
    ["Temas oficiais", themes.length.toLocaleString("pt-BR")],
    ["Autores", authors.length.toLocaleString("pt-BR")],
    ["Com inteiro teor", withFullText.toLocaleString("pt-BR")],
    ["Tema lider", themes[0]?.[0] ?? "-"],
  ];

  document.querySelector("#summary").innerHTML = cards
    .map(
      ([label, value]) => `
        <article class="summary-card">
          <span>${escapeHtml(label)}</span>
          <strong title="${escapeHtml(value)}">${escapeHtml(value)}</strong>
        </article>
      `,
    )
    .join("");
}

function renderThemeRanking(items) {
  const themes = countBy(items, (item) => item.temas).slice(0, 12);
  const max = themes[0]?.[1] ?? 1;
  document.querySelector("#themes-list").innerHTML = themes
    .map(
      ([theme, count]) => `
        <button class="rank-item" type="button" data-theme="${escapeHtml(theme)}">
          <span class="rank-name" title="${escapeHtml(theme)}">${escapeHtml(theme)}</span>
          <span class="rank-count">${count.toLocaleString("pt-BR")}</span>
          <div class="bar"><span style="width:${Math.max(4, (count / max) * 100)}%"></span></div>
        </button>
      `,
    )
    .join("");

  document.querySelectorAll("#themes-list .rank-item").forEach((button) => {
    button.addEventListener("click", () => {
      document.querySelector("#theme-filter").value = button.dataset.theme;
      applyFilters();
    });
  });
}

function renderSubthemes(items) {
  const selectedTheme = document.querySelector("#theme-filter").value;
  const subthemes = countKeywords(items).slice(0, 18);
  const max = subthemes[0]?.[1] ?? 1;
  const context = selectedTheme
    ? `${subthemes.length} keywords em ${selectedTheme}`
    : "Selecione um tema para ver os descritores";

  document.querySelector("#subthemes-context").textContent = context;
  document.querySelector("#subthemes-list").innerHTML = selectedTheme
    ? subthemes
        .map(
          ([keyword, count]) => {
            const height = Math.max(4, Math.round((count / max) * 190));
            return `
            <button class="subtheme-bar" type="button" data-keyword="${escapeHtml(keyword)}" title="${escapeHtml(keyword)}: ${count}">
              <strong>${count.toLocaleString("pt-BR")}</strong>
              <span style="height:${height}px"></span>
              <em>${escapeHtml(keyword)}</em>
            </button>
          `;
          },
        )
        .join("") || `<p class="empty">Nao ha keywords oficiais para este recorte.</p>`
    : `<p class="empty">Escolha um tema no filtro ou na lista de temas oficiais.</p>`;

  document.querySelectorAll("#subthemes-list .subtheme-bar").forEach((button) => {
    button.addEventListener("click", () => {
      document.querySelector("#search").value = button.dataset.keyword;
      applyFilters();
    });
  });
}

function renderChart(items) {
  const months = new Map();
  for (const item of items) {
    if (!item.dataApresentacao) continue;
    const key = item.dataApresentacao.slice(0, 7);
    months.set(key, (months.get(key) ?? 0) + 1);
  }
  const entries = [...months.entries()].sort((a, b) => a[0].localeCompare(b[0]));
  const labels = entries.map(([key]) => monthFormatter.format(new Date(`${key}-01T00:00:00Z`)));
  const values = entries.map(([, count]) => count);
  const max = Math.max(...values, 1);
  const width = 760;
  const height = 300;
  const padding = { top: 24, right: 20, bottom: 46, left: 42 };
  const plotWidth = width - padding.left - padding.right;
  const plotHeight = height - padding.top - padding.bottom;
  const xStep = entries.length > 1 ? plotWidth / (entries.length - 1) : 0;
  const points = values.map((value, index) => {
    const x = padding.left + index * xStep;
    const y = padding.top + plotHeight - (value / max) * plotHeight;
    return { x, y, value, label: labels[index] };
  });
  const pointList = points.map((point) => `${point.x},${point.y}`).join(" ");
  const yTicks = [0, Math.round(max / 2), max];

  document.querySelector("#monthly-chart").innerHTML = `
    <svg viewBox="0 0 ${width} ${height}" role="img" aria-label="Serie mensal de proposicoes">
      ${yTicks
        .map((tick) => {
          const y = padding.top + plotHeight - (tick / max) * plotHeight;
          return `
            <line class="grid-line" x1="${padding.left}" y1="${y}" x2="${width - padding.right}" y2="${y}"></line>
            <text x="8" y="${y + 4}">${tick}</text>
          `;
        })
        .join("")}
      <polyline class="series-line" points="${pointList}"></polyline>
      ${points
        .map(
          (point, index) => `
            <circle class="series-point" cx="${point.x}" cy="${point.y}" r="4">
              <title>${escapeHtml(point.label)}: ${point.value}</title>
            </circle>
            <text x="${point.x}" y="${height - 18}" text-anchor="middle">${escapeHtml(labels[index].replace(" de ", "/"))}</text>
          `,
        )
        .join("")}
    </svg>
  `;
}

function renderPropositions(items) {
  document.querySelector("#result-count").textContent = `${items.length.toLocaleString("pt-BR")} resultados`;
  const topItems = items.slice(0, 80);
  const html = topItems
    .map((item) => {
      const autores = item.autores.map((author) => author.nome).join(", ") || "Autoria nao informada";
      const themes = item.temas.slice(0, 4).map((theme) => `<span class="chip">${escapeHtml(theme)}</span>`).join("");
      const keywords = item.keywords.slice(0, 5).map((keyword) => `<span class="chip">${escapeHtml(keyword)}</span>`).join("");
      return `
        <article class="proposition-card">
          <div class="proposition-title">
            <span class="badge">${escapeHtml(item.siglaTipo)} ${escapeHtml(item.numero)}/${escapeHtml(item.ano)}</span>
            <strong>${escapeHtml(item.descricaoTipo || item.siglaTipo)}</strong>
          </div>
          <p class="ementa">${escapeHtml(item.ementa || "Sem ementa disponivel.")}</p>
          <div class="meta-row">
            <span>${escapeHtml(formatDate(item.dataApresentacao))}</span>
            <span>${escapeHtml(autores)}</span>
            ${item.urlInteiroTeor ? `<a href="${escapeHtml(item.urlInteiroTeor)}" target="_blank" rel="noreferrer">Inteiro teor</a>` : ""}
          </div>
          ${themes || keywords ? `<div class="chip-row">${themes}${keywords}</div>` : ""}
        </article>
      `;
    })
    .join("");

  document.querySelector("#propositions").innerHTML =
    html || `<p class="empty">Nenhuma proposicao encontrada com os filtros atuais.</p>`;
}

function renderTopicClusters() {
  const container = document.querySelector("#clusters-list");
  const context = document.querySelector("#clusters-context");
  const tabs = document.querySelector("#cluster-tabs");
  const models = [
    ["official", "Descritores oficiais", state.topicModel],
    ["bertopic", "BERTopic", state.bertopicModel],
  ].filter(([, , model]) => model?.clusters?.length);
  const activeModel = models.find(([id]) => id === state.activeClusterModel)?.[2] ?? models[0]?.[2];

  tabs.innerHTML = models
    .map(
      ([id, label]) => `
        <button class="tab-button ${activeModel === (id === "official" ? state.topicModel : state.bertopicModel) ? "is-active" : ""}" type="button" data-model="${id}">
          ${escapeHtml(label)}
        </button>
      `,
    )
    .join("");
  document.querySelectorAll("#cluster-tabs .tab-button").forEach((button) => {
    button.addEventListener("click", () => {
      state.activeClusterModel = button.dataset.model;
      renderTopicClusters();
    });
  });

  if (!activeModel?.clusters?.length) {
    context.textContent = "Aguardando geracao do modelo";
    container.innerHTML = `<p class="empty">Ainda nao ha clusters gerados.</p>`;
    return;
  }

  context.textContent = `${activeModel.clusters.length} clusters; ${activeModel.corpus.documents.toLocaleString("pt-BR")} ementas`;
  container.innerHTML = activeModel.clusters
    .slice(0, 12)
    .map((cluster) => {
      const terms = cluster.topTerms.slice(0, 6).map((term) => `<span class="chip">${escapeHtml(term)}</span>`).join("");
      const themes = cluster.topThemes
        .slice(0, 3)
        .map((theme) => `${theme.name} (${theme.count})`)
        .join(", ");
      const example = cluster.examples[0]?.ementa ?? "";
      return `
        <article class="cluster-card">
          <div class="cluster-meta">${cluster.count.toLocaleString("pt-BR")} proposicoes</div>
          <h3>${escapeHtml(cluster.label)}</h3>
          <div class="chip-row">${terms}</div>
          <p>${escapeHtml(themes || "Sem tema oficial associado")}</p>
          <p>${escapeHtml(example)}</p>
        </article>
      `;
    })
    .join("");
}

function applyFilters() {
  const query = normalize(document.querySelector("#search").value);
  const year = document.querySelector("#year-filter").value;
  const type = document.querySelector("#type-filter").value;
  const theme = document.querySelector("#theme-filter").value;
  const author = document.querySelector("#author-filter").value;
  const normalizedAuthor = normalize(author);

  state.filtered = state.data.proposicoes.filter((item) => {
    if (year && String(item.ano) !== year) return false;
    if (type && item.siglaTipo !== type) return false;
    if (theme && !item.temas.includes(theme)) return false;
    if (normalizedAuthor && !item.autores.some((entry) => normalize(entry.nome).includes(normalizedAuthor))) return false;
    if (!query) return true;
    return item.searchText.includes(query);
  });

  renderSummary(state.filtered);
  renderThemeRanking(state.filtered);
  renderSubthemes(state.filtered);
  renderChart(state.filtered);
  renderPropositions(state.filtered);
}

function hydrateFilters(data) {
  const years = [...new Set(data.proposicoes.map((item) => String(item.ano)))].sort();
  const types = [...new Set(data.proposicoes.map((item) => item.siglaTipo).filter(Boolean))].sort(collator.compare);
  const themes = [...new Set(data.proposicoes.flatMap((item) => item.temas))].sort(collator.compare);
  const typeEntries = types.map((type) => {
    const description = data.typeDescriptions?.[type];
    return [type, description ? `${type} - ${description}` : type];
  });
  const authors = countBy(data.proposicoes, (item) => item.autores.map((author) => author.nome))
    .map(([name]) => name);

  setOptions(document.querySelector("#year-filter"), years, "Todos");
  setLabeledOptions(document.querySelector("#type-filter"), typeEntries, "Todos");
  setOptions(document.querySelector("#theme-filter"), themes, "Todos");
  document.querySelector("#author-options").innerHTML = authors
    .map((name) => `<option value="${escapeHtml(name)}"></option>`)
    .join("");

  document.querySelectorAll("input, select").forEach((element) => {
    element.addEventListener("input", applyFilters);
    element.addEventListener("change", applyFilters);
  });
}

async function main() {
  const [response, topicResponse, bertopicResponse] = await Promise.all([
    fetch("./data/proposicoes.json", { cache: "no-store" }),
    fetch("./data/topic-model.json", { cache: "no-store" }).catch(() => null),
    fetch("./data/bertopic-model.json", { cache: "no-store" }).catch(() => null),
  ]);
  const data = await response.json();
  state.topicModel = topicResponse?.ok ? await topicResponse.json() : null;
  state.bertopicModel = bertopicResponse?.ok ? await bertopicResponse.json() : null;
  state.data = {
    ...data,
    proposicoes: data.proposicoes.map((item) => ({
      ...item,
      searchText: normalize(
        [
          item.siglaTipo,
          item.numero,
          item.ano,
          item.ementa,
          item.descricaoTipo,
          item.keywords.join(" "),
          item.temas.join(" "),
          item.autores.map((author) => author.nome).join(" "),
        ].join(" "),
      ),
    })),
  };
  document.querySelector("#updated-at").textContent = `Atualizado em ${formatDate(data.generatedAt.slice(0, 10))}`;
  hydrateFilters(state.data);
  renderTopicClusters();
  applyFilters();
}

main().catch((error) => {
  document.querySelector("#updated-at").textContent = "Nao foi possivel carregar os dados.";
  document.querySelector("#propositions").innerHTML = `<p class="empty">${escapeHtml(error.message)}</p>`;
});
