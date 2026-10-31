"""Fait classer tout le jeu d'exemples par le serveur JEV (le « professeur »)
et liste les désaccords avec nos étiquettes, à relire à la main.

    python3 ml/jev_teacher.py [URL]   → ml/data/jev_labels.csv
"""
import csv, json, sys, urllib.request
from pathlib import Path

URL = (sys.argv[1] if len(sys.argv) > 1 else "http://100.95.198.127:8096") + "/v1/decision"
DATA = Path(__file__).parent / "data"
SCHEMA = {"mode": {"type": "enum", "choices": ["math", "list", "timer", "code", "plain"], "description": (
    "Le mode que la demande appelle.\n- math : la demande cherche un résultat chiffré — calcul, pourcentage, réduction, écart de prix, "
    "conversion d'unités ou de devises, ou une formule décrite en mots (aire, volume, mensualité, intérêts…).\n- list : la demande veut une liste, "
    "une check-list, des tâches, des courses, des ingrédients, ajouter des éléments à une liste, ou contient le lien d'une recette.\n- timer : la "
    "demande veut un minuteur, un compte à rebours, un chronomètre ou une session pomodoro.\n- code : la demande écrit, corrige ou range un snippet "
    "de code ou une commande.\n- plain : cas par défaut — une pensée, une question, du texte, une note qui ne correspond à aucun autre mode.")}}
INSTRUCTIONS = "Classe la demande de l'utilisateur dans un seul mode d'une note AlphaNote.\nRéponds uniquement selon le schéma, sans rédiger. En cas de doute, plain."

rows = []
for name in ("train", "test"):
    with open(DATA / f"{name}.csv", encoding="utf-8") as f:
        rows += [(name, r["text"], r["label"]) for r in csv.DictReader(f)]

out = []
for i in range(0, len(rows), 25):
    batch = rows[i:i + 25]
    body = json.dumps({"instructions": INSTRUCTIONS, "schema": SCHEMA, "contexts": [t for _, t, _ in batch], "temperature": 1.0}).encode()
    req = urllib.request.Request(URL, data=body, headers={"content-type": "application/json"})
    results = json.load(urllib.request.urlopen(req, timeout=120))["results"]
    for (split, text, label), res in zip(batch, results):
        out.append((split, text, label, res["decision"]["mode"], round(res["fields"]["mode"]["probability"], 3)))

with open(DATA / "jev_labels.csv", "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f); w.writerow(["split", "text", "label", "jev", "p"]); w.writerows(out)
agree = sum(1 for o in out if o[2] == o[3])
print(f"accord JEV : {agree}/{len(out)} ({100 * agree / len(out):.1f} %)")
for o in out:
    if o[2] != o[3]:
        print(f"  [{o[2]} → JEV {o[3]} {o[4]}] {o[1]}")
