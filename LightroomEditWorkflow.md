# 📷 Lightroom Edit Workflow v3.0 — Claude-gestützt

> **Zweck:** Session-Choreographie für Claude + Lightroom MCP.
> Sagt wann welche Funktion aufgerufen wird und wo du (User) eingreifst.
> Die konkreten Stilwerte sind **nicht** hier — die leitet Claude aus der Analyse ab.

---

## So benutzt du diesen Workflow

Öffne ein Bild im Develop-Modul, starte Claude mit:
> *„Bearbeite das aktive Bild nach Workflow v3.0"* (+ ggf. Stilwunsch wie „cool-dramatisch" oder „natürlich-warm")

Claude geht dann Phase für Phase durch. An jeder **🛑 Feedback-Stelle** wartet er auf dich.

---

## Phase 0 — Session-Start

**Claude tut:**
- Liest ggf. expliziten Stilwunsch aus der Nachricht (sonst: aus Kontext inferieren)
- Kein Tool-Call nötig

**User-Input erwartet:** nein

---

## Phase 1 — Bild & RAW-Daten auslesen

**Claude tut:**
1. `lightroom:get_active_photo`
   → Kamera, Objektiv, EXIF (ISO, Blende, Zeit, Brennweite), aktuelle Develop-Settings, Rating, Keywords
2. **Kamera-Weiche:**
   - **Canon EOS R6 (CR3 RAW)** → voller Spielraum, Adobe Farbe, Objektivkorrektur aktiv, Schärfe-Radius klein (0.8–1.0)
   - **Samsung S21 Ultra (JPEG/HEIC)** → vorsichtig, Sättigung eher runter, Schärfung sparsam, Rauschreduzierung prüfen
   - **Insta360 Ace 2 (JPEG)** → starke Verzeichnungskorrektur, Kontrast/Struktur aggressiver
3. `lightroom:get_photo`
   → visueller Eindruck für Motivbeschreibung

**Claude gibt aus:** 2–3 Sätze Kamera-Kontext + Motivbeschreibung

**User-Input erwartet:** nein

---

## Phase 2 — Bildanalyse

**Claude tut:**
1. `lightroom:analyze_raw_photo`
2. Strukturierte Auswertung gegen die Regeln in [Anhang B](#anhang-b--entscheidungsregeln-aus-zahlen)
3. **Motiv-Typ identifizieren** aus Kombination visuellem Eindruck (Phase 1 `get_photo`) + Spatial-Daten (siehe [Anhang D](#anhang-d--motiv-profile))

**Claude gibt aus:** kompaktes Analyse-Briefing:
- Histogramm-Lage (mean, median, DR-Stops)
- Clipping-Status
- Dominante Farbverteilung (hueDistribution, bMinusR, gMinusM)
- Spatial (thirds, auffällige Grid-Zonen)
- **Identifizierter Motiv-Typ** (Landschaft / Wildlife / Stadt — einer aus Anhang D, mit 1-Satz-Begründung)
- Ableitung: Welche Hebel hat das Bild, welche Risiken?

**User-Input erwartet:** nein

---

## Phase 2b — Auto als Referenz-Check (Lightroom Sensei)

Adobe Sensei (Lightroom Auto) ist auf Millionen Bildern trainiert und liefert eine unabhängige Einschätzung. Als Referenz-Check vor den eigenen Varianten wertvoll: Wenn Claudes Plan stark von Auto abweicht, muss es einen begründeten Grund geben.

**Claude tut:**
1. `lightroom:reset_develop_settings`
2. `lightroom:set_develop_settings` mit `auto_tone: true` (und optional `auto_white_balance: true` — siehe unten)
3. `lightroom:get_active_photo` → liest die von Auto gesetzten Basic-Werte aus dem Panel
4. `lightroom:analyze_edit` → quantitative Auswirkung
5. `lightroom:create_snapshot` als `LR Auto (Referenz)`
6. Reset oder direkt Variante A darüber bauen

**Claude gibt aus:** Vergleichstabelle Baseline vs. Auto. Fokus auf Abweichungen:
- Welche Regler hat Auto stark gesetzt? (Ausweis: welche Probleme das Modell sieht)
- Welche Regler bleiben bei 0? (das was Auto als "unkritisch" einstuft)
- Wohin zieht Auto die Metriken? (DR, bMinusR, saturation)

### Wann `auto_white_balance` aktivieren?

| Szene | Empfehlung |
|---|---|
| Portrait mit Hauttönen | **ja** — Auto-WB ist verlässlich |
| Alltagsszene, Mischlicht, neutrale Farbverteilung | **ja** |
| Landschaft mit dominanter Farbstimmung (Nebel, Goldene Stunde, Dämmerung, Polarlicht, Unterwasser) | **nein** — Auto rechnet die Stimmung heraus |
| Monochrome/farbarme Szenen | **nein** — Auto erzeugt künstliche Farbverschiebungen |

**Faustregel aus der Analyse:** Wenn `hueDistribution` zu ≥80 % in einem einzigen Bucket liegt oder `bMinusR` absolut > 30 ist → `auto_white_balance` ausschalten, weil Auto diese Farbstimmung als "Weißabgleichfehler" deuten und neutralisieren wird.

### Interpretation der Auto-Werte

- **Blacks/Whites nah an Claudes Plan** → Schwarz-/Weißpunkt technisch richtig gesetzt
- **Auto Shadows stark positiv, Claude-Plan negativ** → Stilentscheidung: Dokumentarisch vs. Dramatisch
- **Auto Highlights stark negativ** → in den Highlights ist mehr zurückzuholen als auf den ersten Blick erkennbar
- **Auto bMinusR nahe 0, Claude-Analyse stark abweichend** → Farbstimmung ist **Signal, nicht Rauschen** → bewusst erhalten

**Claude gibt aus:** 1 Absatz Interpretation — was bestätigt Auto, wovon weiche ich bewusst ab, und warum.

**User-Input erwartet:** nein (Auto-Snapshot bleibt als stiller Vergleichspunkt im Panel)

---

## Phase 2c — Zuschnitt & Ausrichtung

Cropping definiert die Komposition, bevor stilistische Edit-Entscheidungen fallen. Muss vor Phase 3 passieren, weil Vignette, Color Grading und Masken auf dem finalen Bildausschnitt wirken. **Das MCP kann Crop nicht setzen** — User setzt manuell (`R` im Develop-Modul).

**Claude tut:**
- Crop-Vorschlag aus `get_photo` (visueller Eindruck) + EXIF (Originalseitenverhältnis) + Motiv-Typ (Anhang D)
- Begründung aus Komposition: Horizont-Lage, Drittelregel, Blickführung, Mittelachsen-Symmetrie
- Nennt konkret: Seitenverhältnis + Ausrichtungskorrektur (Grad) falls nötig

**Claude gibt aus:**
- Empfohlenes Seitenverhältnis (3:2 original, 16:9 Panorama, 4:5 Instagram-Portrait, 1:1 quadratisch, 9:16 Reels)
- Ausrichtungsvorschlag falls Horizont schief (Grad, im Uhrzeigersinn oder gegen)
- Was aus dem Bild weg darf (störende Ränder, unwichtige Bildzonen)
- Was unbedingt bleiben muss (Motiv-Anker, Symmetrien, führende Linien)

### 🛑 Feedback-Stelle 0.5

> User setzt Crop in Lightroom (`R`), bestätigt mit *„Crop gesetzt"*
> Alternativ: *„Kein Crop nötig"* → direkt weiter zu Phase 3
> Alternativ: *„Anders croppen weil X"* → Claude passt Vorschlag an

### Optionaler Reality-Check nach Crop

Nach dem Crop kann Claude `lightroom:analyze_edit` laufen lassen — das respektiert den Crop im Export. Wenn die neuen `spatial.thirds`- und `spatial.grid3x3`-Werte stark von der Vollbild-Analyse in Phase 2 abweichen, ist das ein Hinweis, dass der Crop den Bildcharakter verändert hat (z.B. von weiter Landschaft zu Detail-Fokus) → Motiv-Typ in Phase 3 evtl. neu bewerten.

---

## Phase 3 — Drei Edit-Varianten berechnen & als Snapshots speichern

**Claude tut pro Variante:**
1. `lightroom:reset_develop_settings` (nur vor Variante A — danach wird auf Varianten-Basis weitergearbeitet)
2. `lightroom:set_develop_settings` mit kompletter Werte-Vorgabe
3. `lightroom:create_snapshot` mit klarem Namen (`Var A — [Label]`, `Var B — [Label]`, `Var C — [Label]`)
4. `lightroom:analyze_edit` zur Verifikation der Variante

**Die drei Varianten werden an den Motiv-Typ aus Phase 2 angepasst (siehe [Anhang D](#anhang-d--motiv-profile)).**

Standard-Varianten für **Landschaft** (Default, wenn Motiv-Typ nicht eindeutig):

| Variante | Charakter | Typischer Zweck |
|---|---|---|
| **A — Dokumentarisch** | moderate Kontraste, natürliche Farben, Felsen offen, Matte-Lift in Tiefen | Publikation, Reportage, Archiv |
| **B — Cool-Dramatic** | tiefe Schwarzpunkte, hohe Weißpunkte, Blau/Aqua HSL-Push, Vignette | Instagram, Stil Matthias |
| **C — Teal/Orange Cinematic** | Variante A/B + Color Grading Shadows 35°/Lights 210° (sat ≥10) | Filmischer Look, Farbtrennung |

Für Wildlife/Stadt siehe Motiv-Profile.

Falls ein spezieller Stilwunsch in Phase 0 kam (z.B. „high-key", „schwarzweiß"), ersetzt Claude eine der Standardvarianten entsprechend.

**Claude gibt aus:** kompakte Vergleichstabelle der Kernmetriken (DR, blacks%, highlights%, bMinusR, gMinusM, tempSpread) für alle drei Varianten + Hinweis welcher Snapshot im Panel welche Variante ist.

### 🛑 Feedback-Stelle 1

> User prüft die drei Snapshots visuell in Lightroom und gibt eine der folgenden Rückmeldungen:
> - *„Variante X nehmen"* → Claude wendet Snapshot X an, geht zu Phase 5
> - *„Variante X mit Änderung Y"* → Claude passt an, neuer Snapshot, zurück zur Prüfung
> - *„Noch eine Variante mit Z"* → Claude erstellt vierte Variante

---

## Phase 4 — Iterative Feinjustierung (optional)

Diese Phase wiederholt sich so lange, bis der globale Edit sitzt.

**Claude tut pro Iteration:**
1. `lightroom:create_snapshot` vor Änderung (Sicherheitsnetz)
2. `lightroom:set_develop_settings` mit Delta
3. `lightroom:analyze_edit`
4. Vergleichstabelle vorher/nachher

**Typische Eingriffe:**
- Kontrast, Belichtung, Farbbalance
- HSL Gelb/Orange defensiv gegen Gelbstich im Nebel
- Color Grading Sättigung hoch (Werte ≥10 damit sichtbar, siehe [Anhang A](#anhang-a--tool-quirks))

### 🛑 Feedback-Stelle 2

> *„Passt, weiter zu den Masken"* → Phase 5
> *„Noch X ändern"* → nochmal iterieren

---

## Phase 5 — Lokale Masken (Vorschlag)

**Claude kann keine Masken setzen** — das MCP unterstützt das aktuell nicht. Claude gibt einen Vorschlag mit konkreten Werten, User setzt manuell.

**Die Masken-Auswahl richtet sich nach Motiv-Typ aus Phase 2 — siehe [Anhang D](#anhang-d--motiv-profile).**

Standard-Masken für **Landschaft** mit Vorschlag aus den Zahlen:

1. **🌫️ AI-Maske „Himmel auswählen"** — wenn thirds[0] ≥ 120 und highlights-Zone überbelichtet wirkt
   - typisch: Belichtung −0.2 bis −0.3, Lichter −15, Dehaze +10 bis +15, Klarheit +5 bis +10

2. **🪨 AI-Maske „Motiv auswählen" oder invertierter Himmel** — wenn dark cluster meanLum < 25 UND Strukturpotenzial da
   - typisch: Belichtung −0.1 bis −0.2, Tiefen +10 bis +20, Struktur +10 bis +15, Klarheit +5 bis +8, Dehaze +5 bis +10

3. **🧊 Pinsel mit Bereichsmaske „Helligkeit 150–255"** — wenn highlights tonal < 2 % UND Eis/Schnee im Bild
   - typisch: Belichtung +0.1 bis +0.2, Weiß +5 bis +10, Tönung +3 bis +5 (gegen Cyan), Sättigung −5 bis −10

4. **💧 Pinsel unteres Bilddrittel** — wenn Wasser/Vordergrund vorhanden, thirds[2] flach wirkt
   - typisch: Klarheit +5, Dehaze +5

**Halbe Intensität als Default für Matthias' Stil** — Werte sind bereits reduziert angesetzt.

### 🛑 Feedback-Stelle 3

> User setzt Masken in Lightroom, gibt Rückmeldung: *„Masken sind drauf"* oder *„Masken X und Y gesetzt, Rest nicht"*

---

## Phase 6 — Verifikation nach Masken

**Claude tut:**
1. `lightroom:analyze_edit`
2. Vergleich: pre-Masken vs. post-Masken

**Checkliste der Warnungen:**
- `shadowsWarnPct` > 15 % → Felsen-Maske Belichtung zurückdrehen
- `shadowsClippedPct` > 4 % → zu viel Schwarz-Clipping
- `highlightsWarnPct` > 5 % → Eis überstrahlt
- `gMinusM` Drift > 3 → Farbstich aufgetaucht
- `saturation p95` > 90 → irgendwo zu bunt

**Claude gibt aus:** Verifikations-Tabelle + evtl. Korrekturvorschlag

### 🛑 Feedback-Stelle 4 (nur bei Warnungen)

> User entscheidet: so lassen oder nachjustieren

---

## Phase 7 — Metadaten

### 7a — Keyword-Vorschlag

**Claude tut:**
- Aus Motiv + EXIF + Session-Kontext 5 Keywords vorschlagen
- Hierarchie: Ort → Motiv → Genre → Stimmung/Stil → Trip/Projekt

**Claude gibt aus:** 5 Keywords mit 1-Wort-Begründung, fragt nach Bestätigung

### 🛑 Feedback-Stelle 5

> *„setze"* → `lightroom:set_keywords`
> *„statt X nimm Y"* → anpassen, nochmal fragen

### 7b — Rating

**Claude fragt:** *„Wie viele Sterne?"* (keine Voreinstellung)

### 🛑 Feedback-Stelle 6

> User nennt Zahl 1–5 → `lightroom:set_rating`
> *„skip"* → kein Rating setzen

### 7c — Collection (optional)

Wenn sinnvoll, schlägt Claude vor:
- `lightroom:list_collections` → existierende prüfen
- Falls Trip/Serie erkennbar: `lightroom:add_to_collection` vorschlagen
- Falls nichts Passendes: `lightroom:create_collection` vorschlagen

---

## Phase 8 — Abschluss

**Claude tut:**
1. Finaler Snapshot mit Stern-Präfix: `lightroom:create_snapshot` als `★ FINAL — [Variante] + Masken`
2. Zusammenfassung (1 Absatz):
   - Welche Variante war Basis
   - Welche Masken gesetzt
   - Kernmetriken final
   - Keywords + Rating

**Claude fragt abschließend:** *„Nächstes Bild aus dem Ordner?"* oder *„Session-Retrospektive machen?"*

---

## Phase 9 — Workflow-Retrospektive (optional)

**Zweck:** Der Workflow ist ein lebendes Dokument. Nach einer Session — oder nach einer Serie von Bildern — macht es Sinn zu prüfen, ob die durchlaufene Session Lücken oder Mängel im Workflow aufgedeckt hat. Das verhindert, dass dieselben Lessons mehrfach gelernt werden.

**Trigger:** User fragt explizit („Retrospektive machen?") oder Claude schlägt vor, wenn während der Session eines der folgenden passiert ist:
- Claude ist an einer Stelle vom Workflow abgewichen (Phase übersprungen, eigene Zwischenschritte eingeführt)
- Ein MCP-Parameter hat sich unerwartet verhalten
- Mehr als 3 Iterationen an demselben Regler nötig
- Ein User-Eingriff hat eine offensichtliche Workflow-Lücke geschlossen (wie Phase 2b entstand)
- Ein neues Motiv/Genre aufgetaucht, das kein vorhandenes Profil sauber abdeckt

**Claude tut:**
1. Session-Verlauf durchgehen und strukturiert reflektieren (siehe Template unten)
2. Konkrete Änderungsvorschläge für den Workflow formulieren
3. User-Bestätigung einholen, dann Dokument-Update vornehmen + Changelog-Eintrag

### Retrospektive-Template

Claude antwortet strukturiert entlang folgender Punkte:

**Was funktionierte wie geplant?**
- Welche Phasen liefen ohne Reibung?
- Welche Tool-Aufrufe lieferten direkt brauchbare Ergebnisse?
- Welche Analyse-Signale waren besonders nützlich für Entscheidungen?

**Wo gab es Reibung oder Patzer?**
Tabellarisch:

| Situation | Fehler/Reibung | Richtige Reaktion wäre gewesen |
|---|---|---|
| ... | ... | ... |

**Was war Session-spezifisch neu?**
- Neu entdeckte Parameter-Semantik, Bug, Quirk?
- Neues Motiv-Profil / Stil-Muster?
- Neues Masken-Pattern?
- Neuer Keyword-Kandidat?

**Was fehlt im Workflow?**
Konkrete Ergänzungsvorschläge mit Begründung und Lokation (welche Phase, welcher Anhang).

**Einordnung der Änderung:**
- 🔴 **Muss rein** — Fehler ohne Dokumentation würde wieder passieren
- 🟡 **Sollte rein** — Verbesserung, aber Workflow funktioniert auch ohne
- 🟢 **Kann später** — interessante Beobachtung, noch zu wenig Belege

### 🛑 Feedback-Stelle 7

> User bestätigt Änderungen, priorisiert, oder lehnt ab.
> Bei Annahme: Workflow-Dokument aktualisieren, Changelog-Eintrag mit neuer Minor-Version (v3.x+1).

### Akkumulationsregel

Nicht jede Session rechtfertigt eine Version. Wenn die Retrospektive nur kleine Beobachtungen findet (🟢), sammeln bis drei bis fünf ähnliche Einträge zusammen ein Update lohnen. Parameter-Bugs (🔴) gehen sofort rein.

---

## Anhang A — Tool-Quirks

**ℹ️ `temperature` ist absolute Kelvin, kein Delta.**
Der Parameter erwartet einen **absoluten Kelvin-Wert** (Lightroom-Standard für RAW), kein Offset zum As-Shot-Wert. Richtige Bereiche:
- 2000–3000 K: Tungsten-Korrektur (Bild wird kühler gerendert)
- 5000–5500 K: Tageslicht, Default für neutrale Szenen
- 6000–6500 K: leicht bewölkt, Canon R6 Auto-WB liegt oft hier
- 7500–10000 K: Schatten-Korrektur (Bild wird wärmer gerendert)
- 12000+ K: sehr warme Rendering

Kleine Werte (<2000 K) oder negative Werte führen zu massivem Blau-Crash (Rotkanal → 0). Wert `0` niemals setzen — führt zum Crash. Wenn nicht verwendet: Parameter weglassen.

**ℹ️ `cg_*` Parameter brauchen Sättigung ≥10 um sichtbar zu greifen.**
Werte unter 10 werden in den Zahlen zwar erkannt, aber in der gerenderten Pixel-Analyse ist kaum Unterschied messbar. Für Teal/Orange-Looks mindestens `cg_shadow_sat=15` und `cg_highlight_sat=10`. Nur `shadow`/`highlight`/`balance` verfügbar (SDK-Limit) — kein Midtone, kein Global, kein Luminanz.

**ℹ️ Lokale Masken nicht setzbar.**
Vorschlag mit konkreten Werten, User setzt im Maskenpanel (`Shift+W`).

**ℹ️ Crop und Transformation nicht setzbar.**
User setzt im Crop-Tool (`R`). `analyze_edit` respektiert den Crop, `analyze_raw_photo` nicht.

**ℹ️ Objektivkorrektur nicht setzbar.**
Bei R6-CR3: User muss Haken bei *Profilkorrekturen aktivieren* und *Chromatische Aberration entfernen* manuell setzen (geht einmal pro Import dann via Preset).

**⚠️ Plugin-Timeouts bei komplexen Edits.**
Nach schweren Mask-Renderings kann `create_snapshot` 50 s timeouten. Dann User bitten, manuell Snapshot anzulegen (`+`-Icon im Schnappschüsse-Panel).

---

### Diagnose-Regel bei unerwartetem Tool-Verhalten

Wenn ein Parameter sich seltsam verhält — niemals sofort „kaputt" diagnostizieren. Stattdessen systematischer Kalibrierungstest:

1. **Neutralwert testen:** Was ist der physikalisch sinnvolle „mittlere" Wert? (Bei temperature: 5500 K. Bei cg_sat: 15–20. Bei Belichtung: 0.)
2. **Entgegengesetzte Extreme testen:** Wenn positive Werte Effekt X zeigen, zeigen negative Werte Effekt −X, oder denselben? (Beim Temperatur-Bug taten beide Richtungen dasselbe → Hinweis auf Kelvin-Absolut-Semantik)
3. **Alleine isolieren:** Parameter in sauberer Umgebung testen, nicht in Kombination mit anderen Reglern
4. **Erst danach** Bug-Diagnose, und mit konkretem Reproduktionsfall dokumentieren

### Snapshot-Namenskonvention

Nummerische Präfixe vermeiden Chaos in langen Sessions. Empfohlenes Schema:

| Phase | Schema | Beispiel |
|---|---|---|
| Phase 0 / 1 | `00_Baseline (As Shot)` | `00_Baseline (As Shot)` |
| Phase 2b | `01_Auto-Referenz` | `01_Auto-Referenz` |
| Phase 3 | `02_VarA_[Label]`, `02_VarB_[Label]`, `02_VarC_[Label]` | `02_VarB_Cool-Dramatic` |
| Phase 4 (Iterationen) | `03_Iter1_[Änderung]`, `03_Iter2_…` | `03_Iter1_Gelb-Fix` |
| Phase 5 vorher | `04_Pre-Masken` | `04_Pre-Masken` |
| Phase 8 (Final) | `★_FINAL_[Variante]` | `★_FINAL_Dramatic+CG+Masken` |

**Aufräumen am Session-Ende:** Iter- und Pre-Snapshots können gelöscht werden, sobald der Final-Snapshot steht. Baseline, Auto-Referenz und Final-Snapshot immer behalten.

---

## Anhang B — Entscheidungsregeln aus Zahlen

### Belichtung / Tonwerte

| Metrik | Schwelle | Interpretation | Hebel |
|---|---|---|---|
| `luminance.mean` | < 85 | dunkles Bild | Belichtung +0.1 bis +0.3 prüfen |
| `luminance.mean` | > 135 | helles Bild | Belichtung −0.1 bis −0.3 prüfen |
| `dynamicRangeStops` | < 3 | extrem flach (Nebel/Dunst) | Kontrast +15 bis +25, Dehaze +5 bis +15, Schwarz/Weiß aggressiv |
| `dynamicRangeStops` | > 9 | high contrast | Kontrast-Regler zurückhaltend, Lichter/Tiefen aggressiv |
| `highlightsClippedPct` | > 2 | Clipping | Lichter −20 bis −40 |
| `shadowsClippedPct` | > 4 | Clipping | Tiefen +15 bis +30 |
| `tonalDist.highlights` | = 0 | kein echtes Weiß | Weiß +20 bis +30 |
| `tonalDist.blacks` | < 5 | kein echtes Schwarz | Schwarz −20 bis −35 |

### Farbe

| Metrik | Schwelle | Interpretation | Hebel |
|---|---|---|---|
| `bMinusR` | > 30 | global kühl | ggf. Tint +3 bis +5 |
| `bMinusR` | < −30 | global warm | Tint −3 bis −5 |
| `gMinusM` | > 3 | Grünstich | Tint +3 bis +8 (Magenta-Seite) |
| `gMinusM` | < −3 | Magentastich | Tint −3 bis −8 |
| `hueDistribution` 1 Bucket ≥95 % | monochrom | nur dort HSL eingreifen, Rest = 0 | keine Ghost-Korrekturen |
| `saturation.median` | < 20 | sehr flau | Dynamik +15 |
| `saturation.p95` | > 90 | teilweise übersättigt | Sättigung −5 oder HSL-Sat gezielt runter |

### Cluster & Temp-Spread

| Metrik | Schwelle | Interpretation | Hebel |
|---|---|---|---|
| `dark.bMinusR` | > 20 | Schatten schon kühl | keinen zusätzlichen Blau-Push in den Tiefen |
| `bright.bMinusR` | > 50 | Lichter schon blau | cg_highlights nur dezent (sat ≤5) |
| `tempSpread` | < 15 | keine Farb-Trennung | Teal/Orange Color Grading macht sichtbarsten Unterschied |
| `tempSpread` | > 60 | starke Trennung vorhanden | CG sparsam, sonst Kipp-Effekt |

### Spatial

- `thirds[0]` > 150 UND ganzes Bild: heller Himmel dominiert → Belichtung der Mitte nicht automatisch anheben
- `thirds[1]` < 60 UND Motiv in Mitte: dunkles Hauptmotiv → Felsen/Silhouetten-Charakter
- `grid[*][1]` durchweg heller als `grid[*][0]` und `grid[*][2]`: Lichtkorridor/Nebelkorridor in Bildmitte

---

## Anhang C — Kamera-Grundlagen

### Canon EOS R6 (CR3 RAW)
- Profil: **Adobe Farbe**
- Objektivkorrektur: automatisch bei RF-Glas (R6 erkennt RF24-105, RF 70-200 etc. sofort)
- Tonwert-Wiederherstellung: ±3 Stops problemlos
- Schärfe-Radius: 0.8–1.0 (feine Details)
- Rauschen bis ISO 3200 vernachlässigbar → Luminanz-NR 0–10

### Samsung Galaxy S21 Ultra (JPEG/HEIC)
- Profil: **Adobe Farbe**
- KI-Szenenoptimierung kann Weißabgleich verfälschen → Tint manuell prüfen
- Sättigung oft schon zu hoch → global **−5 bis −10** als Default
- Überschärfte Kanten vom JPEG → Schärfe Betrag 20 statt 40
- Tonwert-Wiederherstellung nur ±1 Stop

### Insta360 Ace 2 (JPEG)
- Profil: **Adobe Farbe**
- Verzeichnungskorrektur manuell aktivieren, evtl. Transformation
- Flacher Ausgangston → Kontrast/Struktur aggressiver als bei R6
- Rauschen in Schatten häufig → Luminanz-NR 15–25
- Mikrokontrast flach → Klarheit/Struktur je +15 bis +20

---

## Anhang D — Motiv-Profile

Innerhalb der Travel-Fotografie (Reise, Natur, Tiere, Städte, Meer, Berge, Eis) gibt es drei Motiv-Typen, die sich genug unterscheiden, um in Phase 3 und 5 eigene Defaults zu rechtfertigen. Claude identifiziert den Typ in Phase 2 aus **visuellem Eindruck** (`get_photo`) und **Spatial-Signalen** der Analyse.

### 🏔️ Landschaft / Natur-weit (Default)

**Typische Szenen:** Berge, Meer, Wald, Eisformationen, Himmel, Weiten, Horizonte.

**Erkennungs-Signale:**
- `spatial.thirds` zeigt klare Staffelung (oben ≠ Mitte ≠ unten), meist oben hell, Mitte dunkel
- Keine Dominanz einer zentralen Grid-Zelle
- `hueDistribution` häufig monochromatisch oder mit 1–2 dominanten Buckets
- Weitwinkel bis Normalbrennweite (14–70 mm)

**Phase 3 — Varianten:**
- **A — Dokumentarisch** (offene Tiefen, Matte-Lift, natürliche Farben)
- **B — Cool-Dramatic** oder **Warm-Dramatic** je nach Lichtstimmung (aggressive Schwarz-/Weißpunkte, HSL-Push der dominanten Farbe)
- **C — Teal/Orange Cinematic** (Color Grading-Split, 210° Lichter / 35° Schatten, sat ≥10)

**Phase 5 — Masken:**
1. 🌫️ Himmel auswählen — Belichtung −0.2 bis −0.3, Lichter −15, Dehaze +10-15
2. 🪨 Motiv (Berg/Fels) auswählen oder Himmel invertieren — Tiefen +10-20, Struktur +10-15
3. 🧊 Helligkeits-Bereichsmaske für Glanzlichter (Schnee/Eis/Wellenschaum) — Belichtung +0.15, Tönung +3 (gegen Cyan)
4. 💧 Vordergrund/Wasser unteres Drittel — Klarheit +5, Dehaze +5

**Spezialregeln:**
- `auto_white_balance` **nicht** aktivieren bei dominanter Farbstimmung (Nebel, Dämmerung, Polar-Blau)
- `spatial.thirds` direkt als Leitfaden verwenden

**Crop-Empfehlung:**
- **3:2** Original (Standard, wenn Komposition hoch/breit ausgewogen)
- **16:9** Panorama-Crop bei dominanter Horizontale (Meer, Bergkette, Wüste)
- **4:5** für Instagram-Feed, wenn vertikale Motive (Wasserfälle, Berge hochkant)
- **1:1** selten — nur bei symmetrischen Motiven (Spiegelung im See)
- Horizont-Check zwingend: Wasserlinie, Meeresoberfläche, Fernhorizont müssen exakt waagerecht

---

### 🦅 Wildlife / Tier

**Typische Szenen:** Vögel, Säugetiere, Reptilien frontal oder in Aktion. Oft mit Tele-Brennweite, isoliertem Motiv vor unscharfem Hintergrund.

**Erkennungs-Signale:**
- `spatial.grid3x3` Zentrum (grid[1][1]) visuell deutlich anders als Ränder
- `spatial.thirds` unzuverlässig — Motiv kann überall sitzen
- `hueDistribution` oft mit signifikantem Orange/Yellow-Anteil (Fell, Federn, Haut)
- Häufig höhere ISO (800+) durch schnelle Verschlusszeit
- Mittlere bis lange Brennweite (70–400 mm+)

**Phase 3 — Varianten:**
- **A — Natural** (neutrale Farben, moderate Kontraste, Tier-Farbe authentisch)
- **B — Low-Key Drama** (Hintergrund abgedunkelt, Motiv hell, starker Subjekt-Fokus)
- **C — High-Key Clean** (helle Töne, Hintergrund nahezu weiß, Motiv-Details fein)

**Phase 5 — Masken:**
1. 🐾 **„Motiv auswählen"** (AI-Maske) — Belichtung +0.1 bis +0.2, Struktur +10-15, Klarheit +5, Schärfe-Boost
2. 👁️ **Bereichsmaske Helligkeit 200–255** innerhalb Motiv-Maske → Augen-Glow — Belichtung +0.2, Weiß +10, Sättigung −5
3. 🌫️ **Hintergrund** (invertierte Motiv-Maske) — Belichtung −0.3 bis −0.5, Klarheit −5 bis −10, Sättigung −10 (Bokeh-Beruhigung)

**Spezialregeln:**
- **HSL Orange/Yellow NIE ohne Präzision anfassen** — Fell/Federn/Haut liegen in diesen Buckets
- Schärfe-Radius 1.0–1.4 (größer als Landschaft, für Fell-Struktur)
- `noise_luminance` je nach ISO 15–40 wichtig
- Vignette dezenter als Landschaft (−5 bis −8), sonst wirkt Motiv unnatürlich isoliert
- Dehaze sparsam — kann Bokeh zerstören

**Crop-Empfehlung:**
- **4:5** oder **5:4** wenn Raum in Blickrichtung des Tieres wichtig ist (klassisches Wildlife-Prinzip: mehr Raum vor dem Tier als dahinter)
- **1:1** für Porträts einzelner Tiere, Augenhöhe
- **3:2** Original wenn Umgebung erzählerisch beiträgt (Habitat-Shot)
- **16:9** bei Rudel/Herden-Aufnahmen oder lateraler Bewegung
- Motiv-Positionierung nach Drittelregel, nicht zentriert (Ausnahme: symmetrisch frontale Portraits)
- Augenlinie auf oberem Drittel

---

### 🏙️ Stadt / Architektur

**Typische Szenen:** Gebäude, Straßen, Skylines, Innenräume, Blaue Stunde, Nachtszenen.

**Erkennungs-Signale:**
- `spatial.grid3x3` zeigt harte Luminanz-Sprünge (geometrische Muster)
- `hueDistribution` mehrere Buckets gleichzeitig aktiv (Tungsten-Gelb + Neon-Pink + Tageslicht-Blau)
- `tempSpread` im Original schon hoch (Mischlicht-Kontraste)
- Häufig Weitwinkel (14–35 mm) mit Verzeichnung
- Oft Dämmerung oder Nacht → höhere ISO

**Phase 3 — Varianten:**
- **A — Natural** (neutraler Weißabgleich, ausgeglichen)
- **B — Film-Noir** (Low-Key, hohe Kontraste, Farbsättigung moderat, Schatten verdichtet)
- **C — Neon-Cinematic** (Teal/Magenta-Grading, starke Farbblocks, moderne City-Ästhetik)

**Phase 5 — Masken:**
1. 🏢 Himmel oder Hintergrund (falls vorhanden) — Belichtung −0.2, Dehaze +15 (Blaue Stunde)
2. 💡 **Bereichsmaske Helligkeit 180–255** → Fensterlichter, Laternen, Neon — Belichtung −0.3 bis −0.5, Tönung +5 (gegen Tungsten-Gelb falls gewünscht)
3. 🌑 **Bereichsmaske Helligkeit 0–60** → tiefe Schatten — Tiefen +10-15, leichte Farb-Kühlung fürs Schatten-Separat
4. 🎨 Gezielte Farbflächen per Pinsel (z.B. eine beleuchtete Fassade) — Sättigung +10, Klarheit +5

**Spezialregeln:**
- **Verzeichnungskorrektur und Perspektiv-Upright zwingend** (meist `Level`-Option im Transformations-Panel)
- Chromatische Aberration unbedingt aktivieren (harte Kontrastkanten an Dachlinien)
- Clarity und Dehaze aggressiver erlaubt (+15 bis +25) — Strukturen profitieren
- Color Grading kann gegensätzliche Hues setzen (z.B. Shadows 220° / Highlights 30°) — Stadt verträgt Split-Looks
- HSL **alle** aktiven Buckets bearbeiten — keine monochromatic-Annahme
- Rauschreduzierung bei Nacht-Shots höher (`noise_luminance` 20–40)

**Crop-Empfehlung:**
- **Upright-Transformation VOR Crop** — kippende Gebäude gerade ziehen, danach croppen (sonst fehlt Material)
- **3:2** klassisch für Skylines, Straßenszenen
- **16:9** für Panorama-Skylines bei Blauer Stunde
- **9:16 vertikal** für einzelne Hochhäuser, enge Gassen, Reels
- **4:5** Instagram für Architektur-Details mit vertikaler Dominanz
- Führende Linien (Straßenfluchten, Dachkanten) müssen aufs Eck der Bildkante zulaufen oder strikt Drittelregel folgen
- Vertikale Kanten prüfen: müssen exakt senkrecht sein, sonst nachjustieren

---

### Hybride / unklare Fälle

Manche Travel-Bilder sind Mischformen — z.B. ein Tier in einer Landschaft, oder ein Mensch in einer Stadt. Claude entscheidet sich für den **dominanten** Typ (was erzählt das Bild primär?) und übernimmt ggf. einzelne Masken aus einem anderen Profil.

**Beispiel:** Wal vor Eisberg-Kulisse → primär Wildlife (Motiv steht im Zentrum, Handlung), aber Himmel-Maske aus Landschaftsprofil mitnehmen.

---

## Changelog

- **v3.4** — Phase 9 (Workflow-Retrospektive) hinzugefügt: strukturierte Reflexion nach Session mit Template, Trigger-Bedingungen und Akkumulationsregel. Anhang A erweitert um Diagnose-Regel bei unerwartetem Tool-Verhalten (temperature-Lektion), Snapshot-Namenskonvention (Nummernpräfixe statt willkürliche Sternchen). Selbstreferenziell: Diese Version ist das erste Retrospektive-Ergebnis, angewandt auf die eigene Entstehungssession.
- **v3.3** — Phase 2c (Zuschnitt & Ausrichtung) eingefügt zwischen Auto-Check und Varianten-Berechnung.
- **v3.2** — Anhang D (Motiv-Profile) hinzugefügt: Landschaft, Wildlife, Stadt.
- **v3.1** — Phase 2b (Auto als Referenz-Check) hinzugefügt. `auto_tone` als Sanity-Check für jede Session, `auto_white_balance` nur bei neutralen Szenen. Lernbeispiel Antarktis: Auto-WB hat Bild von Blau 100 % auf Orange 64 % umgestellt, weil es die Stimmung als WB-Fehler interpretiert.
- **v3.0** — Prozess-Workflow. Session-Choreographie statt Stilanleitung. Integriert Lessons aus der Antarktis-Session (cg_* quirk, Tool-Timeouts, Masken-Vorschlagsstrategie, temperature-Semantik als Kelvin-absolut).
- **v2.0** — Stilanleitung mit Kamera-Weiche und Regelwert-Tabellen.