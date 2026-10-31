// Erreurs du modèle Core ML sur le jeu de test.  swift ml/eval_coreml.swift
import CoreML
import Foundation
import NaturalLanguage

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let compiled = try MLModel.compileModel(at: root.appendingPathComponent("build/AlphaNoteModeClassifier.mlmodel"))
let model = try NLModel(contentsOf: compiled)
let lines = try String(contentsOf: root.appendingPathComponent("data/test.csv"), encoding: .utf8).components(separatedBy: .newlines).filter { !$0.isEmpty }.dropFirst()
var ok = 0, total = 0
let start = Date()
for line in lines {
    guard let comma = line.lastIndex(of: ",") else { continue }
    var text = String(line[..<comma]); let label = String(line[line.index(after: comma)...])
    if text.hasPrefix("\""), text.hasSuffix("\"") { text = String(text.dropFirst().dropLast()).replacingOccurrences(of: "\"\"", with: "\"") }
    let predicted = model.predictedLabel(for: text) ?? "?"
    total += 1
    if predicted == label { ok += 1 } else { print("  [\(label) → \(predicted)] \(text)") }
}
print(String(format: "%d/%d justes, %.1f ms par phrase", ok, total, Date().timeIntervalSince(start) * 1000 / Double(total)))
