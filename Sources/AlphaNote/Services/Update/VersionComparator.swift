import Foundation

/// Comparateur de versions pour le canal de mise à jour.
///
/// Gère les versions stables ("1.2.3") et les pré-releases ("1.2.3b1",
/// "1.2.3-beta2"). Une release stable est toujours plus récente qu'une
/// pré-release de la même base ; deux pré-releases se comparent par leur
/// suffixe. Logique pure, testable sans réseau.
enum VersionComparator {
    struct Parsed: Equatable {
        let base: [Int]
        let pre: String?
    }

    static func parse(_ raw: String) -> Parsed {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") { s = String(s.dropFirst()) }

        var numeric = ""
        var index = s.startIndex
        while index < s.endIndex, s[index].isNumber || s[index] == "." {
            numeric.append(s[index])
            index = s.index(after: index)
        }
        let base = numeric
            .split(separator: ".")
            .map { Int($0) ?? 0 }
        let suffix = String(s[index...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return Parsed(base: base, pre: suffix.isEmpty ? nil : suffix)
    }

    private static func compareBase(_ a: [Int], _ b: [Int]) -> Int {
        let count = max(a.count, b.count)
        for i in 0..<count {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y ? 1 : -1 }
        }
        return 0
    }

    /// Vrai si `candidate` est strictement plus récent que `current`.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = parse(candidate)
        let b = parse(current)

        let baseOrder = compareBase(a.base, b.base)
        if baseOrder > 0 { return true }
        if baseOrder < 0 { return false }

        switch (a.pre, b.pre) {
        case (nil, .some): return true      // stable > pré-release
        case (.some, nil): return false     // pré-release < stable
        case (nil, nil): return false       // identique
        case let (x?, y?): return x > y     // pré-releases par suffixe
        }
    }
}
