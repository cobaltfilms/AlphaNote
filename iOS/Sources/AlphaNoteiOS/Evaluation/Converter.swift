import Foundation

/// Unit conversion + currency conversion
final class Converter {

    // MARK: - Public API

    /// Convert a natural-language conversion expression.
    /// Examples: "12 km to mi", "10\" to cm", "100 USD to EUR", "$10 to JPY"
    func convert(_ expression: String) -> String? {
        let cleaned = expression
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let split = splitConversionExpression(cleaned) else {
            return nil
        }

        guard let parse = parseLeftHandValue(split.left) else {
            return nil
        }

        let toRaw = normalizeToken(split.right)

        if let result = convertUnit(value: parse.value, from: parse.unit, to: toRaw) {
            return result
        }

        if let result = convertCurrency(value: parse.value, from: parse.currency, to: toRaw) {
            return result
        }

        return nil
    }

    // MARK: - Parsing

    private func splitConversionExpression(_ expression: String) -> (left: String, right: String)? {
        guard let regex = try? NSRegularExpression(pattern: "(?i)\\s+(to|in|en)\\s+"),
              let match = regex.firstMatch(in: expression, range: NSRange(expression.startIndex..., in: expression)) else {
            return nil
        }

        guard let matchRange = Range(match.range, in: expression) else {
            return nil
        }

        let left = String(expression[..<matchRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        let right = String(expression[matchRange.upperBound...]).trimmingCharacters(in: .whitespaces)

        guard !left.isEmpty, !right.isEmpty else {
            return nil
        }

        return (left, right)
    }

    private func parseLeftHandValue(_ left: String) -> (value: Double, unit: String, currency: String)? {
        let nsLeft = left as NSString
        let numberPattern = "[-+]?\\d+(?:[.,]\\d+)?"

        guard let numberRegex = try? NSRegularExpression(pattern: numberPattern),
              let numberMatch = numberRegex.firstMatch(in: left, range: NSRange(location: 0, length: nsLeft.length)) else {
            return nil
        }

        let numberText = nsLeft.substring(with: numberMatch.range).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(numberText) else {
            return nil
        }

        let numberRange = numberMatch.range
        let before = nsLeft.substring(with: NSRange(location: 0, length: numberRange.location)).trimmingCharacters(in: .whitespaces)
        let afterStart = numberRange.location + numberRange.length
        let after = nsLeft.substring(with: NSRange(location: afterStart, length: nsLeft.length - afterStart)).trimmingCharacters(in: .whitespaces)

        let symbolCurrency = currencyFromSymbol(before.isEmpty ? after : before)
        let fromCurrency = symbolCurrency.isEmpty ? normalizeCurrency(before.isEmpty ? after : before) : symbolCurrency
        let fromUnitRaw = normalizeToken(after.isEmpty ? before : after)

        return (value, fromUnitRaw, fromCurrency)
    }

    // MARK: - Unit Conversion

    private func convertUnit(value: Double, from: String, to: String) -> String? {
        if let fromUnit = lengthUnit(from), let toUnit = lengthUnit(to) {
            let converted = convertDimension(value: value, from: fromUnit, to: toUnit)
            return formatResult(converted, unit: to)
        }

        if let fromUnit = areaUnit(from), let toUnit = areaUnit(to) {
            let converted = convertDimension(value: value, from: fromUnit, to: toUnit)
            return formatResult(converted, unit: to)
        }

        if let fromUnit = volumeUnit(from), let toUnit = volumeUnit(to) {
            let converted = convertDimension(value: value, from: fromUnit, to: toUnit)
            return formatResult(converted, unit: to)
        }

        if let fromUnit = massUnit(from), let toUnit = massUnit(to) {
            let converted = convertDimension(value: value, from: fromUnit, to: toUnit)
            return formatResult(converted, unit: to)
        }

        if let fromUnit = temperatureUnit(from), let toUnit = temperatureUnit(to) {
            let converted = convertDimension(value: value, from: fromUnit, to: toUnit)
            return formatResult(converted, unit: to)
        }

        return nil
    }

    private func convertDimension(value: Double, from: Dimension, to: Dimension) -> Double {
        let base = from.converter.baseUnitValue(fromValue: value)
        return to.converter.value(fromBaseUnitValue: base)
    }

    private func lengthUnit(_ raw: String) -> UnitLength? {
        let token = normalizeToken(raw)
        let map: [String: UnitLength] = [
            "m": .meters, "meter": .meters, "metre": .meters, "meters": .meters, "metres": .meters,
            "cm": .centimeters, "centimeter": .centimeters, "centimetre": .centimeters, "centimeters": .centimeters, "centimetres": .centimeters,
            "mm": .millimeters, "millimeter": .millimeters, "millimetre": .millimeters, "millimeters": .millimeters, "millimetres": .millimeters,
            "km": .kilometers, "kilometer": .kilometers, "kilometre": .kilometers, "kilometers": .kilometers, "kilometres": .kilometers,
            "in": .inches, "inch": .inches, "inches": .inches, "\"": .inches, "″": .inches,
            "ft": .feet, "foot": .feet, "feet": .feet, "'": .feet, "′": .feet,
            "mi": .miles, "mile": .miles, "miles": .miles,
            "yd": .yards, "yard": .yards, "yards": .yards
        ]
        return map[token]
    }

    private func areaUnit(_ raw: String) -> UnitArea? {
        let token = normalizeToken(raw)
        let map: [String: UnitArea] = [
            "sqm": .squareMeters, "m²": .squareMeters, "sqmeters": .squareMeters, "squaremeter": .squareMeters, "squaremeters": .squareMeters, "squarem": .squareMeters,
            "sqcm": .squareCentimeters, "cm²": .squareCentimeters, "squarecentimeter": .squareCentimeters, "squarecentimeters": .squareCentimeters, "squarecm": .squareCentimeters,
            "sqmm": .squareMillimeters, "mm²": .squareMillimeters, "squaremillimeter": .squareMillimeters, "squaremillimeters": .squareMillimeters, "squaremm": .squareMillimeters,
            "ha": .hectares, "hectare": .hectares, "hectares": .hectares,
            "sqkm": .squareKilometers, "km²": .squareKilometers, "squarekilometer": .squareKilometers, "squarekilometers": .squareKilometers, "squarekm": .squareKilometers,
            "sqft": .squareFeet, "ft²": .squareFeet, "squarefoot": .squareFeet, "squarefeet": .squareFeet, "squareft": .squareFeet,
            "sqin": .squareInches, "in²": .squareInches, "squareinch": .squareInches, "squareinches": .squareInches, "squarein": .squareInches,
            "sqyd": .squareYards, "yd²": .squareYards, "squareyard": .squareYards, "squareyards": .squareYards, "squareyd": .squareYards,
            "sqmi": .squareMiles, "mi²": .squareMiles, "squaremile": .squareMiles, "squaremiles": .squareMiles, "squaremi": .squareMiles,
            "acre": .acres, "acres": .acres,
            "are": .ares, "ares": .ares
        ]
        return map[token]
    }

    private func volumeUnit(_ raw: String) -> UnitVolume? {
        let token = normalizeToken(raw)
        let map: [String: UnitVolume] = [
            "l": .liters, "liter": .liters, "litre": .liters, "liters": .liters, "litres": .liters,
            "ml": .milliliters, "milliliter": .milliliters, "millilitre": .milliliters, "milliliters": .milliliters, "millilitres": .milliliters,
            "m³": .cubicMeters, "cubicmeter": .cubicMeters, "cubicmeters": .cubicMeters,
            "cm³": .cubicCentimeters, "cc": .cubicCentimeters, "cubiccentimeter": .cubicCentimeters, "cubiccentimeters": .cubicCentimeters,
            "mm³": .cubicMillimeters, "cubicmillimeter": .cubicMillimeters, "cubicmillimeters": .cubicMillimeters,
            "gal": .gallons, "gallon": .gallons, "gallons": .gallons,
            "qt": .quarts, "quart": .quarts, "quarts": .quarts,
            "pt": .pints, "pint": .pints, "pints": .pints,
            "cup": .cups, "cups": .cups,
            "floz": .fluidOunces, "flozs": .fluidOunces, "fluidounce": .fluidOunces, "fluidounces": .fluidOunces,
            "tbsp": .tablespoons, "tablespoon": .tablespoons, "tablespoons": .tablespoons,
            "tsp": .teaspoons, "teaspoon": .teaspoons, "teaspoons": .teaspoons,
            "in³": .cubicInches, "cubicinch": .cubicInches, "cubicinches": .cubicInches,
            "ft³": .cubicFeet, "cubicfoot": .cubicFeet, "cubicfeet": .cubicFeet,
            "yd³": .cubicYards, "cubicyard": .cubicYards, "cubicyards": .cubicYards
        ]
        return map[token]
    }

    private func massUnit(_ raw: String) -> UnitMass? {
        let token = normalizeToken(raw)
        let map: [String: UnitMass] = [
            "kg": .kilograms, "kgs": .kilograms, "kilogram": .kilograms, "kilograms": .kilograms,
            "g": .grams, "gs": .grams, "gram": .grams, "grams": .grams,
            "mg": .milligrams, "milligram": .milligrams, "milligrams": .milligrams,
            "µg": .micrograms, "ug": .micrograms, "mcg": .micrograms, "microgram": .micrograms, "micrograms": .micrograms,
            "t": .metricTons, "tonne": .metricTons, "tonnes": .metricTons, "metricton": .metricTons, "metrictons": .metricTons,
            "lb": .pounds, "lbs": .pounds, "pound": .pounds, "pounds": .pounds,
            "oz": .ounces, "ozs": .ounces, "ounce": .ounces, "ounces": .ounces,
            "st": .stones, "stone": .stones, "stones": .stones
        ]
        return map[token]
    }

    private func temperatureUnit(_ raw: String) -> UnitTemperature? {
        let token = normalizeToken(raw)
        let map: [String: UnitTemperature] = [
            "c": .celsius, "°c": .celsius, "celsius": .celsius, "centigrade": .celsius,
            "f": .fahrenheit, "°f": .fahrenheit, "fahrenheit": .fahrenheit,
            "k": .kelvin, "kelvin": .kelvin, "kelvins": .kelvin
        ]
        return map[token]
    }

    // MARK: - Currency Conversion

    private var cachedRates: [String: Double] = [:]
    private var ratesBase: String = ""
    private var ratesTimestamp: Date = .distantPast

    private func convertCurrency(value: Double, from: String, to: String) -> String? {
        guard from.count == 3,
              to.count == 3,
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
                result = "\(self.formatNumber(converted)) \(to)"
            }
            group.leave()
        }

        _ = group.wait(timeout: .now() + 5)

        return result
    }

    private func fetchRates(base: String, completion: @escaping ([String: Double]) -> Void) {
        if ratesBase == base && Date().timeIntervalSince(ratesTimestamp) < 3600 && !cachedRates.isEmpty {
            completion(cachedRates)
            return
        }

        let urlStr = "https://api.exchangerate.host/latest?base=\(base)"
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

    private func currencyFromSymbol(_ token: String) -> String {
        switch token.trimmingCharacters(in: .whitespaces) {
        case "$": return "USD"
        case "€": return "EUR"
        case "£": return "GBP"
        case "¥", "￥": return "JPY"
        default: return ""
        }
    }

    private func normalizeCurrency(_ token: String) -> String {
        let value = token
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        if value.count == 3, value.allSatisfy({ $0.isLetter }) {
            return value
        }

        return ""
    }

    private func normalizeToken(_ token: String) -> String {
        token
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "°", with: "°")
            .replacingOccurrences(of: " ", with: "")
    }

    private func formatResult(_ value: Double, unit: String) -> String {
        "\(formatNumber(value)) \(unit)"
    }

    private func formatNumber(_ value: Double) -> String {
        if value == floor(value) {
            return String(Int64(value))
        }

        var formatted = String(format: "%.6f", value)
        while formatted.last == "0" {
            formatted.removeLast()
        }
        if formatted.last == "." {
            formatted.removeLast()
        }
        return formatted
    }
}
