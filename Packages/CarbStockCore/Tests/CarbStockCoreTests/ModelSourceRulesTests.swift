import Foundation
import Testing

/// Gate G1: every `@Model` in `App/Models` is checked against the CloudKit rules (spec 9.2) at source level,
/// so `swift test` alone (no simulator) catches a violation. The introspection of the real schema
/// (`AppTests/SchemaRulesTests`) is the second, independent check.
@Suite struct ModelSourceRulesTests {
    // MARK: the checker itself, with violating fixtures (each must be reported)

    private func found(_ source: String, _ needle: String) -> Bool {
        ModelSourceChecker.violations(in: [source]).contains { $0.contains(needle) }
    }

    @Test func reportsAttributeWithoutDefaultOrOptional() {
        #expect(found("@Model final class A { var name: String }", "A.name"))
    }

    @Test func reportsUniqueAttribute() {
        #expect(found("@Model final class A { @Attribute(.unique) var id: UUID = UUID() }", "A.id"))
    }

    @Test func reportsTransformableAndExternalTypes() {
        #expect(found("@Model final class A { var tags: [String] = [] }", "A.tags"))
        #expect(found("@Model final class A { var kind: Kind = .a }", "A.kind"))
    }

    @Test func reportsRelationshipThatIsNotOptional() {
        let a = "@Model final class A { var id: UUID = UUID(); var bs: [B] = [] }"
        let b = "@Model final class B { var id: UUID = UUID(); var a: A? }"
        #expect(found(a + "\n" + b, "A.bs"))
    }

    @Test func reportsRelationshipWithoutInverse() {
        let a = "@Model final class A { var id: UUID = UUID(); var bs: [B]? = [] }"
        let b = "@Model final class B { var id: UUID = UUID() }"
        #expect(found(a + "\n" + b, "A.bs"))
    }

    @Test func reportsDenyAndOrderedRelationships() {
        let a = "@Model final class A { @Relationship(deleteRule: .deny, inverse: \\B.a) var bs: [B]? = [] }"
        let b = "@Model final class B { var a: A? }"
        #expect(found(a + "\n" + b, "A.bs"))
        #expect(found("@Model final class A { @Relationship(.ordered) var x: String? }", "A.x"))
    }

    @Test func reportsLetPropertyAndReservedName() {
        #expect(found("@Model final class A { let id: UUID = UUID() }", "A.id"))
        #expect(found("@Model final class A { var description: String = \"\" }", "A.description"))
    }

    @Test func acceptsACompliantModel() {
        let a = """
        @Model final class A {
            var id: UUID = UUID()
            var note: String?
            var count: Int = 0
            var computed: Int { count + 1 }
            @Relationship(deleteRule: .cascade, inverse: \\B.a) var bs: [B]? = []
            init() {}
        }
        """
        let b = "@Model final class B { var id: UUID = UUID(); var a: A? }"
        #expect(ModelSourceChecker.violations(in: [a, b]).isEmpty)
    }

    // MARK: the real model files

    @Test func appModelsFollowTheCloudKitRules() throws {
        let sources = try Self.modelSources()
        #expect(sources.count >= 3, "Modelldateien nicht gefunden")
        let models = sources.joined().components(separatedBy: "@Model").count - 1
        #expect(models == 12, "Erwartet 12 @Model-Typen (5 Inventory, 5 Training, 2 Imports), gefunden \(models)")
        #expect(ModelSourceChecker.violations(in: sources) == [])
    }

    static func modelSources() throws -> [String] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        let dir = url.appendingPathComponent("App/Models")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }.sorted { $0.path < $1.path }
        return try files.map { try String(contentsOf: $0, encoding: .utf8) }
    }
}
