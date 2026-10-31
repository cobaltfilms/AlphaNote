"""Entraîne le classifieur de mode TFLite (Android) sur le même jeu que Create ML.

MediaPipe Model Maker n'a pas de roues Apple Silicon (tensorflow-text 2.15) :
le modèle est donc un petit réseau Keras, exporté en TFLite. La découpe en
jetons se fait hors du modèle, à l'identique en Kotlin (ModeTokenizer.kt) :
mots et trigrammes de caractères hachés (FNV-1a 32 bits) dans BUCKETS cases,
donc aucun vocabulaire à embarquer, et les fautes de frappe gardent des
trigrammes connus.

    ml/.venv/bin/python ml/train_tflite.py
      → ml/build/alphanote_mode_classifier.tflite
"""
import csv
import json
import re
import unicodedata
from pathlib import Path

import numpy as np
import tensorflow as tf

ROOT = Path(__file__).parent
LABELS = ["code", "list", "math", "plain", "timer"]
BUCKETS = 8192
SEQ_LEN = 128
tf.keras.utils.set_random_seed(20261031)


def fnv1a(text: str) -> int:
    h = 0x811C9DC5
    for byte in text.encode("utf-8"):
        h ^= byte
        h = (h * 0x01000193) & 0xFFFFFFFF
    return h


def tokens(text: str) -> list[int]:
    """Identifiants 1…BUCKETS (0 = remplissage). Même algorithme en Kotlin."""
    folded = "".join(c for c in unicodedata.normalize("NFD", text.lower()) if unicodedata.category(c) != "Mn")
    words = re.findall(r"[a-z0-9]+|[^\sa-z0-9]", folded)
    ids = []
    for word in words:
        ids.append(fnv1a("w:" + word) % BUCKETS + 1)
        padded = "<" + word + ">"
        if len(word) > 1:
            ids += [fnv1a("t:" + padded[i:i + 3]) % BUCKETS + 1 for i in range(len(padded) - 2)]
    ids = ids[:SEQ_LEN]
    return ids + [0] * (SEQ_LEN - len(ids))


def load(name):
    with open(ROOT / f"data/{name}.csv", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    x = np.array([tokens(r["text"]) for r in rows], dtype=np.int32)
    y = np.array([LABELS.index(r["label"]) for r in rows], dtype=np.int32)
    return rows, x, y


_, x_train, y_train = load("train")
test_rows, x_test, y_test = load("test")

inputs = tf.keras.Input(shape=(SEQ_LEN,), dtype="int32")
embedded = tf.keras.layers.Embedding(BUCKETS + 1, 48)(inputs)
# Moyenne sur les vrais jetons seulement (masque des zéros de remplissage).
mask = tf.keras.layers.Lambda(lambda t: tf.cast(tf.not_equal(t, 0), tf.float32)[..., None])(inputs)
summed = tf.keras.layers.Lambda(lambda a: tf.reduce_sum(a[0] * a[1], axis=1) / tf.maximum(tf.reduce_sum(a[1], axis=1), 1.0))([embedded, mask])
hidden = tf.keras.layers.Dense(48, activation="relu")(tf.keras.layers.Dropout(0.2)(summed))
outputs = tf.keras.layers.Dense(len(LABELS), activation="softmax")(hidden)
model = tf.keras.Model(inputs, outputs)
model.compile(optimizer=tf.keras.optimizers.Adam(0.005), loss="sparse_categorical_crossentropy", metrics=["accuracy"])
model.fit(x_train, y_train, epochs=60, batch_size=16, validation_split=0.1, verbose=0)

predicted = model.predict(x_test, verbose=0).argmax(axis=1)
correct = int((predicted == y_test).sum())
print(f"Précision sur le jeu de test : {100 * correct / len(y_test):.1f} % ({correct}/{len(y_test)})")
for row, p in zip(test_rows, predicted):
    if LABELS[p] != row["label"]:
        print(f"  [{row['label']} → {LABELS[p]}] {row['text']}")

converter = tf.lite.TFLiteConverter.from_keras_model(model)
out = ROOT / "build"
out.mkdir(exist_ok=True)
(out / "alphanote_mode_classifier.tflite").write_bytes(converter.convert())

# Vecteur commun : Kotlin doit produire exactement ces jetons et cette décision.
sample = "Combien font 3 pizzas à 12,50 € ?"
probs = model.predict(np.array([tokens(sample)], dtype=np.int32), verbose=0)[0]
(out / "tflite_vector.json").write_text(json.dumps({
    "text": sample, "tokens": [t for t in tokens(sample) if t], "label": LABELS[int(probs.argmax())],
    "labels": LABELS, "buckets": BUCKETS, "seq_len": SEQ_LEN}, ensure_ascii=False, indent=1))
print("→ ml/build/alphanote_mode_classifier.tflite")
