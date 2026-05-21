const state = {
  data: null,
  filtered: [],
};

const collator = new Intl.Collator("pt-BR");
const dateFormatter = new Intl.DateTimeFormat("pt-BR", { dateStyle: "medium" });
const monthFormatter = new Intl.DateTimeFormat("pt-BR", { month: "short", year: "numeric", timeZone: "UTC" });

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
  const subthemes = countBy(items, (item) => item.keywords).slice(0, 30);
  const context = selectedTheme
    ? `${subthemes.length} keywords em ${selectedTheme}`
    : "Selecione um tema para ver os descritores";

  document.querySelector("#subthemes-context").textContent = context;
  document.querySelector("#subthemes-list").innerHTML = selectedTheme
    ? subthemes
        .map(
          ([keyword, count]) => `
            <button class="subtheme-chip" type="button" data-keyword="${escapeHtml(keyword)}">
              ${escapeHtml(keyword)}
              <strong>${count.toLocaleString("pt-BR")}</strong>
            </button>
          `,
        )
        .join("") || `<p class="empty">Nao ha keywords oficiais para este recorte.</p>`
    : `<p class="empty">Escolha um tema no filtro ou na lista de temas oficiais.</p>`;

  document.querySelectorAll("#subthemes-list .subtheme-chip").forEach((button) => {
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
  document.querySelector("#monthly-chart").innerHTML = entries
    .map((entry, index) => {
      const value = values[index];
      const height = Math.max(4, Math.round((value / max) * 230));
      return `
        <div class="month-bar" title="${escapeHtml(labels[index])}: ${value}">
          <strong>${value}</strong>
          <span style="height:${height}px"></span>
          <em>${escapeHtml(labels[index])}</em>
        </div>
      `;
    })
    .join("");
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

function applyFilters() {
  const query = normalize(document.querySelector("#search").value);
  const year = document.querySelector("#year-filter").value;
  const type = document.querySelector("#type-filter").value;
  const theme = document.querySelector("#theme-filter").value;
  const author = document.querySelector("#author-filter").value;

  state.filtered = state.data.proposicoes.filter((item) => {
    if (year && String(item.ano) !== year) return false;
    if (type && item.siglaTipo !== type) return false;
    if (theme && !item.temas.includes(theme)) return false;
    if (author && !item.autores.some((entry) => entry.nome === author)) return false;
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
  setOptions(document.querySelector("#author-filter"), authors, "Todos");

  document.querySelectorAll("input, select").forEach((element) => {
    element.addEventListener("input", applyFilters);
    element.addEventListener("change", applyFilters);
  });
}

async function main() {
  const response = await fetch("./data/proposicoes.json", { cache: "no-store" });
  const data = await response.json();
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
  applyFilters();
}

main().catch((error) => {
  document.querySelector("#updated-at").textContent = "Nao foi possivel carregar os dados.";
  document.querySelector("#propositions").innerHTML = `<p class="empty">${escapeHtml(error.message)}</p>`;
});
