# EasyThreat

Kompakte Aggro-Balken und ein Kampfjournal für OctoWoW. Von **VanCleef**.

**Build:** `20261018-colors1` (Entwicklungsstand)

## Installation

### OctoWoW-Launcher

Diese Git-Adresse im Addon-Manager des Launchers einfügen:

`https://github.com/edwinvancleef577/EasyThreat.git`

Die Groß-/Kleinschreibung bitte so übernehmen, insbesondere unter Linux. `EasyThreat.toc`, die Lua-Dateien und `Media/` liegen direkt im Repository-Hauptverzeichnis.

Steht nach einem früheren Versuch **Failed to install** da: Spiel beenden, den bestehenden Addon-Ordner außerhalb von `Interface/AddOns` sichern, den fehlerhaften Eintrag im Launcher entfernen und die Adresse erneut hinzufügen. Den `WTF`-Ordner und die SavedVariables behalten; dort liegen die Einstellungen. Auch ein bisher manuell installiertes Addon muss für die Verwaltung durch den Launcher gegebenenfalls einmal so ersetzt werden.

### ZIP manuell installieren

1. Auf der Repository-Seite **Code → Download ZIP** wählen und das Archiv entpacken.
2. Den entpackten Repository-Ordner (z. B. `easythreat-main`) in **EasyThreat** umbenennen.
3. Diesen Ordner nach `Interface/AddOns` kopieren.
4. Die Datei muss unter `Interface/AddOns/EasyThreat/EasyThreat.toc` liegen, ohne einen weiteren verschachtelten EasyThreat-Ordner.
5. EasyThreat im Charakterbildschirm aktivieren. Mit **`/et`** oder einem Linksklick auf das Minimap-Icon die Konfiguration öffnen.

Für manuelle Updates das Spiel beenden und den Addon-Ordner ersetzen. Die SavedVariables behalten, damit Einstellungen erhalten bleiben. Die Aufnahme ist eingebaut; ein separates Addon **EasyThreat_Recorder** wird nicht benötigt.

## Korrektur für Gruppenwerte

Bitte alle Gruppenmitglieder gemeinsam aktualisieren. Fehlende Beobachtungen eines anderen Clients verdrängen keine gültige lokale Threat-Berechnung mehr. Tatsächlich ungültige Berechnungen bleiben gesperrt. Die Diagnose unterscheidet diese Fälle. Für Kampfstatus-Abfragen werden passende Einheiten statt ungeeigneter GUID-Zugriffe verwendet. Ältere Builds können die erweiterten Werteantworten nicht lesen.

## Loslegen

- Spielern und Pets ihre Rollen zuweisen. Die eigene Rolle steht direkt in der Anzeigentabelle.
- Unter **Anzeigen** je Rolle Tooltip, Zielrahmen, Namensplaketten und Gegnerliste auswählen. Die Auswahl gilt für den eigenen Charakter.
- **Weitere Spieler/Pets** bestimmt die zusätzlichen Balken: 1–4, standardmäßig **3**. Der eigene Charakter und das eigene Pet zählen nicht dazu. Bereits gespeicherte Einstellungen bleiben erhalten.
- Unter **Gegnerfilter** Solo, Gruppe oder Raid sowie Gegnerstufen und Gegnertypen auswählen. Für gefilterte Anzeigen im Solospiel **Solo** einschalten.
- Unter **Positionen** außerhalb des Kampfes die **Vorschau** und das Verschieben aktivieren. Die goldenen Griffleisten dienen zum Ziehen.

Die anfängliche Prozent-Schwelle ist **0 %**. Höhere Werte reduzieren die gefilterten Anzeigen; der Zielrahmen hat ein eigenes Verhalten für die Anzeige im Kampf.

## Balken lesen

Der eigene Balken steht oben, das eigene lebende Pet direkt darunter. Weitere Teilnehmer folgen entsprechend ihrer verfügbaren Threat-Werte.

Beim Aufbau zeigt ein blauer Balken mit Zahl die bekannte Bedrohung des zunächst einzigen Beteiligten. Sobald ein weiterer Spieler oder ein Pet Bedrohung erzeugt, folgt die Kampfansicht. Ein voller Herausforderer-Balken bedeutet bei ausreichenden Daten, dass die geschätzte Übernahmeschwelle erreicht ist. Es ist keine Schadensrangliste.

Der Rahmen markiert den gemeldeten oder beobachteten Aggrohalter: grün bei einem zugewiesenen Tank, rot bei anderen Rollen. Größte Bedrohungssumme und tatsächlicher Aggrohalter können sich unterscheiden. Mit **Immer Spielerfarben verwenden** bleiben auch eigene Balken und der Aufbau in den Spielerfarben.

Fehlende Messwerte sind keine gemessenen Nullwerte. Soweit möglich bleibt der letzte Wert blasser sichtbar. Ein beobachtetes Gegnerziel kann auch nur das Ziel eines einzelnen Zaubers sein.

## Tooltip und Abstände

Unter **Positionen → Tooltip** hält **Immer anzeigen** die zulässigen Gegnerbalken auch außerhalb des Kampfes leer mit „Keine Aggro“ sichtbar. **Dynamische Breite** berücksichtigt die endgültige Tooltip-Breite, auch mit EasyCast. Das Pet-Icon steht innen neben dem kürzeren, rechtsbündigen Petbalken.

Unter **Abstände** gibt es den Pet-Abstand und den **Abstand zu Mitspielern** (Standard: 6). Letzterer trennt den eigenen Spieler-/Pet-Block von den weiteren Teilnehmern. Unter **Positionen → Zielrahmen → Abstände** sind dieselben Abstände unabhängig vom Tooltip einstellbar; dort liegen auch X/Y.

## Kampfjournal

Das Buch oder ein Rechtsklick auf das Minimap-Icon öffnet das Journal. Gegner-Threat, Ressourcenvorrat und -verbrauch, Heilung und Schaden lassen sich über die Filterbuttons einblenden. Gruppe oder eigener Charakter mit Pets, ein wählbarer Zeitbereich und eine gespeicherte Referenz helfen beim gemeinsamen Vergleichen.

Das Journal soll Gruppenspiel verständlich machen und vergibt keine Leistungsnote. Datenqualität, geschätzte Werte und fehlende Beobachtungen sind zu beachten. Die Darstellung lässt sich in der Hauptkonfiguration anpassen.

## Daten und Diagnose

EasyThreat verwendet verfügbare Client-Funktionen, Serverantworten, lokale Kampfereignisse und den Austausch mit anderen EasyThreat-Clients. **SuperWoW und ClassicAPI bleiben optional.** Zum Laden des Addons ist keine zusätzliche DLL erforderlich. Lokale Formeln können nicht für jede Fähigkeit, jedes Talent oder jede eigene Balanceänderung exakte Werte garantieren.

Alle Gruppenmitglieder sollten denselben Build verwenden. Gruppenaustausch und das Teilen von Aufnahmen sind standardmäßig an; die Schalter stehen unter **Diagnose**. Offline-Spieler, unterschiedliche Versionen oder fehlende Beobachtungen können Lücken verursachen. Empfangene Aufnahmen machen das Journal nicht automatisch zu einem vollständigen Gruppenlog.

Für einen kurzen Datentest:

1. **`/et test start`** eingeben, vor dem Angriff einen Gegner auswählen und etwa zwei Minuten spielen.
2. Danach **`/et test show`** öffnen und den Bericht kopieren. **`/et test stop`** beendet früher.
3. Build, Client-Version, beteiligte Addons und erwartetes sowie tatsächliches Verhalten beschreiben.

Der Test verändert keine Rollen oder Anzeigeeinstellungen. Keine Serverantwort verhindert die lokale Berechnung nicht. Ohne aktives Schadensschild sind null Schadensschild-Treffer normal. Abweichungen zwischen Quellen können auch durch unterschiedliche Messzeitpunkte entstehen.

**Exporte vor dem Weitergeben prüfen:** Einstellungen und Journal können Charakternamen und Gruppeninformationen enthalten. Keine vollständigen Account-Ordner oder privaten Diagnosedaten öffentlich hochladen. Normale SavedVariables werden beim Neuladen der Oberfläche oder regulären Beenden des Spiels gespeichert. Ein angezeigter Pfad allein bedeutet noch nicht, dass eine neue Datei geschrieben wurde.

## Lizenz

Es gilt die beiliegende [LICENSE](LICENSE). Nutzung, Kopieren, Änderungen und Weitergabe sind bei Erhalt des Hinweises erlaubt. Die Nutzung mit offiziellen, von Blizzard betriebenen World-of-Warcraft-Diensten ist nicht gestattet; OctoWoW-Nutzung ist willkommen. Unabhängiges Fanprojekt ohne Gewährleistung. Spielgrafiken und Schriften gehören ihren jeweiligen Rechteinhabern.

## Spieler- und Pet-Farben

Nur dein eigener Balken verwendet Warnfarben. Andere Spieler behalten ihre Spielerfarbe, auch beim Aufbau und bei fliehenden Gegnern. Pets erhalten automatisch einen anderen Farbton; eine eigene gespeicherte Pet-Farbe hat Vorrang. Unter **Spielerfarben** kannst du das Pet über die Gruppenauswahl auswählen und separat färben. Die Farben gelten auch für Gegnerliste und Journal. **Immer Spielerfarben verwenden** fixiert zusätzlich die Farbe deines eigenen Balkens. Der grüne/rote Rahmen kennzeichnet weiterhin den Aggrohalter.

Das Journal startet standardmäßig in **Gruppe**. Dieses Update aktiviert die Gruppenansicht einmal auch bei bestehenden Einstellungen; spätere bewusste Umschaltungen bleiben gespeichert.
