import Foundation

/// Sélectionne, dans un paquet d'update décompressé, le bundle qui est bien
/// CETTE application, et prouve son identité avant qu'il puisse être installé.
///
/// Faire correspondre le seul nom de fichier ne suffit pas : on copie le résultat
/// par-dessus l'app en cours d'exécution. Un paquet qui contiendrait un bundle
/// du bon nom mais d'un autre identifiant doit être un échec franc, jamais un
/// remplacement silencieux. Logique pure, testable sans I/O.
enum UpdateBundleSelector {
    struct Candidate: Equatable {
        let name: String
        let bundleIdentifier: String?
    }

    enum Failure: Equatable {
        case noBundleFound
        case identityMismatch(found: String?)
        case unknownRunningIdentity
    }

    enum Outcome: Equatable {
        case success(candidateIndex: Int)
        case failure(Failure)
    }

    static func select(from candidates: [Candidate],
                       expectedName: String,
                       runningIdentifier: String?) -> Outcome {
        let matching = candidates.enumerated().filter { $0.element.name == expectedName }
        guard !matching.isEmpty else {
            return .failure(.noBundleFound)
        }
        guard let running = runningIdentifier else {
            return .failure(.unknownRunningIdentity)
        }
        for entry in matching where entry.element.bundleIdentifier == running {
            return .success(candidateIndex: entry.offset)
        }
        return .failure(.identityMismatch(found: matching.first?.element.bundleIdentifier))
    }
}
