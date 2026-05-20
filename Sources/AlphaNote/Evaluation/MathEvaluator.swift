import Foundation

/// Safe recursive-descent math evaluator — no NSExpression.
/// Supports: +, -, *, /, ^, parentheses, colloquial percent.
final class MathEvaluator {

    // MARK: - Public API

    /// Evaluate a math expression. Returns nil if it can't be parsed.
    func evaluate(_ expression: String) -> Double? {
        let tokens = tokenize(expression)
        guard !tokens.isEmpty else { return nil }
        var pos = 0
        do {
            let result = try parseExpression(tokens, &pos)
            return pos == tokens.count ? result : nil
        } catch {
            return nil
        }
    }

    // MARK: - Token Types

    private enum Token: Equatable {
        case number(Double)
        case percent          // %
        case `operator`(String) // + - * / ^
        case lparen, rparen
        case identifier(String) // for future variable support
    }

    // MARK: - Tokenizer

    private func tokenize(_ input: String) -> [Token] {
        var tokens: [Token] = []
        var chars = input[...].unicodeScalars
        var buffer = ""

        func flushNumber() {
            if let val = Double(buffer) {
                tokens.append(.number(val))
            }
            buffer = ""
        }

        while let ch = chars.popFirst() {
            switch ch {
            case "0"..."9", ".": // negative handled by parser
                buffer.append(Character(ch))
            case "%":
                if !buffer.isEmpty { flushNumber() }
                tokens.append(.percent)
            case "+", "*", "/":
                if !buffer.isEmpty { flushNumber() }
                tokens.append(.operator(String(ch)))
            case "^":
                if !buffer.isEmpty { flushNumber() }
                tokens.append(.operator("^"))
            case "-":
                // Distinguish minus sign from negative number
                if !buffer.isEmpty {
                    flushNumber()
                    tokens.append(.operator("-"))
                } else if tokens.last == .number(0) || tokens.last == .rparen || tokens.last != nil {
                    tokens.append(.operator("-"))
                } else {
                    buffer.append(Character(ch))
                }
            case "(":
                if !buffer.isEmpty { flushNumber() }
                tokens.append(.lparen)
            case ")":
                if !buffer.isEmpty { flushNumber() }
                tokens.append(.rparen)
            case " ", "\t":
                if !buffer.isEmpty { flushNumber() }
            default:
                if Character(ch).isLetter || ch == "_" {
                    buffer.append(Character(ch))
                } else if !buffer.isEmpty {
                    flushNumber()
                }
            }
        }

        // Handle colloquial "of" — convert "50% of 200" → 0.5 * 200
        var cleaned: [Token] = []
        for i in tokens.indices {
            if case .identifier(let word) = tokens[i], word.lowercased() == "of" {
                cleaned.append(.operator("*"))
            } else {
                cleaned.append(tokens[i])
            }
        }

        // Convert standalone % after number to 0.01 multiplier
        var final: [Token] = []
        for i in cleaned.indices {
            if case .percent = cleaned[i] {
                // Colloquial: "50% of 200" or "100 + 15%"
                // The % becomes a modifier on the preceding number
                if let lastIdx = final.indices.last, case .number(let val) = final[lastIdx] {
                    final[lastIdx] = .number(val / 100.0)
                }
                // Insert implicit * if next token is number or lparen
                if i + 1 < cleaned.count {
                    switch cleaned[i + 1] {
                    case .number, .lparen:
                        final.append(.operator("*"))
                    default:
                        break
                    }
                }
            } else {
                final.append(cleaned[i])
            }
        }

        return final
    }

    // MARK: - Parser (recursive descent)

    private func parseExpression(_ tokens: [Token], _ pos: inout Int) throws -> Double {
        var result = try parseTerm(tokens, &pos)

        while pos < tokens.count {
            if case .operator(let op) = tokens[pos], op == "+" || op == "-" {
                pos += 1
                let rhs = try parseTerm(tokens, &pos)
                switch op {
                case "+": result += rhs
                case "-": result -= rhs
                default: break
                }
            } else {
                break
            }
        }
        return result
    }

    private func parseTerm(_ tokens: [Token], _ pos: inout Int) throws -> Double {
        var result = try parsePower(tokens, &pos)

        while pos < tokens.count {
            if case .operator(let op) = tokens[pos], op == "*" || op == "/" {
                pos += 1
                let rhs = try parsePower(tokens, &pos)
                switch op {
                case "*": result *= rhs
                case "/": result /= rhs
                default: break
                }
            } else {
                break
            }
        }
        return result
    }

    private func parsePower(_ tokens: [Token], _ pos: inout Int) throws -> Double {
        var result = try parseUnary(tokens, &pos)

        if pos < tokens.count, case .operator("^") = tokens[pos] {
            pos += 1
            let rhs = try parsePower(tokens, &pos) // right-associative
            result = Foundation.pow(result, rhs)
        }
        return result
    }

    private func parseUnary(_ tokens: [Token], _ pos: inout Int) throws -> Double {
        if pos < tokens.count, case .operator("-") = tokens[pos] {
            pos += 1
            let val = try parsePrimary(tokens, &pos)
            return -val
        }
        return try parsePrimary(tokens, &pos)
    }

    private func parsePrimary(_ tokens: [Token], _ pos: inout Int) throws -> Double {
        guard pos < tokens.count else { throw ParseError.unexpectedEnd }

        switch tokens[pos] {
        case .number(let val):
            pos += 1
            return val
        case .lparen:
            pos += 1
            let result = try parseExpression(tokens, &pos)
            guard pos < tokens.count, case .rparen = tokens[pos] else {
                throw ParseError.missingParen
            }
            pos += 1
            return result
        case .identifier(_):
            // Future: variable lookup
            pos += 1
            return 0
        default:
            throw ParseError.unexpectedToken
        }
    }

    enum ParseError: Error {
        case unexpectedEnd
        case missingParen
        case unexpectedToken
    }
}