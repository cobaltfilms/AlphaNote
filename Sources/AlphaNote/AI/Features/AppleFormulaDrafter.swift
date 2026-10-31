import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Rédaction de formules par le modèle d'Apple Intelligence, sur l'appareil
/// (Foundation Models, macOS / iOS 26, Mac M1+ / iPhone 15 Pro+). Même
/// consigne et mêmes garde-fous que la voie JEV (FormulaDraftFeature) ; la
/// génération guidée rend directement la liste de lignes, sans JSON à lire.
enum AppleFormulaDrafter {
    static let modelName = "Apple Intelligence"

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    static func draft(question: String) async -> JEVOutcome<[String]> {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            do {
                let session = LanguageModelSession(instructions: FormulaDraftFeature.systemPrompt)
                let response = try await session.respond(to: question, generating: GeneratedFormula.self,
                                                         options: GenerationOptions(temperature: 0))
                var lines = response.content.lignes
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                // Le modèle oublie parfois le « = » final : la dernière ligne est
                // toujours le résultat, on la marque (le calcul reste vérifié).
                if let last = lines.last, !last.hasSuffix("=") {
                    lines[lines.count - 1] = last + " ="
                }
                return lines.isEmpty ? .erreur("Apple Intelligence n'a pas rendu de formule.") : .ok(lines)
            } catch {
                return .erreur("Apple Intelligence n'a pas pu rédiger la formule.")
            }
        }
        #endif
        return .erreur("Apple Intelligence n'est pas disponible sur cet appareil.")
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, iOS 26.0, *)
@Generable
struct GeneratedFormula {
    @Guide(description: "Lignes de la note math : « nom: expression » pour les intermédiaires, la dernière se termine par « = ».")
    var lignes: [String]
}
#endif
