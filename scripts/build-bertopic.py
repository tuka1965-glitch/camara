import json
import re
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

from bertopic import BERTopic
from sentence_transformers import SentenceTransformer
from sklearn.feature_extraction.text import CountVectorizer


ROOT = Path(__file__).resolve().parents[1]
INPUT_FILE = ROOT / "docs" / "data" / "proposicoes.json"
OUT_FILE = ROOT / "docs" / "data" / "bertopic-model.json"
MODEL_TYPES = {"PL", "PLP", "PEC", "PDL", "PRC", "MPV", "PLV", "PLN"}

STOPWORDS = {
    "sobre",
    "para",
    "pela",
    "pelo",
    "pelos",
    "pelas",
    "como",
    "dispoe",
    "dispõe",
    "altera",
    "alteracao",
    "alteração",
    "federal",
    "nacional",
    "brasil",
    "brasileiro",
    "brasileira",
    "providencias",
    "providências",
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
    "constituição",
    "codigo",
    "código",
    "artigo",
    "inciso",
    "paragrafo",
    "parágrafo",
    "redacao",
    "redação",
    "ambito",
    "âmbito",
    "uniao",
    "união",
    "estado",
    "municipio",
    "município",
    "publica",
    "pública",
    "publico",
    "público",
    "administracao",
    "administração",
}


def clean_text(value):
    return re.sub(r"\s+", " ", str(value or "")).strip()


def topic_label(topic_model, topic_id):
    terms = [term for term, _ in topic_model.get_topic(topic_id)[:6]]
    return ", ".join(terms[:4]) if terms else f"Tópico {topic_id}"


def main():
    data = json.loads(INPUT_FILE.read_text(encoding="utf-8-sig"))
    records = [
        item
        for item in data["proposicoes"]
        if item.get("siglaTipo") in MODEL_TYPES and clean_text(item.get("ementa"))
    ]
    docs = [
        clean_text(f"{item['ementa']} {'; '.join(item.get('keywords', []))}")
        for item in records
    ]

    embedding_model = SentenceTransformer("sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2")
    vectorizer = CountVectorizer(
        stop_words=sorted(STOPWORDS),
        ngram_range=(1, 3),
        min_df=2,
        max_df=0.6,
    )
    topic_model = BERTopic(
        language="multilingual",
        embedding_model=embedding_model,
        vectorizer_model=vectorizer,
        min_topic_size=6,
        nr_topics="auto",
        calculate_probabilities=False,
        verbose=True,
    )
    topics, _ = topic_model.fit_transform(docs)

    clusters = []
    for topic_id, count in Counter(topics).most_common():
        if topic_id == -1:
            continue
        members = [index for index, value in enumerate(topics) if value == topic_id]
        theme_counts = Counter()
        for index in members:
            theme_counts.update(records[index].get("temas", []))
        examples = [
            {
                "id": records[index]["id"],
                "sigla": f"{records[index]['siglaTipo']} {records[index]['numero']}/{records[index]['ano']}",
                "ementa": records[index]["ementa"],
            }
            for index in members[:5]
        ]
        clusters.append(
            {
                "label": topic_label(topic_model, topic_id),
                "topicId": int(topic_id),
                "count": int(count),
                "memberIds": [records[index]["id"] for index in members],
                "topTerms": [term for term, _ in topic_model.get_topic(topic_id)[:8]],
                "topThemes": [
                    {"name": name, "count": int(value)}
                    for name, value in theme_counts.most_common(5)
                ],
                "examples": examples,
            }
        )

    payload = {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "method": "BERTopic com embeddings multilingues sobre ementa + keywords oficiais",
        "corpus": {
            "documents": len(docs),
            "source": "docs/data/proposicoes.json",
            "includedTypes": sorted(MODEL_TYPES),
            "embeddingModel": "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2",
        },
        "clusters": clusters,
        "outliers": int(sum(1 for topic in topics if topic == -1)),
    }
    OUT_FILE.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"Gerados {len(clusters)} tópicos BERTopic em {OUT_FILE}")


if __name__ == "__main__":
    main()
