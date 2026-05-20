import Foundation

/// Unit conversion + currency conversion
final class Converter {

    // MARK: - Public API

    /// Convert a natural-language conversion expression.
    /// Examples: "12km in miles", "100USD in EUR", "72f in c"
    func convert(_ expression: String) -> String? {
        let pattern = #"(\d+\.?\d*)\s*([\w°]+)\s+(?:in|to|en)\s+([\w°]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: expression, range: NSRange(expression.startIndex..., in: expression)),
              match.numberOfRanges >= 4 else {
            return nil
        }

        guard let valueRange = Range(match.range(at: 1), in: expression),
              let fromRange = Range(match.range(at: 2), in: expression),
              let toRange = Range(match.range(at: 3), in: expression) else {
            return nil
        }

        guard let value = Double(String(expression[valueRange])) else { return nil }
        let from = normalize(String(expression[fromRange]))
        let to = normalize(String(expression[toRange]))

        // Try unit conversion
        if let result = convertUnit(value: value, from: from, to: to) {
            return result
        }

        // Try currency conversion
        if let result = convertCurrency(value: value, from: from, to: to) {
            return result
        }

        return nil
    }

    // MARK: - Unit Conversion

    private let distanceUnits: [String: Double] = [
        "km": 1000, "kilometer": 1000, "kilometers": 1000,
        "m": 1, "meter": 1, "meters": 1,
        "cm": 0.01, "centimeter": 0.01,
        "mm": 0.001, "millimeter": 0.001,
        "mi": 1609.344, "mile": 1609.344, "miles": 1609.344,
        "yd": 0.9144, "yard": 0.9144, "yards": 0.9144,
        "ft": 0.3048, "foot": 0.3048, "feet": 0.3048,
        "in": 0.0254, "inch": 0.0254, "inches": 0.0254,
    ]

    private let massUnits: [String: Double] = [
        "kg": 1, "kilogram": 1, "kilograms": 1,
        "g": 0.001, "gram": 0.001, "grams": 0.001,
        "lb": 0.453592, "pound": 0.453592, "pounds": 0.453592,
        "oz": 0.0283495, "ounce": 0.0283495, "ounces": 0.0283495,
    ]

    private func convertUnit(value: Double, from: String, to: String) -> String? {
        // Distance
        if let fromM = distanceUnits[from], let toM = distanceUnits[to] {
            let result = value * fromM / toM
            return formatResult(result, unit: to)
        }

        // Mass
        if let fromKg = massUnits[from], let toKg = massUnits[to] {
            let result = value * fromKg / toKg
            return formatResult(result, unit: to)
        }

        // Temperature
        if isTemp(from) && isTemp(to) {
            let result = convertTemp(value: value, from: from, to: to)
            return formatResult(result, unit: to)
        }

        return nil
    }

    private func isTemp(_ unit: String) -> Bool {
        ["c", "°c", "celsius", "f", "°f", "fahrenheit", "k", "kelvin"].contains(unit)
    }

    private func convertTemp(value: Double, from: String, to: String) -> Double {
        // Convert to Celsius first
        let celsius: Double
        switch from {
        case "c", "°c", "celsius": celsius = value
        case "f", "°f", "fahrenheit": celsius = (value - 32) * 5 / 9
        case "k", "kelvin": celsius = value - 273.15
        default: return value
        }

        switch to {
        case "c", "°c", "celsius": return celsius
        case "f", "°f", "fahrenheit": return celsius * 9 / 5 + 32
        case "k", "kelvin": return celsius + 273.15
        default: return value
        }
    }

    // MARK: - Currency Conversion

    private var cachedRates: [String: Double] = [:]
    private var ratesBase: String = ""
    private var ratesTimestamp: Date = .distantPast

    private func convertCurrency(value: Double, from: String, to: String) -> String? {
        // Only attempt for 3-letter currency codes
        guard from.count == 3, to.count == 3,
              from.allSatisfy({ $0.isUppercase }),
              to.allSatisfy({ $0.isUppercase }) else {
            return nil
        }

        let group = DispatchGroup()
        group.enter()

        var result: String?

        fetchRates(base: from) { rates in
            if let rate = rates[to] {
                let converted = value * rate
                result = String(format: "%.2f %@", converted, to.uppercased())
            }
            group.leave()
        }

        _ = group.wait(timeout: .now() + 5)

        return result
    }

    private func fetchRates(base: String, completion: @escaping ([String: Double]) -> Void) {
        // Use cache if fresh (< 1 hour)
        if ratesBase == base && Date().timeIntervalSince(ratesTimestamp) < 3600 && !cachedRates.isEmpty {
            completion(cachedRates)
            return
        }

        let urlStr = "https://api.exchangerate.host/latest?base=\(base.uppercased())"
        guard let url = URL(string: urlStr) else {
            completion([:])
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rates = json["rates"] as? [String: Double] else {
                completion([:])
                return
            }
            self?.cachedRates = rates
            self?.ratesBase = base
            self?.ratesTimestamp = Date()
            completion(rates)
        }.resume()
    }

    // MARK: - Helpers

    private func normalize(_ unit: String) -> String {
        unit.lowercased()
            .replacingOccurrences(of: "°", with: "")
            .replacingOccurrences(of: "s$", with: "", options: .regularExpression)
    }

    private func formatResult(_ value: Double, unit: String) -> String {
        if value == floor(value) && abs(value) < 1e9 {
            return "\(Int64(value)) \(unit)"
        }
        return String(format: "%.4g %@", value, unit)
    }
}