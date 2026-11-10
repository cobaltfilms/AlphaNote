import Foundation

/// Thème d'une note, pour ranger la liste par sujets.
///
/// Un thème choisi est une ligne du texte, comme un rappel :
///
///     thème : Recettes
///
/// Le texte se synchronise tel quel, donc le thème aussi, sans champ en plus.
/// Même format et mêmes règles que la version Android (`domain/NoteThemes.kt`).
///
/// Une note sans cette ligne reçoit un thème **proposé**, calculé sur l'appareil
/// (`ThemeSorter`) : jamais écrit dans la note, jamais envoyé sur le réseau.
enum NoteThemes {
    /// Section des notes qu'aucune règle ne range.
    static let none = "Sans thème"
    static let maxLength = 40

    private static let line = try! NSRegularExpression(
        pattern: #"^\s*th[eè]me\s*:\s*(.+?)\s*$"#,
        options: [.caseInsensitive]
    )

    static func isThemeLine(_ raw: String) -> Bool {
        line.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)) != nil
    }

    /// Thème écrit dans la note (dernière ligne « thème : … »), sinon nil.
    static func explicit(in content: String) -> String? {
        for raw in content.components(separatedBy: "\n").reversed() {
            guard let match = line.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
                  let range = Range(match.range(at: 1), in: raw) else { continue }
            let name = normalized(String(raw[range]))
            if !name.isEmpty { return name }
        }
        return nil
    }

    /// Nom présentable : espaces resserrés, longueur bornée.
    static func normalized(_ name: String) -> String {
        let collapsed = name.split(whereSeparator: { $0 == " " || $0 == "\t" || $0.isNewline }).joined(separator: " ")
        return String(collapsed.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
    }

    /// Clé de comparaison : « Recettes », « recettes » et « RECETTES » sont un seul thème.
    static func key(_ name: String) -> String {
        normalized(name).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR")).lowercased()
    }

    static func removingTheme(from content: String) -> String {
        content.components(separatedBy: "\n").filter { !isThemeLine($0) }.joined(separator: "\n")
    }

    /// Écrit (ou retire, si `theme` est nil ou vide) la ligne de thème. Elle se
    /// place en fin de texte, avant les pièces jointes qui ferment la note.
    static func settingTheme(_ theme: String?, in content: String) -> String {
        var lines = removingTheme(from: content).components(separatedBy: "\n")
        let name = theme.map(normalized) ?? ""
        guard !name.isEmpty else { return lines.joined(separator: "\n") }

        var tail: [String] = []
        while let last = lines.last, NoteAttachments.isImageLine(last) || last.trimmingCharacters(in: .whitespaces).isEmpty {
            if NoteAttachments.isImageLine(last) { tail.insert(last, at: 0) }
            lines.removeLast()
        }
        lines.append("thème : \(name)")
        return (lines + tail).joined(separator: "\n")
    }

    /// Texte utile au classement : sans en-tête de mode, thème, rappels ni pièces jointes.
    static func classifiableText(title: String, content: String) -> (title: String, body: String) {
        var lines = content.components(separatedBy: "\n").filter {
            !isThemeLine($0) && !NoteAttachments.isImageLine($0)
                && !$0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("rappel ")
        }
        if let first = lines.first, EditorTextRules.isModeHeader(first.trimmingCharacters(in: .whitespaces)) {
            let header = first.trimmingCharacters(in: .whitespaces)
            lines.removeFirst()
            // « list: courses » : ce qui suit le mot-clé sert de titre.
            if let colon = header.firstIndex(of: ":") {
                lines.insert(String(header[header.index(after: colon)...]), at: 0)
            }
        }
        let explicitTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = lines.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        return (explicitTitle.isEmpty ? firstLine : explicitTitle, lines.joined(separator: "\n"))
    }

    // MARK: - Sections de la liste

    struct Section: Equatable {
        let theme: String
        let noteUUIDs: [String]
    }

    /// Notes regroupées par thème, dans l'ordre reçu à l'intérieur d'un thème.
    /// Thèmes par ordre alphabétique, « Sans thème » en dernier.
    static func sections(noteUUIDs: [String], themes: [String: String]) -> [Section] {
        var order: [String] = []
        var names: [String: String] = [:]
        var members: [String: [String]] = [:]
        for uuid in noteUUIDs {
            let name = themes[uuid] ?? none
            let themeKey = key(name)
            if members[themeKey] == nil {
                order.append(themeKey)
                names[themeKey] = name
            }
            members[themeKey, default: []].append(uuid)
        }
        let noneKey = key(none)
        let sorted = order.filter { $0 != noneKey }.sorted() + (order.contains(noneKey) ? [noneKey] : [])
        return sorted.map { Section(theme: names[$0] ?? none, noteUUIDs: members[$0] ?? []) }
    }
}

/// Classement local et déterministe des notes par thème — aucune IA, aucun
/// réseau, même résultat sur chaque appareil (port Android : `ThemeSorter.kt`).
///
/// Pour une note sans thème écrit, dans l'ordre :
/// 1. **par l'exemple** : elle ressemble (mots pondérés TF-IDF, cosinus) aux
///    notes qui portent déjà un thème écrit — ranger quelques notes à la main
///    apprend le thème aux autres ;
/// 2. **par le vocabulaire** : un catalogue de thèmes courants, chacun avec ses
///    mots (français et anglais) ;
/// 3. **par la forme** : une note en mode `code`, ou faite surtout de lignes de
///    terminal ou de code, va dans « Informatique » ;
/// 4. sinon elle reste « Sans thème » : pas de classement forcé.
enum ThemeSorter {
    struct Item {
        let uuid: String
        let title: String
        let content: String
        let keyword: String

        init(uuid: String, title: String, content: String, keyword: String) {
            self.uuid = uuid
            self.title = title
            self.content = content
            self.keyword = keyword
        }
    }

    /// Ressemblance minimale avec les notes d'un thème pour le rejoindre.
    static let exampleThreshold = 0.22
    /// Points du catalogue à réunir : un mot compte 1, un mot du titre 2. Trois
    /// points = trois mots, ou un mot du titre et un autre : un seul mot ne suffit pas.
    static let catalogThreshold = 3
    /// Part des lignes « de terminal ou de code » qui fait une note technique.
    static let codeLineShare = 0.4

    /// uuid → thème (écrit ou proposé). Une note absente n'a pas de thème.
    static func assign(_ items: [Item]) -> [String: String] {
        var result: [String: String] = [:]
        var pending: [(item: Item, title: [String], body: [String])] = []
        var examples: [String: (name: String, vectors: [[String: Double]])] = [:]

        let prepared = items.map { item -> (Item, [String], [String], String?) in
            let text = NoteThemes.classifiableText(title: item.title, content: item.content)
            return (item, tokens(text.title), tokens(text.body), NoteThemes.explicit(in: item.content))
        }

        // Fréquence documentaire sur toutes les notes.
        var documentFrequency: [String: Int] = [:]
        for (_, title, body, _) in prepared {
            for token in Set(title + body) { documentFrequency[token, default: 0] += 1 }
        }
        let count = Double(prepared.count)
        func vector(_ title: [String], _ body: [String]) -> [String: Double] {
            var weights: [String: Double] = [:]
            for token in body { weights[token, default: 0] += 1 }
            for token in title { weights[token, default: 0] += 1 }
            for (token, frequency) in weights {
                let idf = log((count + 1) / (Double(documentFrequency[token] ?? 0) + 1)) + 1
                weights[token] = (1 + log(frequency)) * idf
            }
            return normalize(weights)
        }

        for (item, title, body, explicit) in prepared {
            if let explicit {
                result[item.uuid] = explicit
                let themeKey = NoteThemes.key(explicit)
                var entry = examples[themeKey] ?? (explicit, [])
                entry.vectors.append(vector(title, body))
                examples[themeKey] = entry
            } else {
                pending.append((item, title, body))
            }
        }

        // Centre de chaque thème appris, dans un ordre stable.
        let centroids: [(name: String, vector: [String: Double])] = examples.keys.sorted().map { themeKey in
            let entry = examples[themeKey]!
            var sum: [String: Double] = [:]
            for vector in entry.vectors {
                for (token, weight) in vector { sum[token, default: 0] += weight }
            }
            return (entry.name, normalize(sum))
        }

        for (item, title, body) in pending {
            if title.isEmpty && body.isEmpty { continue }
            let own = vector(title, body)
            var best: (name: String, score: Double)?
            for centroid in centroids {
                let score = dot(own, centroid.vector)
                if score >= exampleThreshold, score > (best?.score ?? 0) { best = (centroid.name, score) }
            }
            if let best {
                result[item.uuid] = best.name
            } else if let name = catalogTheme(title: title, body: body) {
                // Un thème appris du même nom garde son orthographe.
                result[item.uuid] = examples[NoteThemes.key(name)]?.name ?? name
            } else if item.keyword == "code" || looksLikeCode(item.content) {
                result[item.uuid] = examples[NoteThemes.key(codeTheme)]?.name ?? codeTheme
            }
        }
        return result
    }

    /// Thème du catalogue pour un texte seul (sans apprentissage par l'exemple).
    static func catalogTheme(title: String, content: String) -> String? {
        let text = NoteThemes.classifiableText(title: title, content: content)
        return catalogTheme(title: tokens(text.title), body: tokens(text.body))
    }

    private static func catalogTheme(title: [String], body: [String]) -> String? {
        let titleSet = Set(title)
        let all = titleSet.union(body)
        var best: (name: String, score: Int)?
        for theme in catalog {
            var score = 0
            for word in theme.words where all.contains(word) {
                score += titleSet.contains(word) ? 2 : 1
            }
            if score >= catalogThreshold, score > (best?.score ?? 0) { best = (theme.name, score) }
        }
        return best?.name
    }

    // MARK: - Forme

    private static let codeLine = try! NSRegularExpression(
        pattern: #"^\s*[$#>]\s|\s--?[a-z][a-z0-9-]+|/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+|[{};]\s*$|[A-Za-z_]+\(.*\)|^\s*[A-Za-z_]+=\S|\[[ 0-9.:]+\]|\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b"#
    )

    /// Vrai quand au moins deux lignes, et `codeLineShare` des lignes non vides,
    /// ont l'allure d'une commande, d'un journal ou de code.
    static func looksLikeCode(_ content: String) -> Bool {
        let lines = content.components(separatedBy: "\n").filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty && !NoteThemes.isThemeLine($0) && !NoteAttachments.isImageLine($0)
        }
        guard lines.count >= 2 else { return false }
        let matching = lines.filter { codeLine.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }.count
        return matching >= 2 && Double(matching) >= Double(lines.count) * codeLineShare
    }

    // MARK: - Mots

    /// Mots utiles : minuscules, sans accents, 3 lettres au moins, pluriels
    /// simples ramenés au singulier, mots vides retirés.
    static func tokens(_ text: String) -> [String] {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR")).lowercased()
        return folded.split { !$0.isLetter }.compactMap { raw in
            let word = String(raw)
            let stemmed = stem(word)
            return stemmed.count >= 3 && !stopWords.contains(word) && !stopWords.contains(stemmed) ? stemmed : nil
        }
    }

    static func stem(_ word: String) -> String {
        guard word.count > 3, let last = word.last, last == "s" || last == "x" else { return word }
        return String(word.dropLast())
    }

    private static func normalize(_ vector: [String: Double]) -> [String: Double] {
        let norm = sqrt(vector.values.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return vector }
        return vector.mapValues { $0 / norm }
    }

    private static func dot(_ lhs: [String: Double], _ rhs: [String: Double]) -> Double {
        let (small, large) = lhs.count <= rhs.count ? (lhs, rhs) : (rhs, lhs)
        // Somme dans un ordre stable : le même score sur chaque appareil.
        return small.keys.sorted().reduce(0) { $0 + (small[$1] ?? 0) * (large[$1] ?? 0) }
    }

    // MARK: - Catalogue

    struct CatalogTheme {
        let name: String
        let words: Set<String>

        init(_ name: String, _ words: String) {
            self.name = name
            self.words = Set(ThemeSorter.tokens(words))
        }
    }

    static let codeTheme = "Informatique"

    /// Les rayons : peu nombreux et larges, les mêmes que ceux proposés au
    /// serveur JEV (`ThemeClassificationFeature`). L'ordre départage les égalités.
    static let catalog: [CatalogTheme] = [
        CatalogTheme("Cuisine", """
            recette ingredient cuisson four farine beurre sucre oeuf levure oignon ail creme cuillere gramme \
            prechauffer melanger cuire poele casserole sauce gateau tarte soupe poulet mijoter eplucher hacher \
            marinade dessert plat entree vinaigrette bouillon recipe bake flour butter sugar cook oven tablespoon \
            teaspoon simmer ingredients courses supermarche panier delhaize colruyt carrefour lidl aldi \
            groceries epicerie pain fromage legume fruit yaourt boucherie boulangerie
            """),
        CatalogTheme("Image & son", """
            tournage montage camera rush etalonnage davinci timeline scenario storyboard casting cadrage codec \
            prores lut dcp trepied drone focale diaphragme realisateur monteur etalonneur shooting footage \
            grading mixage generique mastering
            """),
        CatalogTheme("Argent & papiers", """
            banque iban virement facture impot tva salaire budget depense remboursement pret credit loyer \
            assurance paiement comptable comptabilite fiscal epargne invoice tax bank payment montant solde \
            echeance mensualite devis contrat client prestataire fournisseur administration commune formulaire \
            attestation certificat permis immatriculation notaire avocat identite declaration guichet \
            prefecture mairie justificatif
            """),
        CatalogTheme("Vie perso", """
            medecin docteur ordonnance medicament pharmacie dentiste hopital symptome vaccin mutuelle kine \
            voyage vol avion train hotel reservation billet valise passeport itineraire aeroport airbnb \
            vacances camping randonnee musee plage maison appartement travaux peinture plombier electricien \
            meuble jardin demenagement bricolage ikea chauffage livre serie podcast album musique roman \
            cinema concert exposition spectacle theatre cadeau anniversaire noel fete mariage naissance \
            famille ecole enfant
            """),
        CatalogTheme(codeTheme, """
            serveur server ssh docker git python swift kotlin script api bug linux terminal install config \
            database sql json token regex compile build deploy backup nas routeur dns javascript html css \
            function variable kernel sudo bash kubectl compose container snapshot proxmox nginx yaml npm pip \
            curl chmod mount ubuntu debian driver gpu nvidia cuda dataset error failed systemctl daemon \
            firmware firewall vlan subnet localhost password login identifiant wifi username licence serial
            """),
    ]

    static let stopWords: Set<String> = [
        "les", "des", "une", "est", "pour", "que", "qui", "dans", "sur", "pas", "plus", "par", "avec", "son",
        "ses", "aux", "mes", "tes", "nos", "vos", "leur", "mon", "ton", "notre", "votre", "cette", "ces",
        "elle", "ils", "elles", "nous", "vous", "mais", "donc", "car", "comme", "tout", "tous", "toute",
        "etre", "avoir", "fait", "faire", "sont", "ont", "ete", "aussi", "tres", "bien", "sans", "sous",
        "entre", "vers", "chez", "puis", "alors", "quand", "dont", "cela", "ceci", "celui", "celle",
        "the", "and", "for", "that", "with", "this", "from", "are", "was", "were", "have", "has", "had",
        "not", "but", "you", "your", "they", "them", "their", "will", "would", "can", "could", "should",
        "what", "when", "where", "which", "who", "how", "all", "any", "its", "our", "out", "about", "into",
        "http", "https", "www", "com",
    ]
}
