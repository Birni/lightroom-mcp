# 📷 Lightroom Edit Workflow v3.5 — Claude-gestützt

> **Zweck:** Session-Choreographie für Claude + Lightroom MCP.
> Sagt wann welche Funktion aufgerufen wird und wo du (User) eingreifst.
> Die konkreten Stilwerte sind **nicht** hier — die leitet Claude aus der Analyse ab.

---

## So benutzt du diesen Workflow

Öffne ein Bild im Develop-Modul, starte Claude mit:
> *„Bearbeite das aktive Bild nach Workflow v3.5"* (+ ggf. Stilwunsch wie „cool-dramatisch" oder „natürlich-warm")

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
5. `lightroom:create_snapshot` als `01_Auto-Referenz`
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
- Empfohlenes Seitenverhältnis (3:2 original, 16:9 Panorama, 19:9 Ultra-Panorama, 4:5 Instagram-Portrait, 1:1 quadratisch, 9:16 Reels)
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
1. `lightroom:reset_develop_settings` (nur vor Variante A — danach wird auf Varianten-Basis weitergearbeitet, oder alternativ alle Werte explizit setzen statt zu resetten, um User-gesetzten Crop zu schützen)
2. **Pre-Set Sektions-Checkliste durchgehen** (siehe unten)
3. `lightroom:set_develop_settings` mit kompletter Werte-Vorgabe
4. `lightroom:create_snapshot` mit klarem Namen (`02_VarA_[Label]`, `02_VarB_[Label]`, `02_VarC_[Label]`)
5. `lightroom:analyze_edit` zur Verifikation der Variante

### 🔴 Pre-Set Sektions-Checkliste (vor jedem `set_develop_settings`)

Diese Checkliste ist **verpflichtend** vor jedem Varianten-Aufruf. Claude muss alle sechs Lightroom-Panels bewusst durchgehen, auch wenn der Wert bewusst auf 0 bleibt. Ohne explizites Durchgehen fehlen systematisch einzelne Sektionen (Lesson aus v3.5-Entstehungssession: drei Sektionen in einer Session vergessen — Details/Maskieren, Color Grading unter Wirkungsschwelle, Tonwertkurve komplett).

- ☐ **Grundeinstellungen** — `exposure`, `contrast`, `highlights`, `shadows`, `whites`, `blacks`, `texture`, `clarity`, `dehaze`, `vibrance`, `saturation`, ggf. `temperature` / `tint` (siehe Anhang A zu Kelvin-Absolut-Semantik)
- ☐ **Tonwertkurve (parametrisch)** — `tone_shadows`, `tone_darks`, `tone_lights`, `tone_highlights`. Point curves werden nicht benutzt (User-Präferenz). Matte-Lift in den Tiefen (`tone_shadows` +8 bis +12) ist Default für Antarktis-/Dokumentarisch-Stile
- ☐ **HSL (Hue/Sat/Lum)** — nur die Buckets bearbeiten, die in `hueDistribution` ≥5 % zeigen. Monochrome Szenen: meist nur `blue`/`aqua`. Ghost-Korrekturen in leeren Buckets vermeiden
- ☐ **Farbmischung / Color Grading** — `cg_shadow_hue`/`_sat`, `cg_highlight_hue`/`_sat`, `cg_balance`. **Sat-Werte: entweder 0 oder ≥10, niemals 1–9** (Wirkungsschwelle — siehe Anhang A). Bei Antarktis-Szenen: warm-amber Shadows (35°) statt Blau, sonst werden Felsen künstlich kühl
- ☐ **Details** — `sharpness`, `sharpen_radius`, `sharpen_detail`, **`sharpen_masking`** (niemals Default 0 lassen für Landschaft/Stadt — glatte Flächen werden sonst mitgeschärft), `noise_luminance`, `noise_color`. Baselines pro Kamera und Motiv siehe [Anhang C](#anhang-c--kamera-grundlagen)
- ☐ **Effekte** — `vignette_amount`, `vignette_midpoint`, `vignette_feather`, `vignette_roundness`, ggf. `grain_*`

**Die drei Varianten werden an den Motiv-Typ aus Phase 2 angepasst (siehe [Anhang D](#anhang-d--motiv-profile)).**

Standard-Varianten für **Landschaft** (Default, wenn Motiv-Typ nicht eindeutig):

| Variante | Charakter | Typischer Zweck |
|---|---|---|
| **A — Dokumentarisch** | moderate Kontraste, natürliche Farben, Felsen offen, Matte-Lift in Tiefen, CG optional dezent (sat 10, Richtung aus Analyse) | Publikation, Reportage, Archiv |
| **B — Dramatisch** | tiefe Schwarzpunkte, hohe Weißpunkte, dominante-Farbe HSL-Push, Vignette, CG sat ≥15 (Richtung aus Analyse) | Instagram, Portfolio, Druck |
| **C — Kontext-Wildcard** | dritte Variante passt sich dem Bildinhalt an — siehe Kontext-Tabelle unten | Stilexploration, Abwechslung |

**CG-Richtung aus Analyse ableiten:**

| Signal | Shadows-Hue | Highlights-Hue | Logik |
|---|---|---|---|
| `dark.bMinusR` < −20 (Schatten schon warm) | kühl (210–220°) | warm (35–45°) | Gegenpol setzen, Separation verstärken |
| `dark.bMinusR` > +10 (Schatten schon kühl) | warm (30–45°) | kühl (200–220°) | Gegenpol setzen, Felsen/Struktur nicht weiter verkühlen |
| `tempSpread` < 20 (kaum Farbtrennung) | warm (35°) | kühl (210°) | Split erzeugen wo keiner ist |
| `tempSpread` > 50 (starke Trennung) | CG sparsam oder aus | CG sparsam oder aus | Vorhandene Separation reicht, CG kippt schnell |
| Warmes Licht dominant (`bMinusR` < −25) | kühl (210°) | warm beibehalten oder neutral | Kühle Schatten als Anker gegen Gesamtwärme |

**Kontext-Tabelle für Variante C:**

| Bildkontext | Variante C wird zu | Charakter |
|---|---|---|
| Szene hat natürliche Warm/Kalt-Trennung (tempSpread 25–50) | **Cinematic Split** | CG-Richtung aus Tabelle oben, sat ≥10, Farbtrennung verstärken |
| Monochrome/farbarme Szene (hueDistr. ≥90% ein Bucket, unsaturatedPct >60%) | **Schwarzweiß** | Kontrast-getrieben, Rotfilter-Simulation für Himmel-Drama |
| Nebel, Dunst, weiches Licht (DR <4, saturation median <15) | **Atmosphärisch/Soft** | Lifted Blacks (+tone_shadows +15–20), reduzierter Kontrast, Pastelltöne, kein Dehaze |
| Warmes Licht dominant (bMinusR < −25, Orange/Yellow >50%) | **Warm-Dramatic** | Wie B, aber warme Farbtemperatur beibehalten statt kühl ziehen |

*Schwellenwerte vorläufig — wird über Sessions kalibriert.*

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
2. `lightroom:set_develop_settings` mit Delta — **auch hier Sektions-Checkliste prüfen, falls neue Sektion betroffen**
3. `lightroom:analyze_edit`
4. Vergleichstabelle vorher/nachher

**Typische Eingriffe:**
- Kontrast, Belichtung, Farbbalance
- HSL Gelb/Orange defensiv gegen Gelbstich im Nebel
- Color Grading Sättigung hoch (Werte ≥10 damit sichtbar, siehe [Anhang A](#anhang-a--tool-quirks))
- Parametrische Kurve nachziehen (Matte-Lift in Tiefen falls Felsen zuloßen)

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

### 🟡 Masken-Reihenfolge & Interaktions-Warnung

Die Reihenfolge, in der Masken gesetzt werden, beeinflusst das Ergebnis sichtbar. AI-Masken können in angrenzende Bereiche „einbluten", was nachgelagerte Masken unterwandert.

**Empfohlene Reihenfolge für Landschaft:**

1. **🌫️ Himmel-Maske zuerst** — größte Fläche, stärkster Hebel. Gibt Basis für die Einschätzung, was danach noch nötig ist.
2. **🪨 Felsen/Motiv (invertierter Himmel oder „Motiv auswählen")** — nachdem Himmel gesetzt ist, sieht man welche Bereiche noch offen sind
3. **🧊 Schnee-/Eis-Bereichsmaske danach** — hier passiert häufig ein Interaktions-Effekt:
   - Die AI-Maske „Himmel auswählen" greift oft in **angrenzende helle Bereiche** (z.B. schneebedeckte Gipfel hinter dem Himmel, helle Wolkenkanten).
   - Nach der Himmel-Maske ist die Schnee-Bereichsmaske möglicherweise **weniger stark** als erwartet, weil der Helligkeitsbereich bereits reduziert wurde.
   - **Gegenmaßnahme:** Werte der Schnee-Bereichsmaske 20–30 % stärker ansetzen als ursprünglich geplant, wenn Himmel-Maske Belichtung ≤ −0.2 hatte. Oder: Schnee vor Himmel setzen (ungewöhnlich, aber funktional)
4. **💧 Vordergrund/Wasser zuletzt** — am wenigsten Interaktionseffekte

**Reality-Check nach Himmel-Maske (empfohlen):** `analyze_edit` laufen lassen, `bright.meanLum` und `thirds[0]` checken. Wenn `bright.meanLum` um > 20 gefallen ist, sind auch die Schneeberge mit heruntergezogen worden — dann Schnee-Maske verstärken.

**Lesson aus v3.5-Entstehungssession:** Himmel-Maske senkte `thirds[0]` um −36, aber auch `bright.meanLum` um −25 (Schneeberge betroffen). Die geplante Schnee-Bereichsmaske (+0.10 Belichtung) konnte nicht kompensieren — sichtbares whites%-Einbrechen von 5.6 auf 0.2. Lösung im Einzelfall: globalen Weißpunkt nachträglich minimal anheben (wirkt primär auf Schneeberge, weil Himmel durch Maske gedeckelt).

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
- `whites %` nach Masken < 1 UND vor Masken > 3 → Weißpunkt durch Himmel-Maske verloren (siehe Phase 5 Interaktions-Warnung). Globalen `whites`-Regler um +5 bis +10 nachziehen.

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
1. Finaler Snapshot mit Stern-Präfix: `lightroom:create_snapshot` als `★_FINAL_[Variante]+Masken`
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
- User fragt mehrfach „Warum fehlt X?" auf Sektionen, die standardmäßig im Workflow sein sollten → mehrere Symptome desselben Root-Causes, sofort reagieren

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

**Ausnahme — Root-Cause-Cluster:** Wenn mehrere 🔴-Einträge denselben Root-Cause haben (z.B. drei vergessene Develop-Sektionen alle auf fehlende Checkliste zurückführbar), gehen sie als **eine kohärente Änderung** zusammen rein, auch wenn es drei Symptome sind. Nicht auf weitere Sessions warten — gleiche Ursache würde beim nächsten Bild wieder zuschlagen.

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

### 🔴 Sanity-Check-Liste (vor jedem `set_develop_settings`)

Ergänzung zur Pre-Set Sektions-Checkliste in Phase 3. Diese Regeln betreffen Parameter-Werte, nicht Sektions-Vollständigkeit:

- **`cg_*_sat`** (Color Grading Sättigung Shadow/Highlight): entweder **0** oder **≥10** — niemals 1–9. Zwischenwerte sind in der gerenderten Ausgabe faktisch nicht messbar. Wer „dezentes Color Grading" will, lässt es aus (0) — denn technisch gibt es kein dezentes CG unter 10.
- **`sharpen_masking`**: niemals bei Default 0 lassen für Landschaft/Stadt. Glatte Flächen (Himmel, Meer, Wände) werden sonst mitgeschärft und zeigen Rauschen-Amplifikation. Baselines siehe Anhang C.
- **`tone_*` (parametrische Kurve)**: wenn User-Memory „Always use parametric curve" enthält, gehört mindestens **ein** `tone_*`-Wert zu jeder ernsthaften Variante, auch wenn nur leicht. Null-Kurve ist ok bei reiner Farbstil-Exploration, aber nicht als Default.
- **`temperature`**: 0 oder Werte < 2000 K niemals setzen (Blau-Crash). Wenn unverändert: Parameter weglassen, nicht auf 0 setzen.
- **HSL-Sparsamkeit**: in monochromen Szenen (hueDistribution ≥95 % ein Bucket) nur den dominanten Bucket anfassen. Ghost-Korrekturen in leeren Buckets produzieren unvorhersehbare Ergebnisse, wenn das Bild später leicht nachbelichtet wird.

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
| Phase 3 bei Korrektur-Iteration | `02_VarX_[Label]_v2`, `_v3` | `02_VarA_Dokumentarisch_v3` |
| Phase 4 (Iterationen) | `03_Iter1_[Änderung]`, `03_Iter2_…` | `03_Iter1_Gelb-Fix` |
| Phase 5 vorher | `04_Pre-Masken` | `04_Pre-Masken` |
| Phase 8 (Final) | `★_FINAL_[Variante]+Masken` | `★_FINAL_Dokumentarisch+Masken` |

**Aufräumen am Session-Ende:** Iter-, Pre- und `_vN`-Zwischenversionen können gelöscht werden, sobald der Final-Snapshot steht. Baseline, Auto-Referenz und Final-Snapshot immer behalten.

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

### 🔴 Schärfungs-Baselines (alle vier Regler)

Standard-Werte pro Kamera und Motiv-Typ. Bei abweichendem ISO oder besonderem Motiv (z.B. Portrait, Makro) einzeln anpassen.

| Kamera | Motiv | Betrag | Radius | Details | **Maskieren** | Luminanz-NR |
|---|---|---|---|---|---|---|
| R6 CR3 | Landschaft | 40 | 0.9 | 25 | **40** | 0–10 |
| R6 CR3 | Wildlife | 50 | 1.2 | 30–35 | **15–25** | 15–40 (je ISO) |
| R6 CR3 | Stadt / Architektur | 45 | 1.0 | 25–30 | **25–35** | 0–15 |
| R6 CR3 | Portrait | 35 | 1.4 | 20 | **50–60** | 10–20 |
| S21 JPEG | alle | 20 | 0.8 | 15 | **50** | Prüfen, meist 0 |
| S21 JPEG | Nacht/Low-Light | 15 | 0.8 | 15 | **60** | 20–30 |
| Insta360 JPEG | Action | 35 | 1.0 | 25 | **35** | 15–25 |

**Faustregel Maskieren:**
- **Hoch (40+):** glatte Flächen sollen glatt bleiben (Himmel, Haut, Bokeh, Wände, Meer)
- **Mittel (25–35):** gemischte Szenen mit Kanten und Flächen (Stadt, Architektur)
- **Niedrig (15–25):** Fell, Federn, Haar, kleinteilige organische Strukturen, die von Schärfe profitieren

**Prüfung per Alt-/Opt-Klick auf Maskieren-Regler in LR:** zeigt Schwarz-Weiß-Vorschau, wo geschärft wird. Weiß = wird geschärft, Schwarz = bleibt unangetastet. Für Landschaft sollten Himmel und Meer im Idealfall größtenteils schwarz sein.

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
- **A — Dokumentarisch** (offene Tiefen, Matte-Lift, natürliche Farben, **CG bewusst aus**)
- **B — Cool-Dramatic** oder **Warm-Dramatic** je nach Lichtstimmung (aggressive Schwarz-/Weißpunkte, HSL-Push der dominanten Farbe, warm-amber CG Shadows mit sat ≥10)
- **C — Teal/Orange Cinematic** (Color Grading-Split, 210° Lichter / 35° Schatten, sat ≥15)

**Phase 3 — Schärfungs-Baselines:** Betrag 40, Radius 0.9, Details 25, **Maskieren 40**

**Phase 3 — Kurve (Default):** `tone_shadows` +8 bis +12 (Matte-Lift), `tone_lights` −2 bis −5 (Himmel-Verdichtung), `tone_highlights` +3 bis +8 (Schnee/Eis-Lift)

**Phase 5 — Masken:**
1. 🌫️ Himmel auswählen — Belichtung −0.2 bis −0.3, Lichter −15, Dehaze +10-15
2. 🪨 Motiv (Berg/Fels) auswählen oder Himmel invertieren — Tiefen +10-20, Struktur +10-15
3. 🧊 Helligkeits-Bereichsmaske für Glanzlichter (Schnee/Eis/Wellenschaum) — Belichtung +0.15, Tönung +3 (gegen Cyan). **Bei starker Himmel-Maske 20–30 % verstärken** (siehe Phase 5 Interaktions-Warnung)
4. 💧 Vordergrund/Wasser unteres Drittel — Klarheit +5, Dehaze +5

**Spezialregeln:**
- `auto_white_balance` **nicht** aktivieren bei dominanter Farbstimmung (Nebel, Dämmerung, Polar-Blau)
- `spatial.thirds` direkt als Leitfaden verwenden

**Crop-Empfehlung:**
- **3:2** Original (Standard, wenn Komposition hoch/breit ausgewogen)
- **16:9** Panorama-Crop bei dominanter Horizontale (Meer, Bergkette, Wüste)
- **19:9** Ultra-Panorama bei sehr breiten Landschaften mit strukturarmem Himmel
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
- **A — Natural** (neutrale Farben, moderate Kontraste, Tier-Farbe authentisch, CG meist aus)
- **B — Low-Key Drama** (Hintergrund abgedunkelt, Motiv hell, starker Subjekt-Fokus)
- **C — High-Key Clean** (helle Töne, Hintergrund nahezu weiß, Motiv-Details fein)

**Phase 3 — Schärfungs-Baselines:** Betrag 50, Radius 1.2, Details 30–35, **Maskieren 15–25** (niedrig, damit Fell/Federn profitieren), Luminanz-NR je ISO 15–40

**Phase 3 — Kurve (Default):** `tone_shadows` +5 (moderate Tiefen-Öffnung), `tone_lights` 0 bis +3, `tone_highlights` +3 (Licht-Akzente)

**Phase 5 — Masken:**
1. 🐾 **„Motiv auswählen"** (AI-Maske) — Belichtung +0.1 bis +0.2, Struktur +10-15, Klarheit +5, Schärfe-Boost
2. 👁️ **Bereichsmaske Helligkeit 200–255** innerhalb Motiv-Maske → Augen-Glow — Belichtung +0.2, Weiß +10, Sättigung −5
3. 🌫️ **Hintergrund** (invertierte Motiv-Maske) — Belichtung −0.3 bis −0.5, Klarheit −5 bis −10, Sättigung −10 (Bokeh-Beruhigung)

**Spezialregeln:**
- **HSL Orange/Yellow NIE ohne Präzision anfassen** — Fell/Federn/Haut liegen in diesen Buckets
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
- **C — Neon-Cinematic** (Teal/Magenta-Grading, starke Farbblocks, moderne City-Ästhetik, CG sat ≥15)

**Phase 3 — Schärfungs-Baselines:** Betrag 45, Radius 1.0, Details 25–30, **Maskieren 25–35** (mittel, Balance zwischen Kantenschärfe und glatten Wänden), Luminanz-NR 0–15 (Nacht: 20–40)

**Phase 3 — Kurve (Default):** `tone_shadows` +3 bis +8, `tone_lights` −5 (Verdichtung), `tone_highlights` −3 bis −8 (Lichter-Kontrolle bei Nachtszenen mit hellen Quellen)

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

- **v3.6** — Zwei Änderungen aus Session 4F4A3282 (Bark Europa, Umweltporträt mit Gletscherpanorama): (1) **Variante A CG-Regel gelockert**: „CG bewusst aus" → „CG optional dezent (sat 10, Richtung aus Analyse)". Dezentes Color Grading und Dokumentarisch schließen sich nicht aus, solange es die vorhandene Stimmung unterstützt statt eine neue aufzudrücken. (2) **Variante C von fixem Teal/Orange zu Kontext-Wildcard umgebaut**: Dritte Variante passt sich dem Bildinhalt an — Cinematic Split bei natürlicher Warm/Kalt-Trennung, Schwarzweiß bei monochromen Szenen, Atmosphärisch/Soft bei Nebel/Dunst, Warm-Dramatic bei warmem Licht. Auswahl über Analyse-Signale (`tempSpread`, `hueDistribution`, `DR`, `bMinusR`). (3) **CG-Richtungstabelle ergänzt**: Shadows/Highlig
- **v3.5** — Drei 🔴-Eigenfehler aus einer Session (Bark Europa, Antarktis-Küstenlandschaft 4F4A3249) zu einer kohärenten Änderung zusammengefasst, weil alle denselben Root-Cause haben — fehlende Sektions-Schablone in Phase 3. Ergänzungen: (1) Phase 3 **Pre-Set Sektions-Checkliste** über alle 6 LR-Panels (Grundeinstellungen / Kurve / HSL / Color Grading / Details / Effekte), auch wenn bewusst 0; (2) Anhang A **Sanity-Check-Liste** mit konkreten Parameter-Regeln (cg_*_sat 0 oder ≥10, sharpen_masking nie bei 0 für Landschaft/Stadt, tone_* als Pflicht bei Memory-Präferenz); (3) Anhang C **Schärfungs-Baselines** als Tabelle pro Kamera und Motiv-Typ inkl. Maskieren-Wert; (4) Anhang D pro Motiv-Profil jetzt Schärfungs-Baselines und Kurven-Defaults redundant aufgeführt für schnelleren Lookup in Phase 3; (5) Phase 5 **Masken-Reihenfolge und Interaktions-Warnung** (Himmel-AI-Maske blutet in Schneeberge → Schnee-Bereichsmaske verstärken oder Reality-Check einbauen); (6) Phase 6 Checkliste um `whites%`-Einbruch nach Himmel-Maske ergänzt; (7) Snapshot-Schema um `_vN`-Suffix erweitert für Korrektur-Iterationen; (8) Phase 9 Akkumulationsregel um Root-Cause-Cluster-Ausnahme erweitert (mehrere 🔴 mit gleicher Ursache = eine Änderung, sofort).
- **v3.4** — Phase 9 (Workflow-Retrospektive) hinzugefügt: strukturierte Reflexion nach Session mit Template, Trigger-Bedingungen und Akkumulationsregel. Anhang A erweitert um Diagnose-Regel bei unerwartetem Tool-Verhalten (temperature-Lektion), Snapshot-Namenskonvention (Nummernpräfixe statt willkürliche Sternchen). Selbstreferenziell: Diese Version ist das erste Retrospektive-Ergebnis, angewandt auf die eigene Entstehungssession.
- **v3.3** — Phase 2c (Zuschnitt & Ausrichtung) eingefügt zwischen Auto-Check und Varianten-Berechnung.
- **v3.2** — Anhang D (Motiv-Profile) hinzugefügt: Landschaft, Wildlife, Stadt.
- **v3.1** — Phase 2b (Auto als Referenz-Check) hinzugefügt. `auto_tone` als Sanity-Check für jede Session, `auto_white_balance` nur bei neutralen Szenen. Lernbeispiel Antarktis: Auto-WB hat Bild von Blau 100 % auf Orange 64 % umgestellt, weil es die Stimmung als WB-Fehler interpretiert.
- **v3.0** — Prozess-Workflow. Session-Choreographie statt Stilanleitung. Integriert Lessons aus der Antarktis-Session (cg_* quirk, Tool-Timeouts, Masken-Vorschlagsstrategie, temperature-Semantik als Kelvin-absolut).
- **v2.0** — Stilanleitung mit Kamera-Weiche und Regelwert-Tabellen.