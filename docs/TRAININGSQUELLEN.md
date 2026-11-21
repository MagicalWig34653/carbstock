# Trainingsquellen: Apple Health und Strava (Prüfung, Stand 21.11.2026)

Ziel: Sessions nicht nur von Hand eintragen, sondern aus Apple Health und/oder Strava beziehen. Randbedingungen: **kein eigenes Backend**, App für beliebige Nutzer (öffentliches Repo, AGPLv3), Trainingsdaten bleiben lokal (O-01 Option B), keine Gesundheitsdaten in iCloud (Spec 11).

Legende: **[belegt]** Aussage einer Apple-/Strava-Quelle, **[Annahme]** plausibel, nicht geprüft, **[Spike]** nur auf Geräten klärbar.

## 1. Was die Quellen liefern: geplant oder absolviert?

| Quelle | Absolvierte Einheiten | Geplante Einheiten |
|---|---|---|
| Apple Health (HealthKit, `HKWorkout`) | ja: Art, Start, Dauer **[belegt]** | nein. WorkoutKit (`WorkoutScheduler`) kann eigene Pläne auf die Uhr legen; dass eine andere App fremde geplante Workouts lesen darf, ist **nicht belegt** → **[Spike]** |
| Strava API | ja: Aktivitäten (`activity:read`, nicht öffentliche mit `activity:read_all`) **[belegt]** | nein. Strava kennt Routen und Aktivitäten, keine geplanten Einheiten **[Annahme, in den Docs nicht gefunden]** |

Folge: **Der Prognose-Bedarf (geplante Einheiten) bleibt manuell** (Sessions und Wochenvorlage). Health/Strava können nur *absolvierte* Einheiten liefern: nützlich zum Abhaken („erledigt“), für die Verbrauchsbuchung und um die Wochenvorlage mit der Realität abzugleichen. Sie ersetzen die Planung nicht.

## 2. Apple Health

- **Geräteübergreifend:** Health-Daten werden über iCloud auf Geräte derselben Apple-ID abgeglichen und sind Ende-zu-Ende-verschlüsselt (Apple Health Privacy Overview) **[belegt]**. Das gilt nur, wenn der Nutzer *Health in iCloud* eingeschaltet hat und mit Zwei-Faktor angemeldet ist. Verfügbarkeit auf jedem Gerät, Zeitpunkt des ersten Abgleichs und Verzögerungen sind **[Spike]**. Die App darf **nicht** annehmen, dass jede Einheit sofort auf jedem iPhone liegt.
- **Wichtig:** CarbStock müsste dafür nichts synchronisieren. Jedes Gerät liest selbst aus seiner Health-Datenbank. Die Trainingsdaten bleiben damit lokal (Option B), und es gibt keine neue iCloud-Ablage für Gesundheitsdaten.
- **Berechtigung:** `NSHealthShareUsageDescription`, HealthKit-Capability, Dialog pro Datentyp. Ob Lesen verweigert wurde, **erfährt die App nicht**; leere Ergebnisse bedeuten „keine Daten oder keine Berechtigung“ **[belegt]**. Die UI muss das neutral sagen und auf Einstellungen > Health > Datenzugriff verweisen.
- **Gesperrtes Gerät:** Der Health-Speicher ist bei gesperrtem Gerät verschlüsselt; Lesen im Hintergrund kann mit `errorDatabaseInaccessible` scheitern **[belegt]**. Also nur im Vordergrund einlesen, Fehler als „später erneut“ behandeln.
- **Duplikate:** Dieselbe Fahrt kann mehrfach in Health stehen (Uhr + Radcomputer-App + Strava-Export). Abgleich nach Zeitfenster-Überlappung und Quelle; nie automatisch löschen, nur zusammenfassen/anbieten **[Annahme, Regeln im Core testbar]**. Eigene Identität: Health-UUID der Probe als Schlüssel (idempotenter Import).
- **Offline:** Health ist lokal, funktioniert ohne Netz **[belegt]**. Ein eben erst auf einem anderen Gerät aufgezeichnetes Training kann fehlen, bis iCloud abgeglichen hat.
- **Regel-Konflikt:** CLAUDE.md/Spec verbieten heute HealthKit („keine Gesundheitsdaten“). Das müsste ausdrücklich geändert werden: nur Workout-Typ, Start, Dauer lesen, **nichts** schreiben, nichts nach iCloud/Backup, Datenschutzangaben und App-Review-Text anpassen (Apple 5.1.3). Kein Puls, keine Leistung, keine Kalorien, keine Route.
- **Mac/iPad:** Nicht relevant (nur iPhone).

## 3. Strava

- **Zugang:** OAuth2 mit Browser/`ASWebAuthenticationSession`; Token-Tausch über `POST /oauth/token` **mit `client_secret`** **[belegt]**. Die Docs nennen kein PKCE **[in den Docs nicht gefunden]**. Das Secret darf nie in einer App oder einem öffentlichen Repo liegen. **Ohne eigenes Backend gibt es keinen sicheren Ort dafür.** Jeder Nutzer müsste eine eigene Strava-API-App anlegen und Client-ID/-Secret in CarbStock eintragen (umständlich, für Allgemeinnutzer unrealistisch).
- **Strava-Abo:** Eine API-App anzulegen setzt ein Strava-Abo voraus **[belegt, Getting Started]**.
- **Kapazität:** Neue Apps laufen im „Single Player Mode“ (nur das eigene Konto, Kapazität 1), nach Upgrade 10 Athleten, darüber nur nach Prüfung durch Strava **[belegt, Rate Limits]**. Für TestFlight mit externen Testern oder den App Store ist die Strava-Anbindung damit nicht frei nutzbar.
- **Limits:** 200 Anfragen/15 min und 2 000/Tag (Lesen 100/1 000) **[belegt]**; Access-Token 6 Stunden, Refresh-Token wechselt bei jeder Erneuerung **[belegt]** → Tokens im Schlüsselbund (Keychain), **nicht** in iCloud und nicht im Backup.
- **Geräteübergreifend:** Das Strava-Konto ist geräteübergreifend, aber die Tokens wären pro Gerät (Keychain lokal). Jedes Gerät müsste sich selbst verbinden. Teilen der Tokens über iCloud-Schlüsselbund wäre ein eigener Entwurf **[Annahme, nicht geprüft]**.
- **Bedingungen:** API-Vertrag (zuletzt 1. Juni 2026 aktualisiert) und Brand-Guidelines sind einzuhalten; nach Presseberichten (Nov. 2024) dürfen Daten nur dem jeweiligen Nutzer gezeigt und nicht für KI-Modelle genutzt werden. **Den aktuellen Vertrag hat noch niemand gelesen** → vor jeder Umsetzung lesen.
- **Webhooks** (Push neuer Aktivitäten) brauchen einen Server → ohne Backend entfällt das; nur Abruf beim App-Start/Pull-to-Refresh.
- **Offline:** ohne Netz keine Strava-Daten; zuletzt importierte Sessions bleiben lokal.
- **Umweg ohne eigenes Secret:** Strava kann Aktivitäten nach Apple Health schreiben (nur wenn der Nutzer es einschaltet) **[Annahme, nicht geprüft]**. Dann reicht die Health-Anbindung für beide Quellen, ohne Strava-API.

## 4. Empfehlung (überholt durch Abschnitt 6: Strava ist fester Bestandteil)

1. **Apple Health zuerst (V2), schmal:** nur lesen, nur Typ/Start/Dauer, nur absolvierte Einheiten, Import in den lokalen Trainingsspeicher mit Health-UUID als Schlüssel. Planung bleibt manuell.
2. **Strava später oder gar nicht:** Wegen Secret, Single-Player-Grenze und Abo-Pflicht ohne Backend für eine App für alle Nutzer nicht tragfähig. Sinnvoll nur über den Umweg Strava → Health oder als „eigene API-App eintragen“-Expertenoption.
3. **Vorher** (Lino): Regeländerung „kein HealthKit“ entscheiden, Datenschutztext anpassen, Spike auf zwei echten Geräten (Health-Abgleich, gesperrt, Duplikate, ob WorkoutKit fremde Pläne zeigt).
4. **Keine Entscheidung** zur iCloud-Synchronisierung der Trainingsdaten: Option B bleibt, bis Lino und Apple entscheiden (O-01).

## 5. Noch zu klären (Spike/Lino)

- S4: Health-Abgleich zwischen zwei iPhones (Verzögerung, ausgeschaltetes iCloud-Health, gesperrt).
- S5: Liefert `WorkoutScheduler` geplante Einheiten fremder Apps? (vermutlich nein)
- S6: Schreibt Strava nach Health (Einstellung, Umfang)?
- Strava-API-Vertrag lesen; Datenschutz-/Review-Auswirkung bei TestFlight extern.

Quellen: Apple Health Privacy Overview (Mai 2023), Apple Developer Forums/Dokumentation zu HealthKit-Datenschutz und `errorDatabaseInaccessible`, WWDC20 „Synchronize health data with HealthKit“, developers.strava.com (Authentication, Getting Started, Rate Limits).

## 6. Verbindliche Planung (Lino, 21.11.: Strava wird wirklich eingeplant, kein eigenes Backend)

Strava ist fester Bestandteil des Plans, nicht „gegebenenfalls“. Apple Health kommt daneben. Beide Quellen liefern **absolvierte** Aktivitäten, die dieselbe Fahrt doppelt melden können (Uhr → Health, Radcomputer/Uhr → Strava → ggf. Health). Deshalb gehört die Duplikatlogik zuerst in den Core.

### 6.1 Wege zu Strava ohne Backend (Wahl offen, Board-Frage)

| Weg | Geheimnis nötig | Nutzbar für | Aufwand/Risiko |
|---|---|---|---|
| **A. Eigene Strava-API-App je Nutzer** (Client-ID und -Secret in den Einstellungen, Keychain) | liegt beim Nutzer, nie im Repo | jeder Nutzer für **sein eigenes** Konto: der Single-Player-Modus (Kapazität 1) reicht genau dafür **[belegt]** | Strava-Abo und App-Anlage durch jeden Nutzer; Einrichtung kurz erklären |
| **B. Archiv-Import** (Strava-Export, `activities.csv`) | keins | jeder | manuell, kein Live-Abruf; Dateiformat ist **[Annahme, vor Umsetzung an einem echten Export prüfen]** |
| **C. Gemeinsame CarbStock-App bei Strava** (ein Secret im Build) | Secret müsste im App-Binary liegen: extrahierbar, nicht im öffentlichen Repo, Kapazität 10, darüber Prüfung durch Strava | alle | ohne Backend nicht sauber; nur mit Strava-Zustimmung denkbar |
| **D. Strava → Apple Health → CarbStock** | keins | wer Strava nach Health schreiben lässt **[Annahme, S6]** | hängt an Health-Anbindung |

**Empfehlung:** A + B (beide ohne Backend und ohne Geheimnis im Repo), später C nur nach Rückfrage bei Strava. D als Zusatz, falls S6 es hergibt.

### 6.2 Aufgaben und Reihenfolge (Projektplan)

1. **M9a Externe Aktivitäten und Duplikate (Core, test-first)**: keine Abhängigkeit, kann sofort nach M6/M7 starten.
2. **M9b Strava**: nach M9a und nach M7 (Einstellungen, Löschen/Export berücksichtigen die neuen Daten); vor dem **externen** TestFlight (M8b), damit die Datenschutzerklärung (AC-D2) die Strava-Anbindung schon enthält.
3. **M9c Apple Health**: nach M9a; wartet auf Linos Entscheidung zur Regel „kein HealthKit“ und Spike S4.

### 6.3 Anforderungen (neu, AC-X)

- **AC-X1** Eine externe Aktivität hat Quelle (strava/health), externe ID, Start (UTC), Dauer (Zeit in Bewegung und verstrichen), Sportart, Titel. **Nicht** gespeichert: Route/GPS, Puls, Leistung, Kalorien, Bilder, Kommentare. Speicher: lokal (Training-Store, O-01 B), nie in iCloud.
- **AC-X2** Import ist **idempotent** über (Quelle, externe ID): erneuter Abruf legt nichts doppelt an; geänderte Aktivitäten werden aktualisiert; bei Strava gelöschte bleiben lokal, markiert „nicht mehr bei Strava“.
- **AC-X3** **Duplikat** = gleiche Fahrt aus zwei Quellen: Start höchstens 5 Minuten auseinander **und** Überlappung der Zeitfenster mindestens 80 % **und** vereinbare Sportart. Duplikate werden zu **einer** Aktivität mit mehreren Quellen zusammengeführt; nichts wird gelöscht. Unsichere Fälle (nur eine Bedingung knapp verfehlt) werden dem Nutzer als „Vielleicht doppelt“ gezeigt.
- **AC-X4** Eine Aktivität zählt **höchstens einmal** für Verbrauch und Statistik, egal wie viele Quellen sie meldet.
- **AC-X5** Eine absolvierte Aktivität an einem Tag mit passender geplanter Session erzeugt einen **Vorschlag** „als erledigt markieren“; der Nutzer bestätigt. Sportart → Session-Typ (Z2/Long/…) lässt sich aus Strava nicht sicher ableiten, der Nutzer wählt; der Vorschlag nutzt die Dauer als Hinweis.
- **AC-X6** Verbinden und Trennen von Strava ist jederzeit möglich; Trennen widerruft den Zugriff bei Strava (Deauthorization), löscht Token aus dem Schlüsselbund; importierte Aktivitäten bleiben, bis der Nutzer sie löscht. „Alle Daten löschen“ (AC-D3) und der Export (AC-S7) berücksichtigen die Aktivitäten.
- **AC-X7** **Offline:** ohne Netz bleiben importierte Aktivitäten sichtbar; Abruf scheitert mit klarer Meldung; kein Absturz; Wiederholung beim nächsten Start/Pull-to-Refresh. Rate-Limit-Antwort (429) wird respektiert (warten, nicht wiederholen).
- **AC-X8** Tokens liegen **nur** im Schlüsselbund dieses Geräts (kein iCloud-Schlüsselbund, kein Backup in Dateien/Export). Das Secret (Weg A) erscheint nie in Logs, Export oder Repo.
- **AC-X9** Jedes Gerät verbindet sich selbst (Tokens sind pro Gerät); die App darf nicht annehmen, dass ein zweites Gerät schon verbunden ist.
- **AC-X10** Der Abruf liest nur, was nötig ist (`activity:read`), und prüft die gewährten Scopes; fehlt der Scope, erklärt die App es.

### 6.4 Abhängigkeiten

M9a ← (M6, Core). M9b ← M9a, M7 (Einstellungen/Export/Löschen), Linos Wahl A/B/C, Strava-API-Vertrag gelesen (Stand 1. Juni 2026), Brand-Guidelines („Connect with Strava“-Button, Hinweis „Powered by Strava“). M9c ← M9a, Entscheidung HealthKit-Regel, Spike S4. M8b ← M9b (Datenschutztext, Review-Hinweise).

### 6.5 Prüfungen

- **Core-Tests (test-first):** Duplikatregeln inkl. Grenzfälle (4:59/5:01 Minuten, 79/80 % Überlappung, mehrere Kandidaten, Reihenfolge der Quellen, drei Quellen für dieselbe Fahrt), Idempotenz, Update, Löschung bei Strava, Zählung höchstens einmal (AC-X4).
- **App-Tests mit Attrappen:** Strava-Client hinter einem Protokoll (kein echtes Netz in Tests): Token-Erneuerung (Refresh-Token wechselt), 401, 429, Offline, verweigerter Scope, Trennen.
- **Geräte-Spike S7 (Lino):** echter OAuth-Ablauf mit eigener Strava-API-App, Strava-App installiert/nicht installiert, Umleitung; S4/S6 für Health.
- **Review:** Datenschutz (keine Gesundheitsdaten in iCloud), Strava-Vertrag und Brand-Regeln, vor M8b.
