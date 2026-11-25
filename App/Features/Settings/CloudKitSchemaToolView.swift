#if DEBUG
import SwiftUI

/// Oberfläche des DEBUG-Werkzeugs: nur mit `-CarbStockCloudKitSchema`, führt erst nach Tipp auf den Knopf etwas aus.
struct CloudKitSchemaToolView: View {
    @State private var running = false
    @State private var outcome: CloudKitSchemaTool.Outcome?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Legt im CloudKit-Container \(Stores.cloudContainerID) die Satztypen und Felder der Inventory-Daten im Development-Schema an. Es werden keine Nutzerdaten geschrieben. Nur Entwickler, einmal vor der Production-Promotion.")
                        .font(.footnote)
                }
                Section("Ergebnis") {
                    switch outcome {
                    case nil:
                        Text(running ? "Läuft …" : "Noch nichts ausgeführt")
                    case .refused(let reason):
                        Label("Nicht ausgeführt", systemImage: "exclamationmark.triangle").font(.headline)
                        Text(reason)
                    case .failed(let message):
                        Label("Fehlgeschlagen", systemImage: "xmark.octagon").font(.headline)
                        Text(message)
                    case .done(let types):
                        Label("Schema angelegt", systemImage: "checkmark.circle").font(.headline)
                        ForEach(types, id: \.self) { Text($0).font(.body.monospaced()) }
                    }
                }
                Section {
                    Button("Schema anlegen") {
                        running = true
                        Task {
                            outcome = await CloudKitSchemaTool.run(.live)
                            running = false
                        }
                    }
                    .disabled(running)
                }
            }
            .navigationTitle("CloudKit-Schema")
        }
    }
}
#endif
