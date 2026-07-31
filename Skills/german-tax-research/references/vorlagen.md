# Vorlagen (Deutsch)

Letter and document templates for an income tax case. Placeholders in square brackets. Everything here is written to be sent to the Finanzamt, so none of it carries a disclaimer, a status marker, or an internal note — keep those in the working analysis.

## Contents

- [Briefkopf](#briefkopf)
- [Einspruch, fristwahrend](#einspruch-fristwahrend)
- [Einspruchsbegründung](#einspruchsbegründung)
- [Antrag auf Aussetzung der Vollziehung](#antrag-auf-aussetzung-der-vollziehung)
- [Antrag auf Ruhen des Verfahrens](#antrag-auf-ruhen-des-verfahrens)
- [Antrag auf vorläufige Festsetzung](#antrag-auf-vorläufige-festsetzung)
- [Antrag auf Fristverlängerung](#antrag-auf-fristverlängerung)
- [Antrag auf schlichte Änderung](#antrag-auf-schlichte-änderung)
- [Anzeige und Berichtigung nach § 153 AO](#anzeige-und-berichtigung-nach--153-ao)
- [Antwort auf eine Belegaufforderung](#antwort-auf-eine-belegaufforderung)
- [Anlagenverzeichnis](#anlagenverzeichnis)
- [Eigenbeleg](#eigenbeleg)
- [Arbeitgeberbestätigung](#arbeitgeberbestätigung)
- [Tätigkeitsbeschreibung Arbeitszimmer](#tätigkeitsbeschreibung-arbeitszimmer)

## Briefkopf

```text
[Vorname Name]
[ggf. zweite steuerpflichtige Person]
[Straße Nr.]
[PLZ Ort]

Finanzamt [Name]
[Straße oder Postfach]
[PLZ Ort]

                                                  [Ort], den [TT. Monat JJJJ]

Steuernummer:          [21/101/02165]
Identifikationsnummer: [IdNr. Person 1] / [IdNr. Person 2]
Veranlagungszeitraum:  [JJJJ]
Bescheid vom:          [TT.MM.JJJJ]
Ihr Schreiben vom:     [TT.MM.JJJJ]

Betreff: [Einspruch / Einspruchsbegründung / Stellungnahme / Antrag …]
```

Number format throughout: `1.234,56 €`, `25,64 %`, `31. Juli 2026`.

## Einspruch, fristwahrend

File first, argue later. Everything the objection needs is the objector, the notice, and the statement that an objection is being made.

```text
Betreff: Einspruch gegen den Einkommensteuerbescheid [JJJJ] vom [TT.MM.JJJJ]

Sehr geehrte Damen und Herren,

gegen den oben bezeichneten Einkommensteuerbescheid [JJJJ] vom [TT.MM.JJJJ],
zugegangen am [TT.MM.JJJJ], lege ich hiermit fristgerecht

                              Einspruch

ein. Der Einspruch richtet sich zugleich gegen die Festsetzung des
Solidaritätszuschlags und der Kirchensteuer für denselben Veranlagungszeitraum.

Die Begründung reiche ich bis zum [TT.MM.JJJJ] nach. Ich bitte um Bestätigung
des Eingangs.

Mit freundlichen Grüßen


[Name]                                    [Name der zweiten Person]
```

Where a `Verspätungszuschlag` is contested, add a separate paragraph naming it expressly — it is a separate administrative act.

## Einspruchsbegründung

```text
Betreff: Einspruchsbegründung — Einkommensteuer [JJJJ], Bescheid vom [TT.MM.JJJJ]

Sehr geehrte Damen und Herren,

zu meinem Einspruch vom [TT.MM.JJJJ] begründe ich wie folgt.

I. Sachverhalt
[Chronologisch, mit Daten und Beträgen, ohne Wertung.]

II. Streitpunkte

1. [Kurzbezeichnung, z. B. „AfA Objekt Musterstraße 1"]
   Streitig ist [Betrag] €.
   a) Der Bescheid setzt [Betrag/Behandlung des Finanzamts] an.
   b) Nach § [Norm] sind [Rechtsfolge] anzusetzen, weil [Subsumtion].
   c) Nachweis: Anlage [Nr.].
   d) Ergebnis: Der Ansatz ist um [Betrag] € zu ändern.

2. [nächster Streitpunkt]

III. Anträge
Ich beantrage, den Einkommensteuerbescheid [JJJJ] vom [TT.MM.JJJJ]
dahingehend zu ändern, dass
1. [konkreter Änderungsantrag mit Betrag],
2. [weiterer Antrag].

IV. Anlagen
[Anlagenverzeichnis, siehe unten]

Mit freundlichen Grüßen
```

State the amount in dispute per item. An objection that argues without quantifying forces the office to compute the consequence, and it will compute it conservatively.

## Antrag auf Aussetzung der Vollziehung

```text
Betreff: Antrag auf Aussetzung der Vollziehung (§ 361 Abs. 2 AO) —
         Einkommensteuer [JJJJ], Bescheid vom [TT.MM.JJJJ]

Sehr geehrte Damen und Herren,

ich beantrage, die Vollziehung des oben bezeichneten Bescheids in Höhe von
[Betrag] € bis zur Entscheidung über meinen Einspruch vom [TT.MM.JJJJ]
auszusetzen.

An der Rechtmäßigkeit des Bescheids bestehen ernstliche Zweifel im Sinne des
§ 361 Abs. 2 Satz 2 AO, weil [Begründung mit Norm und Fundstelle].

[Optional:] Die Vollziehung hätte darüber hinaus eine unbillige, nicht durch
überwiegende öffentliche Interessen gebotene Härte zur Folge, weil [Grund].

Mit freundlichen Grüßen
```

Quantify the suspended amount. Note internally that a failed application costs 0.15 % per month under `§ 237 AO`.

## Antrag auf Ruhen des Verfahrens

```text
Betreff: Antrag auf Ruhen des Einspruchsverfahrens (§ 363 Abs. 2 AO) —
         Einkommensteuer [JJJJ]

Sehr geehrte Damen und Herren,

ich beantrage, das Einspruchsverfahren bis zum Vorliegen [der Bescheinigung
nach § 7i EStG der Behörde [Name], Aktenzeichen [AZ], Antrag vom [Datum] /
der Entscheidung des [BFH/BVerfG/EuGH] im Verfahren [Aktenzeichen]] ruhen zu
lassen.

Die ausstehende Bescheinigung ist Grundlagenbescheid im Sinne des § 175
Abs. 1 Satz 1 Nr. 1 AO; ihre Erteilung führt zur Änderung des Bescheids
unabhängig von dessen Bestandskraft. Ein Ruhen ist daher zweckmäßig
(§ 363 Abs. 2 Satz 1 AO).

Mit freundlichen Grüßen
```

## Antrag auf vorläufige Festsetzung

```text
Ich beantrage, die Festsetzung insoweit für vorläufig zu erklären
(§ 165 Abs. 1 Satz 1 AO), als sie [Bezeichnung des ungewissen Punktes]
betrifft. Der Punkt ist ungewiss, weil [Grund, z. B. das Bescheinigungs-
verfahren nach § 7i EStG noch nicht abgeschlossen ist].
```

## Antrag auf Fristverlängerung

Only for filing and submission deadlines — never for the objection period.

```text
Betreff: Antrag auf Fristverlängerung (§ 109 AO) — [Bezeichnung der Frist]

Sehr geehrte Damen und Herren,

ich beantrage, die mit Schreiben vom [Datum] gesetzte Frist zum [Datum] bis
zum [neues Datum] zu verlängern.

Grund: [konkret und belegbar — z. B. ausstehende Drittunterlagen mit Datum
der Anforderung, Erkrankung, Pflegefall in der Familie].

Ich versichere, dass die Unterlagen bis zum beantragten Termin vollständig
vorgelegt werden.

Mit freundlichen Grüßen
```

Name the concrete obstacle and, where possible, the date on which a third party was asked. A generic workload reason is regularly refused.

## Antrag auf schlichte Änderung

```text
Betreff: Antrag auf schlichte Änderung (§ 172 Abs. 1 Satz 1 Nr. 2 Buchst. a AO)
         — Einkommensteuer [JJJJ], Bescheid vom [TT.MM.JJJJ]

Sehr geehrte Damen und Herren,

ich beantrage, den oben bezeichneten Bescheid dahingehend zu ändern, dass
[konkreter Punkt mit Betrag]. Der Antrag beschränkt sich auf diesen Punkt.

Begründung: [kurz, mit Norm und Nachweis, Anlage [Nr.]].

Mit freundlichen Grüßen
```

The application must reach the office within the objection period. It is narrower than an objection — only the named point is reopened, and there is no `Verböserung` risk beyond it.

## Anzeige und Berichtigung nach § 153 AO

```text
Betreff: Anzeige und Berichtigung nach § 153 Abs. 1 Satz 1 Nr. 1 AO —
         Einkommensteuer [JJJJ]

Sehr geehrte Damen und Herren,

bei der Bearbeitung der Belegaufforderung für den Veranlagungszeitraum [JJJJ]
habe ich festgestellt, dass die Erklärung für den Veranlagungszeitraum [JJJJ]
in folgendem Punkt unrichtig ist:

[Sachverhalt, z. B.: Die Rechnung vom [Datum] über [Betrag] € wurde sowohl im
Veranlagungszeitraum [JJJJ] als auch im Veranlagungszeitraum [JJJJ] als
Arbeitsmittel erklärt.]

Zutreffend sind für [JJJJ] Arbeitsmittel in Höhe von [neuer Betrag] € statt
der erklärten [alter Betrag] €. Ich zeige dies hiermit unverzüglich an und
bitte um entsprechende Berichtigung.

Mit freundlichen Grüßen
```

## Antwort auf eine Belegaufforderung

Skeleton; the full procedure is in [`belegaufforderung-antwort.md`](belegaufforderung-antwort.md).

```text
Betreff: Einkommensteuer [JJJJ] — Unterlagen zu Ihrem Schreiben vom [Datum]

Sehr geehrte [Frau/Herr] [Name],

zu Ihrem Schreiben vom [Datum] übersende ich die angeforderten Unterlagen und
nehme zu den einzelnen Punkten wie folgt Stellung.

Zu 1. [Wortlaut oder Kurzfassung Ihrer Anforderung]
[Antwort. Herleitung des Betrags als kleine Tabelle. Verweis: Anlage [Nr.].]

Zu 2. …

Berichtigungen
Bei der Aufbereitung haben sich folgende Abweichungen zur eingereichten
Erklärung ergeben, die ich hiermit offenlege:
- [Position]: erklärt [Betrag] €, belegt [Betrag] €, Differenz [Betrag] €.
- [Position]: …

Anträge
[falls einschlägig]

Anlagenverzeichnis
[Tabelle]

Mit freundlichen Grüßen


[Name]                                    [Name der zweiten Person]
```

## Anlagenverzeichnis

```markdown
| Nr. | Bezeichnung | Seiten | Datei |
|---:|---|---:|---|
| 1 | Kaufvertrag und AfA-Herleitung Objekt [X] | 14 | anlage-01-kaufvertrag.pdf |
| 2 | Sachstand Bescheinigungsverfahren § 7i EStG | 14 | anlage-02-paragraph-7i.pdf |
| 3 | Mietkonto und Betriebskostenabrechnung [JJJJ] | 72 | anlage-03-mietkonto.pdf |
```

Page counts come from the built files, never from an estimate. Every number named in the letter appears here, and every row here is named in the letter.

## Eigenbeleg

For an expense where no third-party receipt is obtainable.

```text
                                Eigenbeleg

Steuerpflichtige/r:   [Name]
Steuernummer:         [Nr.]
Veranlagungszeitraum: [JJJJ]

Datum der Aufwendung: [TT.MM.JJJJ]
Empfänger:            [Name und Ort]
Gegenstand:           [z. B. Bahnfahrt Flughafen–Innenstadt, Oslo]
Betrag:               [Betrag] [Währung]  (= [Betrag] €, Umrechnung [Kurs])
Beruflicher Anlass:   [Veranstaltung, Datum, Ort]
Grund für den Eigenbeleg: [z. B. Fahrscheinautomat ohne Belegausgabe;
                          Zahlung bar, keine Quittung erhältlich]

Ich versichere die Richtigkeit dieser Angaben.

[Ort], den [TT. Monat JJJJ]


____________________________
[Name]
```

## Arbeitgeberbestätigung

Closes the fourth proof type — that no third party bore the cost.

```text
                          Bestätigung des Arbeitgebers

Hiermit bestätige ich, dass [Frau/Herr] [Name], beschäftigt bei
[Arbeitgeber] seit [Datum], für die nachfolgend genannten Aufwendungen
weder eine Erstattung noch eine Kostenübernahme, weder vollständig noch
teilweise, erhalten hat:

- [Veranstaltung/Aufwendung], [Zeitraum], [Betrag] €
- [weitere Position]

Eine Freistellung von der Arbeitszeit [wurde/wurde nicht] gewährt.

[Ort], den [TT. Monat JJJJ]


____________________________
[Name, Funktion], Stempel
```

Where an employer will not issue this in time, produce the same content as a signed declaration by the taxpayer, name the request and its ticket number, and say that the employer confirmation will follow.

## Tätigkeitsbeschreibung Arbeitszimmer

```text
              Beschreibung der Nutzung des häuslichen Arbeitszimmers
                        Veranlagungszeitraum [JJJJ]

Objekt:           [Anschrift]
Raum:             [Lage im Grundriss], [Fläche] m² von [Gesamtfläche] m²
Ausstattung:      [Schreibtisch, Bürostuhl, Computer, Fachbibliothek, …]
Tätigkeit:        [konkrete Tätigkeiten, mit Umfang und Häufigkeit]
Nutzung:          ausschließlich beruflich; eine private Mitbenutzung findet
                  nicht statt.
Anderer Arbeitsplatz: [Es steht kein anderer Arbeitsplatz zur Verfügung, weil
                  … / Ein Arbeitsplatz beim Arbeitgeber steht an [n] Tagen
                  je Woche zur Verfügung.]
Nachweise:        Grundriss (Anlage [Nr.]), Flächenaufstellung (Anlage [Nr.]),
                  Arbeitsvertrag (Anlage [Nr.])

[Ort], den [TT. Monat JJJJ]


____________________________
[Name]
```

Where an area was derived arithmetically rather than measured, say so in the document: `Die Fläche des Treppenhauses ist rechnerisch aus der Abstimmung auf die vertragliche Gesamtfläche abgeleitet; ein Aufmaß liegt nicht vor.`
