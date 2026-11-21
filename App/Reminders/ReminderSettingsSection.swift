import SwiftData
import SwiftUI

/// Einstellungen „Erinnerungen auf diesem Gerät“ (lokal, nicht synchronisiert).
struct ReminderSettingsSection: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    private let settings = ReminderSettings()
    private let scheduler = ReminderScheduler()

    @State private var enabled = ReminderSettings().isEnabled
    @State private var time = ReminderSettingsSection.date(hour: ReminderSettings().hour, minute: ReminderSettings().minute)
    @State private var permission: NotificationPermission = .notDetermined

    var body: some View {
        Section {
            Toggle("Erinnerungen auf diesem Gerät", isOn: $enabled)
                .onChange(of: enabled) { _, on in
                    Task {
                        if on { await scheduler.enable(context: context) } else { await scheduler.disable(context: context) }
                        permission = await SystemNotificationCenter().permission()
                    }
                }
            if enabled {
                DatePicker("Uhrzeit", selection: $time, displayedComponents: .hourAndMinute)
                    .onChange(of: time) { _, new in
                        let c = Calendar.current.dateComponents([.hour, .minute], from: new)
                        settings.hour = c.hour ?? 9
                        settings.minute = c.minute ?? 0
                        Task { await scheduler.rebuild(context: context) }
                    }
            }
            if enabled, permission == .denied {
                Label("Benachrichtigungen sind für CarbStock ausgeschaltet. „Läuft bald ab“ bleibt in der App sichtbar.",
                      systemImage: "bell.slash")
                    .font(.footnote)
                Button("Systemeinstellungen öffnen") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
        } header: {
            Text("Erinnerungen")
        } footer: {
            Text("Eine Sammelmeldung je Tag, 60 und 30 Tage vor dem MHD. Gilt nur für dieses Gerät und wird nicht über iCloud abgeglichen.")
        }
        .task { permission = await SystemNotificationCenter().permission() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { permission = await SystemNotificationCenter().permission() } }
        }
    }

    static func date(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
    }
}
