# Classifieur de mode embarqué

Classe une demande de la barre de commande dans un mode (math, list, timer,
code, plain) sur l'appareil, sans serveur : JEV devient facultatif. Un seul
jeu d'exemples, deux modèles :

| Plateforme | Modèle | Entraînement | Livré dans |
|---|---|---|---|
| macOS, iOS | Create ML, entropie maximale (~20 Ko) | `swift ml/train_coreml.swift` | `Sources/AlphaNote/Resources/ML/AlphaNoteModeClassifier.coreml` (le .mlmodel renommé) |
| Android | Keras → TFLite (~1,6 Mo), jetons hachés | `ml/.venv/bin/python ml/train_tflite.py` | `Android/app/src/main/assets/alphanote_mode_classifier.tflite` |

```bash
python3 ml/make_dataset.py          # ml/data/{train,test}.csv (graine fixe)
python3 ml/jev_teacher.py           # optionnel : désaccords avec le serveur JEV
swift ml/train_coreml.swift && swift ml/eval_coreml.swift
uv venv --python 3.11 ml/.venv && uv pip install --python ml/.venv/bin/python tensorflow
ml/.venv/bin/python ml/train_tflite.py
```

Le découpage en jetons du modèle TFLite (`tokens()` dans `train_tflite.py`) est
réécrit à l'identique en Kotlin (`ModeTokenizer`) ; `ModeTokenizerTest.kt`
vérifie des vecteurs produits par le script. MediaPipe Model Maker n'est pas
utilisé : sa pile (tensorflow-text 2.15) n'existe pas pour Apple Silicon.

Résultats au 31/10/2026, sur les 203 phrases de test : Core ML 98,5 %, TFLite
97,5 %, ancien routeur par mots-clés 51,7 %.

Au 05/11/2026, alarmes à heure fixe ajoutées au mode timer (« réveille-moi à
7h30 », « alarme à 14h ») et pomodoro retiré : sur les 207 phrases de test,
Core ML 96,6 %, TFLite 98,1 %.
