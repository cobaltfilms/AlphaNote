import Foundation

/// Évaluateur arithmétique sûr (descente récursive, jamais NSExpression).
///
/// Supporte : + - * / ^, parenthèses, pourcentage familier (« 50% of 200 »,
/// « 100 - 20% »), factorielle `5!`, fonctions usuelles (`sqrt`, `abs`,
/// `round`, `floor`, `ceil`, `ln`, `log`, `log2`, `exp`, `sin`, `cos`, `tan`,
/// `min`, `max`), la constante `pi`/`π`, la multiplication implicite
/// (`2(3+4)`, `3 pi`) et la virgule décimale (« 1,5 »).
///
/// Les mots inconnus (« 5 pommes + 3 ») sont ignorés : le calcul reste
/// tolérant aux unités et annotations. Un mot inconnu suivi d'une parenthèse
/// est une fonction inconnue → l'expression est rejetée.
final class MathEvaluator {

    // MARK: - API

    /// Évalue une expression. Retourne nil si elle n'est pas analysable.
    func evaluate(_ expression: String) -> Double? {
        let tokens = tokenize(normalize(expression))
        guard !tokens.isEmpty else { return nil }
        var pos = 0
        do {
            let result = try parseExpression(tokens, &pos)
            guard pos == tokens.count, result.isFinite else { return nil }
            return result
        } catch {
            return nil
        }
    }

    // MARK: - Jetons

    private enum Token: Equatable {
        case number(Double)
        /// Pourcentage littéral déjà divisé par 100 (« 20% » → 0.2) : relatif
        /// quand il est seul à droite d'un + ou d'un − (« 100 - 20% » = 80).
        case percentNumber(Double)
        case percent
        case factorial
        case `operator`(String)
        case lparen, rparen
        case comma
        case identifier(String)

        var isBinaryOperator: Bool {
            if case .operator = self { return true }
            return false
        }
    }

    private static let functions: [String: ([Double]) -> Double?] = [
        "sqrt": { a in a.count == 1 && a[0] >= 0 ? a[0].squareRoot() : nil },
        "abs": { a in a.count == 1 ? Swift.abs(a[0]) : nil },
        "round": { a in a.count == 1 ? a[0].rounded() : nil },
        "floor": { a in a.count == 1 ? a[0].rounded(.down) : nil },
        "ceil": { a in a.count == 1 ? a[0].rounded(.up) : nil },
        "ln": { a in a.count == 1 && a[0] > 0 ? Foundation.log(a[0]) : nil },
        "log": { a in a.count == 1 && a[0] > 0 ? Foundation.log10(a[0]) : nil },
        "log2": { a in a.count == 1 && a[0] > 0 ? Foundation.log2(a[0]) : nil },
        "exp": { a in a.count == 1 ? Foundation.exp(a[0]) : nil },
        "sin": { a in a.count == 1 ? Foundation.sin(a[0]) : nil },
        "cos": { a in a.count == 1 ? Foundation.cos(a[0]) : nil },
        "tan": { a in a.count == 1 ? Foundation.tan(a[0]) : nil },
        "min": { a in a.isEmpty ? nil : a.min() },
        "max": { a in a.isEmpty ? nil : a.max() }
    ]

    private static let constants: [String: Double] = [
        "pi": Double.pi,
        "π": Double.pi
    ]

    // MARK: - Normalisation

    private func normalize(_ input: String) -> String {
        var expression = input
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "**", with: "^")
            .replacingOccurrences(of: "−", with: "-")

        // Virgule décimale entre deux chiffres (« 1,5 »).
        expression = expression.replacingOccurrences(
            of: #"(?<=\d),(?=\d)"#, with: ".", options: .regularExpression
        )

        // « 2 x 3 » → « 2 * 3 » (x comme signe de multiplication).
        if let regex = try? NSRegularExpression(pattern: "(?<=\\d|\\)|%)\\s*[xX]\\s*(?=\\d|\\(|[A-Za-z_π])") {
            expression = regex.stringByReplacingMatches(
                in: expression,
                options: [],
                range: NSRange(expression.startIndex..., in: expression),
                withTemplate: "*"
            )
        }

        return expression
    }

    // MARK: - Tokenizer

    private func tokenize(_ input: String) -> [Token] {
        var raw: [Token] = []
        var number = ""
        var word = ""

        func flushNumber() {
            if !number.isEmpty, let value = Double(number) {
                raw.append(.number(value))
            }
            number = ""
        }

        func flushWord() {
            if !word.isEmpty {
                raw.append(.identifier(word.lowercased()))
            }
            word = ""
        }

        for ch in input {
            if ch.isNumber || ch == "." {
                flushWord()
                number.append(ch)
                continue
            }
            if ch.isLetter || ch == "_" || ch == "π" {
                flushNumber()
                word.append(ch)
                continue
            }

            flushNumber()
            flushWord()

            switch ch {
            case "%": raw.append(.percent)
            case "!": raw.append(.factorial)
            case "+", "*", "/", "^": raw.append(.operator(String(ch)))
            case "-": raw.append(.operator("-"))
            case "(": raw.append(.lparen)
            case ")": raw.append(.rparen)
            case ",", ";": raw.append(.comma)
            default: break // espaces, symboles monétaires, etc.
            }
        }
        flushNumber()
        flushWord()

        // « of » = multiplication ; mots inconnus ignorés ; fonctions et
        // constantes conservées.
        var cleaned: [Token] = []
        for (index, token) in raw.enumerated() {
            guard case let .identifier(name) = token else {
                cleaned.append(token)
                continue
            }
            if name == "of" {
                cleaned.append(.operator("*"))
            } else if Self.functions[name] != nil || Self.constants[name] != nil {
                cleaned.append(token)
            } else if index + 1 < raw.count, raw[index + 1] == .lparen {
                cleaned.append(token) // fonction inconnue → échec au parsing
            }
        }

        // « 50% » → 0.5, et « 50% 200 » → 0.5 * 200.
        var final: [Token] = []
        var index = 0
        while index < cleaned.count {
            let token = cleaned[index]
            if case .percent = token {
                if let last = final.indices.last, case let .number(value) = final[last] {
                    final[last] = .percentNumber(value / 100)
                }
                if index + 1 < cleaned.count {
                    switch cleaned[index + 1] {
                    case .number, .lparen: final.append(.operator("*"))
                    default: break
                    }
                }
            } else {
                final.append(token)
            }
            index += 1
        }

        return final
    }

    // MARK: - Analyse

    private func parseExpression(_ tokens: [Token], _ pos: inout Int) throws -> Double {
        var result = try parseTerm(tokens, &pos)
        while pos < tokens.count, case let .operator(op) = tokens[pos], op == "+" || op == "-" {
            pos += 1
            let rhsStart = pos
            let rhs = try parseTerm(tokens, &pos)
            var relative = false
            if pos == rhsStart + 1, case .percentNumber = tokens[rhsStart] { relative = true }
            let delta = relative ? result * rhs : rhs
            result = op == "+" ? result + delta : result - delta
        }
        return result
    }

    private func parseTerm(_ tokens: [Token], _ pos: inout Int) throws -> Double {
        var result = try parsePower(tokens, &pos)
        while pos < tokens.count {
            if case let .operator(op) = tokens[pos], op == "*" || op == "/" {
                pos += 1
                let rhs = try parsePower(tokens, &pos)
                result = op == "*" ? result * rhs : result / rhs
            } else if tokens[pos] == .lparen || isIdentifier(tokens[pos]) {
                // Multiplication implicite : « 2(3+4) », « 3 pi ».
                let rhs = try parsePower(tokens, &pos)
                result *= rhs
            } else {
                break
            }
        }
        return result
    }

    private func parsePower(_ tokens: [Token], _ pos: inout Int) throws -> Double {
        let base = try parseUnary(tokens, &pos)
        if pos < tokens.count, case .operator("^") = tokens[pos] {
            pos += 1
            let exponent = try parsePower(tokens, &pos) // associatif à droite
            return Foundation.pow(base, exponent)
        }
        return base
    }

    private func parseUnary(_ tokens: [Token], _ pos: inout Int) throws -> Double {
        if pos < tokens.count, case .operator("-") = tokens[pos] {
            pos += 1
            return -(try parseUnary(tokens, &pos))
        }
        if pos < tokens.count, case .operator("+") = tokens[pos] {
            pos += 1
            return try parseUnary(tokens, &pos)
        }
        return try parsePostfix(tokens, &pos)
    }

    private func parsePostfix(_ tokens: [Token], _ pos: inout Int) throws -> Double {
        var value = try parsePrimary(tokens, &pos)
        while pos < tokens.count, tokens[pos] == .factorial {
            pos += 1
            value = try factorial(value)
        }
        return value
    }

    private func parsePrimary(_ tokens: [Token], _ pos: inout Int) throws -> Double {
        guard pos < tokens.count else { throw ParseError.unexpectedEnd }

        switch tokens[pos] {
        case let .number(value):
            pos += 1
            return value

        case let .percentNumber(value):
            pos += 1
            return value

        case .lparen:
            pos += 1
            let result = try parseExpression(tokens, &pos)
            guard pos < tokens.count, tokens[pos] == .rparen else { throw ParseError.missingParen }
            pos += 1
            return result

        case let .identifier(name):
            pos += 1
            if let constant = Self.constants[name] {
                return constant
            }
            guard pos < tokens.count, tokens[pos] == .lparen else { throw ParseError.unknownIdentifier }
            pos += 1
            var arguments: [Double] = []
            if pos < tokens.count, tokens[pos] == .rparen {
                pos += 1
            } else {
                while true {
                    arguments.append(try parseExpression(tokens, &pos))
                    guard pos < tokens.count else { throw ParseError.missingParen }
                    if tokens[pos] == .comma {
                        pos += 1
                        continue
                    }
                    if tokens[pos] == .rparen {
                        pos += 1
                        break
                    }
                    throw ParseError.unexpectedToken
                }
            }
            guard let function = Self.functions[name], let value = function(arguments) else {
                throw ParseError.unknownIdentifier
            }
            return value

        default:
            throw ParseError.unexpectedToken
        }
    }

    private func factorial(_ value: Double) throws -> Double {
        guard value >= 0, value == value.rounded(), value <= 170 else { throw ParseError.unexpectedToken }
        var result = 1.0
        var n = 2.0
        while n <= value {
            result *= n
            n += 1
        }
        return result
    }

    private func isIdentifier(_ token: Token) -> Bool {
        if case .identifier = token { return true }
        return false
    }

    enum ParseError: Error {
        case unexpectedEnd
        case missingParen
        case unexpectedToken
        case unknownIdentifier
    }
}
