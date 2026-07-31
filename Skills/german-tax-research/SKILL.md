---
name: german-tax-research
description: >-
  German income tax (Einkommensteuer) case work: reviews an assessment notice,
  computes the objection deadline, answers a Belegaufforderung point by point,
  reconciles every figure against the transmitted return, and drafts Einspruch,
  Begründung, and applications in formal German with exact § citations.
  USE FOR: Einkommensteuer, Steuererklärung, ELSTER, Steuerbescheid prüfen,
  Einspruch, Einspruchsbegründung, Belegaufforderung, Einspruchsfrist,
  Bekanntgabefiktion, Aussetzung der Vollziehung, Verspätungszuschlag,
  Schätzung, Anlage V, Vermietung und Verpachtung, AfA, § 7i Denkmal,
  Werbungskosten, Arbeitszimmer, Homeoffice-Pauschale, Fortbildungskosten,
  Reisekosten, Arbeitsmittel, Sonderausgaben, Kapitalerträge,
  Lebensmittelpunkt, § 153 AO, German income tax return.
  DO NOT USE FOR: Miet- or Arbeitsrecht argumentation (use
  german-legal-research), building the Anlagen PDF (use
  evidence-package-assembly), reading a PDF or XLSX (use pdf-to-markdown,
  xlsx-to-markdown), tax law outside Germany.
compatibility: >-
  Repository-based case work in Markdown. Optional: PowerShell 7 for the
  bundled deadline script, pandoc plus headless Edge for rendering letters.
---

# German Tax Research (Einkommensteuer)

Turn a Finanzamt letter and a pile of receipts into a filing that survives an examiner: every figure traceable to a document, every legal statement carrying its § citation, every deadline computed rather than estimated.

This Skill supplies the domain material for the [`tax-researcher`](../../Agents/tax-researcher.agent.md) agent, and works standalone in any repository that holds a tax case.

## When to Use

- A `Steuerbescheid` arrived and must be checked, or an `Einspruch` must be filed.
- The Finanzamt sent a `Belegaufforderung` and expects a point-by-point answer with evidence.
- A `Steuererklärung` is being prepared and a position needs a legal basis and a proof plan.
- Rental income, depreciation, home office, training costs, or capital income must be quantified.
- A deviation, duplicate claim, or wrong-year claim surfaced and the correction route is unclear.

## Outcome

A submission-ready German document in which every asserted amount is derived in the text itself, every derivation ends at a named `Anlage`, every legal proposition names its norm, and the deadline it answers is computed from the notice date.

## Non-negotiables

1. **Never invent a norm, a BFH decision, a BMF letter, or a BStBl reference.** State uncertainty instead. A fabricated citation destroys the whole submission's credibility.
2. **Cite to the smallest unit**: `§ 9 Abs. 1 S. 3 Nr. 5 S. 3 EStG`, not "§ 9 EStG".
3. **Every figure traces to a document or to a disclosed assumption.** No figure enters a letter because a spreadsheet produced it.
4. **Submission artifacts carry no internal caveats.** No RDG or StBerG disclaimer, no reviewer note, no status marker, no "intern offen" line in anything that goes to the Finanzamt. Keep those in the working analysis.
5. **Steuerberatervorbehalt (§§ 2, 3 StBerG).** The taxpayer may act for themselves; this Skill never produces commercial advice for third parties. Working analyses end with the disclaimer, submissions do not.

## Workflow

Five phases, in order. Skipping PRÜFEN produces a confident letter about the wrong norm.

### 1 — ERFASSEN (capture)

Build a dated timeline before any assessment: notice date, deemed notification, objection filed, every Finanzamt letter, every deadline extension, every submission. Record `Steuernummer`, `IdNr.` of both spouses on joint assessment, `Veranlagungszeitraum`, and whether the notice carries `§ 164 AO` (Vorbehalt der Nachprüfung) or `§ 165 AO` (Vorläufigkeit) — both change which correction route is open.

Read scanned notices against the PDF, not against the OCR text. Recurring OCR corruptions in German notices: `Becheid`, `Sumne`, `Einkomnens`, `Vernietung`, `nithin`, and `§` read as `S`, `$`, or `8`. Verify every quoted sentence against the image before it enters a letter.

### 2 — PRÜFEN (examine)

For each disputed item, name the `Anspruchsgrundlage` and the procedural norm separately. Material law in EStG/EStDV; procedure in AO. Then determine who bears the burden: the Finanzamt for anything that raises tax, the taxpayer for anything that lowers it. Assume no deduction survives without proof the taxpayer can produce.

Check whether the position was accepted in a prior year. That is a strong practical argument and worth quoting from the earlier notice — but `Abschnittsbesteuerung` means it does not bind the Finanzamt for the year at hand. Say so in the working analysis so nobody relies on it as a guarantee.

### 3 — SUBSUMIEREN (apply)

Use `Gutachtenstil` per disputed item: Obersatz naming the norm and the amount, definition of the contested element, subsumption against the actual facts, result. Work through each element separately and address the Finanzamt's counter-reading explicitly — a symmetrical argument survives the examiner's rebuttal, a one-sided one invites it.

### 4 — FASSEN (draft)

Pick the instrument by what the Finanzamt has already done. Full table and letter templates in [`references/vorlagen.md`](references/vorlagen.md).

| Situation | Instrument |
|---|---|
| Notice is wrong, deadline running | `Einspruch` (fristwahrend, § 355 AO), Begründung nachreichen |
| Small correctable point, no dispute | `Antrag auf schlichte Änderung` (§ 172 Abs. 1 S. 1 Nr. 2 a AO) |
| Payment demand pending, prospects good | `Antrag auf Aussetzung der Vollziehung` (§ 361 AO) |
| A Grundlagenbescheid or pilot case is outstanding | `Antrag auf Ruhen` (§ 363 Abs. 2 AO) or vorläufige Festsetzung (§ 165 AO) |
| Return deadline cannot be met | `Fristverlängerung` (§ 109 AO) — never for the Einspruchsfrist |
| Deadline missed without fault | `Wiedereinsetzung` (§ 110 AO), within one month of the impediment ending |
| Own error found after filing | `Anzeige und Berichtigung` (§ 153 AO) |
| Finanzamt asked for documents | Point-by-point `Stellungnahme` with `Anlagenverzeichnis` |

### 5 — LIEFERN (deliver)

Run the [Verification](#verification) block. Then send on a channel that proves receipt: `Mein ELSTER` produces a `Transferticket`, plain email to the `Poststelle` does not. Use both when the deadline is final. Check the authority mailbox attachment limit before sending; split into numbered part-messages (`Mail 1 von 5`) with continuous `Anlage` numbering when the package exceeds it.

## Deadlines: compute, never estimate

The two-step rule that trips people: a posted notice is deemed notified on the **fourth day** after it was posted (`§ 122 Abs. 2 Nr. 1 AO`, since the PostModG on 1 January 2025 — three days before that), and the objection period is one month from that date (`§ 355 Abs. 1 AO`), computed under `§ 108 AO` with `§§ 187, 188 BGB`. If the deemed-notification day or the deadline day falls on a Saturday, Sunday, or public holiday, it moves to the next working day (`§ 108 Abs. 3 AO`).

```powershell
pwsh -File scripts/Get-SteuerFrist.ps1 -BescheidDatum '2026-02-25' -Bundesland Niedersachsen
```

The script prints the deemed notification date, the objection deadline, and every weekend or holiday shift it applied. Do not compute these dates by hand in a letter.

The `Einspruchsfrist` is **not extendable**. A `Fristverlängerung` under `§ 109 AO` covers filing deadlines, never the objection period; the only relief after expiry is `§ 110 AO`. Where the notice carries no or a defective `Rechtsbehelfsbelehrung`, the period is one year (`§ 356 Abs. 2 AO`).

Filing deadlines, late-filing surcharges, interest, and the assessment limitation period: [`references/fristen-und-verfahren.md`](references/fristen-und-verfahren.md).

## Bescheidprüfung

Ten checks, in this order. The first four are formal and decide whether the substantive ones matter.

1. Addressee complete — on joint assessment both spouses must be named.
2. `Steuernummer`, `Veranlagungszeitraum`, notice date, and the tax type present.
3. `Rechtsbehelfsbelehrung` present and correct.
4. `§ 164 AO` reservation or `§ 165 AO` provisionality noted, including its stated scope.
5. Declared figures against assessed figures, line by line — the `Erläuterungen` state the deviations the Finanzamt made.
6. Every deviation: does the notice give a reason, and is the reason a legal one or a mere assertion?
7. Ancillary notices — `Solidaritätszuschlag`, `Kirchensteuer`, `Zinsen` (§ 233a AO), `Verspätungszuschlag` (§ 152 AO). The surcharge is a separate administrative act and needs its own objection.
8. Payment date and whether enforcement suspension is needed.
9. Whether an objection risks `Verböserung` (§ 367 Abs. 2 S. 2 AO) — the Finanzamt may reassess the whole case, and must warn first, which leaves the window to withdraw.
10. Whether the amount in dispute justifies the effort and the risk.

## Evidence: four proof types, judged separately

The recurring failure is treating one document as proof of everything. For a claimed expense, four independent facts must each be evidenced:

| Proof type | Evidences | Typical document |
|---|---|---|
| Cost | The amount and what it was for | Rechnung, Gebührenbescheid, Vertrag |
| Payment | That the money actually flowed in the year claimed | Kontoauszug, Kartenabrechnung, Quittung |
| Purpose or participation | That the professional occasion was real | Programm, Teilnahmebescheinigung, Ticket, Einladung |
| No reimbursement | That the taxpayer ultimately bore it | Arbeitgeberbestätigung, Eigenerklärung |

An invoice alone proves none of the other three. Where a proof type is missing, either produce a signed `Eigenbeleg` naming the reason, or drop the position — never let the gap travel silently into the letter.

`Zufluss` and `Abfluss` follow `§ 11 EStG`: what counts is the year of payment, not the invoice date. An invoice dated in December and paid in January belongs to the later year, subject to the ten-day rule for regularly recurring payments (`§ 11 Abs. 1 S. 2, Abs. 2 S. 2 EStG`).

Since 2017 receipts are generally kept rather than filed (`Belegvorhaltepflicht`), so the Finanzamt asks for them later — sometimes years later. Keep the evidence with the case, not with the return.

## Reconcile against the transmitted return

Before answering any `Belegaufforderung`, build a control table with one row per contested item and four columns: **transmitted**, **now evidenced**, **difference**, **treatment**. The comparison base is the data set that was actually transmitted — the ELSTER or provider record — never the current working spreadsheet, which drifts as the analysis progresses.

Every non-zero difference gets one of three treatments, stated in the letter itself:

- **Correction downward**: disclose it and say so plainly. It costs a small amount and buys the credibility that carries the contested positions.
- **Correction upward** (a position under-declared or omitted): declare it now, and check whether the same document was already claimed in another year.
- **Maintained despite contrary evidence**: state the taxpayer's position, the governing rule, and the fact that a proof is missing. Never convert a preference into an assertion of proof.

Two findings from real cases that this table catches and nothing else does. A bank credit can be a **net** figure hiding a gross receipt plus a separate disbursement, so a rent line that looks short by a few hundred euro is not evidence of a shortfall until the payer's own statement is read. And a byte-identical invoice can sit in two years' folders, meaning one of the two years overstated the deduction — which is a `§ 153 AO` matter for the other year, not something to leave alone because it is closed.

## Disclosure: § 153 AO

When work on one year reveals that another year's return was wrong, `§ 153 Abs. 1 S. 1 Nr. 1 AO` obliges an immediate notification and correction. Do it in the same submission, name the year, the amount, and the direction. Two reasons beyond the obligation: it removes the `§ 370 AO` exposure that silence creates, and an examiner who sees a self-reported correction against the taxpayer's own interest reads the rest of the package differently.

Distinguish sharply: `§ 153 AO` is a correction of a known error; `§ 371 AO` (Selbstanzeige) is criminal-law territory and needs a `Fachanwalt für Steuerrecht` before a single line is written.

## Deep references

| Topic | Read |
|---|---|
| Deadlines, notification, objection procedure, AdV, estimation, surcharges, interest, limitation | [`references/fristen-und-verfahren.md`](references/fristen-und-verfahren.md) |
| Rental income, AfA rates, § 7b/7h/7i, purchase-price split, anschaffungsnaher Herstellungsaufwand, verbilligte Vermietung | [`references/vermietung-und-afa.md`](references/vermietung-und-afa.md) |
| Werbungskosten, Arbeitszimmer, Homeoffice, travel, training, work equipment, Sonderausgaben, agB, § 35a, Kapitalerträge | [`references/werbungskosten-und-abzuege.md`](references/werbungskosten-und-abzuege.md) |
| Answering a Belegaufforderung end to end, control table, Anlagenverzeichnis, residence and centre-of-life evidence, dispatch | [`references/belegaufforderung-antwort.md`](references/belegaufforderung-antwort.md) |
| Year-keyed amounts: allowances, flat rates, filing deadlines per VZ | [`references/kennzahlen.md`](references/kennzahlen.md) |
| German letter templates: Einspruch, Begründung, AdV, Ruhen, Fristverlängerung, § 153 notification, Eigenbeleg | [`references/vorlagen.md`](references/vorlagen.md) |

Building the `Anlagen` PDF — cover sheet, locator index, page ranges, which sheets may be omitted — is [`evidence-package-assembly`](../evidence-package-assembly/SKILL.md). This Skill decides *what* goes in and *why*; that one builds the file.

## Anti-rationalization

| Rationalization | Reality |
|---|---|
| "The invoice is in the folder, that is the proof." | It proves the cost. It proves neither payment, nor professional purpose, nor that no third party reimbursed it. Four proof types, judged separately. |
| "The Finanzamt accepted this in the prior year." | `Abschnittsbesteuerung`: each year stands alone. Quote the prior notice as an argument, never as a guarantee, and say which it is. |
| "The spreadsheet computes it this way." | The spreadsheet is not the filing. Reconcile against the transmitted data set; where they differ, the workbook is the suspect. |
| "The difference is small, no need to mention it." | An undisclosed deviation found by the examiner discredits the entire package. Disclose it and keep the contested positions credible. |
| "That other year is closed anyway." | `§ 153 Abs. 1 AO` obliges notification regardless, and silence after discovery is what turns an error into an offence. |
| "The area is right, it matches the contract total." | Agreement with a total is arithmetic reconciliation, not measurement. Label it as derived unless an Aufmaß or a dimensioned plan supports it. |
| "The registered address settles where the taxpayer lives." | Registration is one indication among many and can be rebutted — but it is the authority's strongest one, so it must be addressed openly, not omitted. |
| "The deadline is roughly a month after the notice." | Four days deemed notification plus one month, then weekend and holiday shifts. Run the script. |
| "It is late, but the position is basically right — send it." | Near a deadline, do mechanical closure only: signatures, placeholders, file matching, readability. New tax positions wait for a rested review. |

## Red flags

Stop and re-enter the process when any of these is true right now:

- About to state an amount in a letter that no `Anlage` derives.
- About to cite a BFH docket number or a BMF letter that was not read in this session.
- Reconciling against the working spreadsheet instead of the transmitted return.
- Writing "wie im Vorjahr anerkannt" as the sole justification for a position.
- A deviation was found and the draft does not mention it.
- Quoting a notice from an OCR text file without opening the PDF.
- The letter names an `Anlage` that has not been built.
- An internal caveat, status marker, or disclaimer is still in the submission draft.

## Verification

Before reporting a submission ready, produce each of these:

- **Figure trace**: every amount in the letter appears in a control table row with its evidence reference. No orphan figures.
- **Norm check**: every § citation resolved against the current statutory text, with the amendment date noted where the year matters.
- **Deviation sweep**: control table shows no unexplained difference against the transmitted return.
- **Attachment match**: `Anlagenverzeichnis` entries map one-to-one onto files that exist, with page counts.
- **Marker sweep**: full-text search of the draft for `TODO`, `offen`, `intern`, `Prüfvermerk`, `Disclaimer`, `Entwurf` returns only intended prose.
- **Deadline**: `Get-SteuerFrist.ps1` output pasted into the working note, with the dispatch date before it.
- **Dispatch proof**: ELSTER `Transferticket` or equivalent receipt archived with the case.

## Escalation

Flag to the user immediately, and do not proceed alone:

- Any indication of `§ 370 AO` (Hinterziehung) or `§ 378 AO` — `Fachanwalt für Steuerrecht` first, and never draft a `Selbstanzeige` without one.
- `Vertretungszwang` before the BFH (`§ 62 Abs. 4 FGO`). Before the Finanzgericht there is none, and none in the objection procedure.
- `Klagefrist` one month from the `Einspruchsentscheidung` (`§ 47 FGO`) — missing it ends the case.
- `Verböserung` risk that outweighs the objection's upside.
- Business assets, reorganisations, cross-border facts, inheritance or gift tax, VAT audits — outside routine income tax.
- A position that turns on where the taxpayer's centre of life is, because it can move both the deductions and the competent Finanzamt (`§ 19 AO`).

## Anti-patterns

- ❌ Applying the three-day notification fiction — it is four days since 1 January 2025.
- ❌ Asking to extend the `Einspruchsfrist`.
- ❌ Depreciating the full purchase price including the land share.
- ❌ Treating the `§ 7i` or `§ 7h` certificate as optional evidence rather than as a `Grundlagenbescheid` (`§ 175 Abs. 1 S. 1 Nr. 1 AO`).
- ❌ Confusing `anschaffungsnaher Herstellungsaufwand` (`§ 6 Abs. 1 Nr. 1a EStG`, 15 % within three years) with deductible maintenance.
- ❌ Objecting to a `Verspätungszuschlag` inside the income tax objection instead of separately.
- ❌ Naming only one spouse as addressee on a joint assessment.
- ❌ Treating the BMF `Arbeitshilfe zur Kaufpreisaufteilung` as binding (BFH IX R 26/19).
- ❌ Claiming "the estimate is unlawful" without substantiating the actual bases of taxation.
- ❌ Putting an RDG or StBerG disclaimer into a letter addressed to the Finanzamt.

---

*Hinweis für interne Arbeitsunterlagen: Diese Ausarbeitung stellt keine Steuerberatung i. S. v. § 2 StBerG und keine Rechtsberatung i. S. v. § 2 RDG dar. Für verbindliche Auskünfte ist eine Steuerberaterin, ein Steuerberater oder eine Fachanwältin bzw. ein Fachanwalt für Steuerrecht einzuschalten.*
