// Entraîne le classifieur de mode Core ML (macOS / iOS) avec Create ML.
//   swift ml/train_coreml.swift   → ml/build/AlphaNoteModeClassifier.mlmodel
import CreateML
import Foundation
import TabularData

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let train = try DataFrame(contentsOfCSVFile: root.appendingPathComponent("data/train.csv"))
let test = try DataFrame(contentsOfCSVFile: root.appendingPathComponent("data/test.csv"))

// Entropie maximale (régression logistique sur les mots) : sur quelques
// centaines de phrases courtes, elle bat nettement le transfert BERT d'Apple
// (98,5 % contre 89 % au test du 31/10/2026), pour un modèle minuscule.
let parameters = MLTextClassifier.ModelParameters(
    validation: .split(strategy: .automatic),
    algorithm: .maxEnt(revision: 1),
    language: .french
)
let model = try MLTextClassifier(trainingData: train, textColumn: "text", labelColumn: "label", parameters: parameters)

let metrics = model.evaluation(on: test, textColumn: "text", labelColumn: "label")
print(String(format: "Précision sur le jeu de test : %.1f %%", (1 - metrics.classificationError) * 100))

let out = root.appendingPathComponent("build")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
try model.write(to: out.appendingPathComponent("AlphaNoteModeClassifier.mlmodel"),
                metadata: MLModelMetadata(author: "AlphaNote", shortDescription: "Mode d'une demande : math, list, timer, code, plain.", version: "1"))
print("→ ml/build/AlphaNoteModeClassifier.mlmodel")
