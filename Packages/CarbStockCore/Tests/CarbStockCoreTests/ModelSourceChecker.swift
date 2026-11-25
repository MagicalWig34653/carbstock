import Foundation

/// Source-level check of the SwiftData `@Model` files against the CloudKit rules (spec 9.2, Gate G1).
///
/// It reads Swift source text, not the runtime schema, so it runs inside `swift test` without a simulator.
/// What it enforces per stored property of every `@Model` class:
///  - `var`, never `let`; no reserved or underscore-prefixed names
///  - attributes: only String, Int, Double, Bool, Date, UUID, Data (optional or not); no arrays, no enums,
///    no Codable structs (they would become transformable/composite attributes); no `.unique`, `.transformable`
///  - non-optional attributes carry a default value (`= …`)
///  - relationships: optional (`X?` or `[X]?`), have an inverse on the other model, never `.deny`, never `.ordered`
enum ModelSourceChecker {
    static let allowedAttributeTypes: Set<String> = ["String", "Int", "Double", "Bool", "Date", "UUID", "Data"]
    static let reservedNames: Set<String> = ["description", "entity", "objectID", "isDeleted", "isInserted", "isUpdated",
                                             "isFault", "hasChanges", "managedObjectContext", "hash", "self", "class", "superclass"]

    struct Property {
        var name: String
        var type: String
        var hasDefault: Bool
        var isLet: Bool
        var attributes: [String]
    }
    struct Model {
        var name: String
        var properties: [Property]
        var body: String
    }

    static func violations(in sources: [String]) -> [String] {
        let models = sources.flatMap { parseModels(strip($0)) }
        let names = Set(models.map(\.name))
        let byName = Dictionary(models.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [String] = []
        for model in models {
            for badToken in [".unique", "#Unique", ".transformable", ".ordered"] where model.body.contains(badToken) {
                out.append("\(model.name): enthält \(badToken) (Spec 9.2)")
            }
            for p in model.properties {
                let id = "\(model.name).\(p.name)"
                if p.isLet { out.append("\(id): `let` statt `var`") }
                if reservedNames.contains(p.name) || p.name.hasPrefix("_") { out.append("\(id): reservierter oder unzulässiger Name") }
                for a in p.attributes where a.contains(".unique") || a.contains(".transformable") || a.contains(".ordered") {
                    out.append("\(id): Attribut \(a) nicht CloudKit-tauglich")
                }
                let isOptional = p.type.hasSuffix("?")
                var base = isOptional ? String(p.type.dropLast()) : p.type
                let isArray = base.hasPrefix("[") && base.hasSuffix("]") && !base.contains(":")
                if isArray { base = String(base.dropFirst().dropLast()) }
                if names.contains(base) {
                    if !isOptional { out.append("\(id): Beziehung nicht optional (\(p.type))") }
                    if p.attributes.contains(where: { $0.contains(".deny") }) { out.append("\(id): Löschregel .deny") }
                    let backRefs = byName[base]?.properties.filter { prop in
                        var t = prop.type
                        if t.hasSuffix("?") { t.removeLast() }
                        if t.hasPrefix("["), t.hasSuffix("]") { t = String(t.dropFirst().dropLast()) }
                        return t == model.name
                    } ?? []
                    if backRefs.isEmpty { out.append("\(id): keine Gegenbeziehung in \(base)") }
                    if let declared = declaredInverse(p.attributes), !(byName[base]?.properties.contains { $0.name == declared } ?? false) {
                        out.append("\(id): Inverse \(base).\(declared) existiert nicht")
                    }
                } else {
                    if isArray || !allowedAttributeTypes.contains(base) { out.append("\(id): Typ \(p.type) nicht erlaubt (nur \(allowedAttributeTypes.sorted().joined(separator: ", ")))") }
                    if !isOptional && !p.hasDefault { out.append("\(id): weder optional noch mit Vorgabewert") }
                }
            }
        }
        return out
    }

    private static func declaredInverse(_ attributes: [String]) -> String? {
        for a in attributes {
            guard let r = a.range(of: "inverse:") else { continue }
            let tail = a[r.upperBound...]
            if let dot = tail.lastIndex(of: ".") {
                let name = tail[tail.index(after: dot)...].prefix { $0.isLetter || $0.isNumber || $0 == "_" }
                if !name.isEmpty { return String(name) }
            }
        }
        return nil
    }

    // MARK: parsing

    /// Removes comments and string contents so braces and `=` inside them cannot confuse the scan.
    static func strip(_ s: String) -> String {
        var out = "", i = s.startIndex
        while i < s.endIndex {
            let c = s[i], next = s.index(after: i) < s.endIndex ? s[s.index(after: i)] : Character(" ")
            if c == "/" && next == "/" {
                while i < s.endIndex && s[i] != "\n" { i = s.index(after: i) }
            } else if c == "/" && next == "*" {
                i = s.index(i, offsetBy: 2)
                while i < s.endIndex && !(s[i] == "*" && s.index(after: i) < s.endIndex && s[s.index(after: i)] == "/") { i = s.index(after: i) }
                if i < s.endIndex { i = s.index(i, offsetBy: 2) }
            } else if c == "\"" {
                out.append("\"\"")
                i = s.index(after: i)
                while i < s.endIndex && s[i] != "\"" { if s[i] == "\\" { i = s.index(after: i) }; if i < s.endIndex { i = s.index(after: i) } }
                if i < s.endIndex { i = s.index(after: i) }
            } else { out.append(c); i = s.index(after: i) }
        }
        return out
    }

    static func parseModels(_ text: String) -> [Model] {
        var models: [Model] = []
        var search = text.startIndex
        while let m = text.range(of: "@Model", range: search..<text.endIndex) {
            search = m.upperBound
            guard let cls = text.range(of: "class ", range: m.upperBound..<text.endIndex) else { break }
            let name = text[cls.upperBound...].prefix { $0.isLetter || $0.isNumber || $0 == "_" }
            guard let open = text[cls.upperBound...].firstIndex(of: "{") else { break }
            var depth = 0, end = open
            for idx in text[open...].indices {
                if text[idx] == "{" { depth += 1 } else if text[idx] == "}" { depth -= 1; if depth == 0 { end = idx; break } }
            }
            let body = String(text[text.index(after: open)..<end])
            models.append(Model(name: String(name), properties: parseProperties(body), body: body))
            search = end
        }
        return models
    }

    /// Statements at class level: split on newline or `;` outside (), [], <>; a `{` ends the head (computed property, init, func).
    private static func parseProperties(_ body: String) -> [Property] {
        var statements: [(head: String, hasBody: Bool)] = []
        var cur = "", paren = 0, braces = 0, hasBody = false
        func flush() {
            let t = cur.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { statements.append((t, hasBody)) }
            cur = ""; hasBody = false
        }
        for c in body {
            if braces > 0 {
                if c == "{" { braces += 1 } else if c == "}" { braces -= 1; if braces == 0 { flush() } }
                continue
            }
            switch c {
            case "(", "[": paren += 1; cur.append(c)
            case ")", "]": paren -= 1; cur.append(c)
            case "{": hasBody = true; braces = 1
            case "\n", ";": if paren == 0 { flush() } else { cur.append(" ") }
            default: cur.append(c)
            }
        }
        flush()

        var props: [Property] = [], pendingAttributes: [String] = []
        for (head, hasBody) in statements {
            var rest = Substring(head), attributes = pendingAttributes
            pendingAttributes = []
            while rest.hasPrefix("@") {
                var depth = 0, stop = rest.endIndex
                for idx in rest.indices {
                    let ch = rest[idx]
                    if ch == "(" { depth += 1 } else if ch == ")" { depth -= 1 }
                    else if ch == " " && depth == 0 && idx != rest.startIndex { stop = idx; break }
                }
                attributes.append(String(rest[..<stop]))
                rest = rest[stop...].drop { $0 == " " }
            }
            guard rest.hasPrefix("var ") || rest.hasPrefix("let ") else {
                if rest.isEmpty { pendingAttributes = attributes }
                continue
            }
            if hasBody { continue } // computed property
            let isLet = rest.hasPrefix("let ")
            let decl = rest.dropFirst(4).trimmingCharacters(in: .whitespaces)
            guard let colon = decl.firstIndex(of: ":") else { continue }
            let name = decl[..<colon].trimmingCharacters(in: .whitespaces)
            let afterColon = decl[decl.index(after: colon)...]
            var depth = 0, eq: String.Index?
            for idx in afterColon.indices {
                let ch = afterColon[idx]
                if "([<".contains(ch) { depth += 1 } else if ")]>".contains(ch) { depth -= 1 }
                else if ch == "=" && depth == 0 { eq = idx; break }
            }
            let type = (eq.map { afterColon[..<$0] } ?? afterColon).trimmingCharacters(in: .whitespaces)
            props.append(Property(name: name, type: type, hasDefault: eq != nil, isLet: isLet, attributes: attributes))
        }
        return props
    }
}
