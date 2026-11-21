# App Store Connect und Developer-Portal – was Lino anlegt

**Zeitpunkt: ab sofort möglich.** Name, Bundle-ID und iCloud-Container sind festgelegt und ändern sich nicht mehr; das Grundgerüst baut. Das Anlegen veröffentlicht nichts.
Agenten legen hier nichts an (Linos Konto, Außenwirkung).

## Stand 21.11.2026: App ID und Container registriert
Lino hat ausdrücklich erlaubt, die Bundle-ID per Xcode/automatischer Signierung zu registrieren. Ein signierter Gerätebuild
(`xcodebuild build -destination 'generic/platform=iOS' -allowProvisioningUpdates`, Team `J2DU2P47XW`) hat das Provisioning-Profil
„iOS Team Provisioning Profile: de.linolaske.carbstock“ angelegt. Es enthält App-ID `J2DU2P47XW.de.linolaske.carbstock`,
iCloud-Container `iCloud.de.linolaske.carbstock` (Development + Production), CloudKit, Push (`aps-environment`), KV-Speicher und 2 Geräte.
**Offen bleibt:** App-Store-Connect-Eintrag (Schritt 2), Prüfung im Portal durch Lino, CloudKit-Schema-Promotion, alles Weitere dieser Datei.

## Schritt 1 – Developer-Portal (Certificates, Identifiers & Profiles)
1. **iCloud-Container** anlegen: `iCloud.de.linolaske.carbstock` (Beschreibung z. B. „CarbStock“).
2. **App ID** (explicit) anlegen: Bundle-ID `de.linolaske.carbstock`, Beschreibung „CarbStock“, Team `J2DU2P47XW`.
   Capabilities einschalten:
   - **iCloud** → „Include CloudKit support“ → Container `iCloud.de.linolaske.carbstock` zuordnen
   - **Push Notifications** (nötig für CloudKit-Stille-Benachrichtigungen; es gibt keinen eigenen Push-Server)
   - sonst nichts (kein HealthKit, kein Sign in with Apple, keine App Groups)

Alternative: Projekt in Xcode öffnen (`xcodegen generate`, dann `CarbStock.xcodeproj`), mit dem Konto anmelden und einmal auf ein Gerät bauen – die automatische Signierung legt App ID und Container dann selbst an. Danach im Portal prüfen, ob iCloud/CloudKit und Push aktiv sind.

## Schritt 2 – App Store Connect → Apps → „+“ → Neue App
| Feld | Wert |
|---|---|
| Plattform | iOS |
| Name | **CarbStock** (prüfen, ob frei; Ausweichvorschläge: „CarbStock – Carb-Vorrat“, „CarbStock Vorrat“; max. 30 Zeichen, keine Preise/fremden Marken) |
| Primäre Sprache | Deutsch |
| Bundle-ID | `de.linolaske.carbstock` (erscheint im Menü erst nach Schritt 1) |
| SKU | `carbstock-ios` (frei wählbar, intern, nicht änderbar) |
| Nutzerzugriff | Vollzugriff |

## Später (nicht jetzt)
- **App-Datenschutz** („App Privacy“): voraussichtlich „Data Not Collected“ – erst nach Spike S1 und Linos Prüfung (siehe `docs/KONZEPT.md` §4).
- **Datenschutz-URL**: Pflicht vor TestFlight extern / Review; Text entsteht in M8.
- **Kategorie**: Gesundheit und Fitness (Vorschlag), Sekundär: Essen und Trinken oder Dienstprogramme.
- **Altersfreigabe, Exportkonformität**: `ITSAppUsesNonExemptEncryption = NO` ist gesetzt.
- **CloudKit-Schema nach Production promoten** (CloudKit-Konsole) – erst vor dem ersten TestFlight-Build, bewusster Schritt durch Lino (Spec 9.2.5).
- **O-18**: öffentlich im App Store oder nur privat/TestFlight – bestimmt Umfang von Impressum, Review und Datenschutzangaben.

## Was danach freigeschaltet wird
- Signierte Gerätebuilds mit iCloud → **Spike S1** (Sync auf zwei Geräten) und **S3** (Benachrichtigungen auf dem Gerät).
- TestFlight-Builds (Upload nur nach Linos Regeln für TestFlight-Freigaben).
