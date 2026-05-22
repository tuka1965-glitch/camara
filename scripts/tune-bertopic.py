import json
import importlib.util
import math
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

from bertopic import BERTopic
from sentence_transformers import SentenceTransformer
from sklearn.feature_extraction.text import CountVectorizer

ROOT = Path(__file__).resolve().parents[1]
INPUT_FILE = ROOT / "docs" / "data" / "proposicoes.json"
OUT_FILE = ROOT / "docs" / "data" / "bertopic-tuning.json"
BUILD_SCRIPT = ROOT / "scripts" / "build-bertopic.py"

spec = importlib.util.spec_from_file_location("build_bertopic", BUILD_SCRIPT)
build_bertopic = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build_bertopic)

MODEL_TYPES = build_bertopic.MODEL_TYPES
STOPWORDS = build_bertopic.STOPWORDS
build_document = build_bertopic.build_document
clean_text = build_bertopic.clean_text

CONFIGS = [
    {"name": "balanced-v1", "min_topic_size": 8, "min_df": 3, "max_df": 0.5, "nr_topics": "auto"},
    {"name": "larger-topics", "min_topic_size": 10, "min_df": 3, "max_df": 0.5, "nr_topics": "auto"},
    {"name": "stricter-terms", "min_topic_size": 8, "min_df": 4, "max_df": 0.45, "nr_topics": "auto"},
    {"name": "twenty-topics", "min_topic_size": 8, "min_df": 3, "max_df": 0.5, "nr_topics": 20},
    {"name": "twenty-five-topics", "min_topic_size": 8, "min_df": 3, "max_df": 0.5, "nr_topics": 25},
]


def official_theme_metrics(records, topics):
    theme_set = sorted({theme for item in records for theme in item.get("temas", [])})
    if not theme_set:
        return {"weightedPurity": 0, "crossEntropyNats": 0, "perplexity": 1}

    global_counts = Counter()
    for index, topic in enumerate(topics):
        if topic != -1:
            global_counts.update(records[index].get("temas", []))

    alpha = 1.0
    assigned = 0
    purity_numerator = 0
    cross_entropy_sum = 0.0
    evaluated = 0

    for topic_id in sorted(set(topics)):
        if topic_id == -1:
            continue
        members = [index for index, value in enumerate(topics) if value == topic_id]
        theme_counts = Counter()
        for index in members:
            theme_counts.update(records[index].get("temas", []))
        assigned += len(members)
        purity_numerator += theme_counts.most_common(1)[0][1] if theme_counts else 0
        total_labels = sum(theme_counts.values())
        for index in members:
            doc_themes = [theme for theme in records[index].get("temas", []) if theme]
            if not doc_themes:
                continue
            evaluated += 1
            doc_cross_entropy = 0.0
            for theme in doc_themes:
                probability = (theme_counts[theme] + alpha) / (total_labels + alpha * len(theme_set))
                doc_cross_entropy += -math.log(probability) / len(doc_themes)
            cross_entropy_sum += doc_cross_entropy

    cross_entropy = cross_entropy_sum / evaluated if evaluated else 0
    return {
        "assignedDocuments": assigned,
        "evaluatedDocuments": evaluated,
        "weightedPurity": round(purity_numerator / assigned, 3) if assigned else 0,
        "crossEntropyNats": round(cross_entropy, 3),
        "perplexity": round(math.exp(cross_entropy), 2),
    }


def main():
    data = json.loads(INPUT_FILE.read_text(encoding="utf-8-sig"))
    records = [
        item
        for item in data["proposicoes"]
        if item.get("siglaTipo") in MODEL_TYPES and clean_text(item.get("ementa"))
    ]
    docs = [build_document(item) for item in records]
    embedding_model = SentenceTransformer("sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2")
    rows = []

    for config in CONFIGS:
        vectorizer = CountVectorizer(
            stop_words=sorted(STOPWORDS),
            ngram_range=(1, 3),
            min_df=config["min_df"],
            max_df=config["max_df"],
            token_pattern=r"(?u)\b[a-zA-Z][a-zA-Z-]{2,}\b",
        )
        topic_model = BERTopic(
            language="multilingual",
            embedding_model=embedding_model,
            vectorizer_model=vectorizer,
            min_topic_size=config["min_topic_size"],
            nr_topics=config["nr_topics"],
            calculate_probabilities=False,
            verbose=False,
        )
        topics, _ = topic_model.fit_transform(docs)
        metrics = official_theme_metrics(records, topics)
        rows.append(
            {
                **config,
                "clusters": len([topic for topic in set(topics) if topic != -1]),
                "outliers": sum(1 for topic in topics if topic == -1),
                **metrics,
            }
        )

    payload = {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "documents": len(docs),
        "configs": rows,
    }
    OUT_FILE.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"Gerado tuning BERTopic em {OUT_FILE}")


if __name__ == "__main__":
    main()
