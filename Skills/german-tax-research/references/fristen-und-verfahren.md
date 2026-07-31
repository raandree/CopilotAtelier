# Fristen und Verfahren (AO)

Procedural law for an income tax case: notification, deadlines, the objection procedure, corrections, estimation, surcharges, interest, and the limitation period. Material law is in [`vermietung-und-afa.md`](vermietung-und-afa.md) and [`werbungskosten-und-abzuege.md`](werbungskosten-und-abzuege.md).

## Contents

- [Bekanntgabe: when a notice takes effect](#bekanntgabe-when-a-notice-takes-effect)
- [Deadline arithmetic](#deadline-arithmetic)
- [Einspruch (§§ 347 ff. AO)](#einspruch--347-ff-ao)
- [Aussetzung der Vollziehung (§ 361 AO)](#aussetzung-der-vollziehung--361-ao)
- [Ruhen und Vorläufigkeit](#ruhen-und-vorläufigkeit)
- [Correction routes after the deadline](#correction-routes-after-the-deadline)
- [Filing deadlines (§ 149 AO)](#filing-deadlines--149-ao)
- [Verspätungszuschlag (§ 152 AO)](#verspätungszuschlag--152-ao)
- [Zinsen (§§ 233a, 237 AO)](#zinsen--233a-237-ao)
- [Schätzung (§ 162 AO)](#schätzung--162-ao)
- [Mitwirkung und Beweislast](#mitwirkung-und-beweislast)
- [Festsetzungsverjährung (§§ 169–171 AO)](#festsetzungsverjährung--169171-ao)
- [Örtliche Zuständigkeit (§§ 19, 26, 127 AO)](#örtliche-zuständigkeit--19-26-127-ao)

## Bekanntgabe: when a notice takes effect

| Transmission | Deemed notified | Norm |
|---|---|---|
| Post, within Germany | 4th day after posting | § 122 Abs. 2 Nr. 1 AO |
| Post, abroad | one month after posting | § 122 Abs. 2 Nr. 2 AO |
| Electronic transmission | 4th day after dispatch | § 122 Abs. 2a AO |
| Provision for retrieval (Mein ELSTER) | 4th day after the notification of provision | § 122a Abs. 4 AO |

The four-day rule replaced the three-day rule for everything dispatched from 1 January 2025 (PostModG, BGBl. 2024 I Nr. 236). For older notices the three-day rule still applies — check the dispatch date, not the date of the analysis.

The fiction fails where the notice arrived later or not at all; then the authority must prove access and its date (`§ 122 Abs. 2 Hs. 2 AO`). A credible submission that the envelope arrived later shifts the burden — keep the envelope.

On joint assessment a single copy to the common address notifies both spouses (`§ 122 Abs. 7 AO`), unless one of them requested separate notification or the authority knows of serious disagreement.

## Deadline arithmetic

`§ 108 Abs. 1 AO` adopts `§§ 187–193 BGB`:

- The day of notification does not count (`§ 187 Abs. 1 BGB`).
- A one-month period ends on the day of the following month that bears the same number as the notification day (`§ 188 Abs. 2 BGB`); where that month is shorter, on its last day (`§ 188 Abs. 3 BGB`).
- A period ending on a Saturday, Sunday, or a public holiday at the place of the authority ends on the next working day (`§ 108 Abs. 3 AO`).
- The deemed notification day itself also shifts when it falls on a weekend or holiday.

Public holidays are state law, so the relevant `Bundesland` is the one where the Finanzamt sits. `scripts/Get-SteuerFrist.ps1` implements all of this, including the movable feasts, and reports each shift it applied.

## Einspruch (§§ 347 ff. AO)

- Period: one month from notification (`§ 355 Abs. 1 AO`), **not extendable**.
- Missing or defective `Rechtsbehelfsbelehrung`: one year (`§ 356 Abs. 2 AO`).
- Form: written, electronic, or recorded at the authority (`§ 357 Abs. 1 AO`). Email suffices; a signature is not required. Naming the objector and the contested notice is.
- Reasons may follow later. File on time first, argue afterwards.
- No `Vertretungszwang`; the taxpayer may act alone.
- Filing does not suspend payment (`§ 361 Abs. 1 AO`) — that needs a separate application.
- `Verböserung` (`§ 367 Abs. 2 S. 2 AO`): the authority reviews the whole case and may raise the tax, but must give notice and the opportunity to withdraw. Weigh this before writing a substantive Begründung.
- Withdrawal is possible until the `Einspruchsentscheidung` (`§ 362 AO`) and ends the procedure; the notice becomes final.
- After an adverse `Einspruchsentscheidung`: `Klage` to the Finanzgericht within one month (`§ 47 FGO`).

## Aussetzung der Vollziehung (§ 361 AO)

Granted on serious doubts as to lawfulness or on unreasonable hardship. Apply to the Finanzamt first; on refusal, to the Finanzgericht (`§ 69 FGO`).

The cost of losing: `Aussetzungszinsen` under `§ 237 AO` at 0.15 % per month (1.8 % p. a.) on the suspended amount. Apply only where the objection has real prospects, and quantify the exposure before recommending it.

## Ruhen und Vorläufigkeit

| Instrument | When | Effect |
|---|---|---|
| `Ruhen kraft Gesetzes`, § 363 Abs. 2 S. 2 AO | A pilot case is pending at BVerfG, BFH, or EuGH on the same question | Procedure rests, deadline preserved |
| `Ruhen aus Zweckmäßigkeit`, § 363 Abs. 2 S. 1 AO | Both sides agree to wait, e.g. for a pending certificate | Procedure rests by consent |
| `Vorläufige Festsetzung`, § 165 Abs. 1 AO | A fact is uncertain, e.g. income-generating intent, or a pending Grundlagenbescheid | Notice issues but stays open in the stated scope |
| `Vorbehalt der Nachprüfung`, § 164 AO | Case not yet examined | Whole notice remains changeable while the reservation stands |

A `Grundlagenbescheid` — a `§ 7i` or `§ 7h` certificate, a separate assessment of income — binds the follow-on notice and forces its amendment when it arrives (`§ 175 Abs. 1 S. 1 Nr. 1 AO`), regardless of finality. Where such a certificate is outstanding, ask for provisionality or for the procedure to rest instead of arguing an unprovable amount.

## Correction routes after the deadline

| Route | Norm | Condition |
|---|---|---|
| Schlichte Änderung | § 172 Abs. 1 S. 1 Nr. 2 a AO | Applied for within the objection period; narrow, only the named point |
| Neue Tatsachen | § 173 Abs. 1 AO | Facts newly known; to the taxpayer's benefit only without gross fault |
| Widerstreitende Steuerfestsetzung | § 174 AO | Same fact taxed twice or not at all |
| Grundlagenbescheid | § 175 Abs. 1 S. 1 Nr. 1 AO | Basic notice issued, amended, or repealed |
| Rückwirkendes Ereignis | § 175 Abs. 1 S. 1 Nr. 2 AO | Event with retroactive tax effect |
| Offenbare Unrichtigkeit | § 129 AO | Clerical or arithmetic slip by the authority |
| Anzeige und Berichtigung | § 153 AO | The taxpayer discovers their own error — an obligation, not an option |

## Filing deadlines (§ 149 AO)

Standard: seven months after the end of the calendar year, so 31 July of the following year for unadvised taxpayers (`§ 149 Abs. 2 S. 1 AO`); the last day of February of the second following year in advised cases (`§ 149 Abs. 3 AO`).

`§ 36 EGAO` extends both for the assessment periods 2020 to 2024. Because those extensions are per-year and not intuitive, they are tabulated per VZ in [`kennzahlen.md`](kennzahlen.md). Read the table rather than reasoning from the standard rule for any year up to 2024.

Extension of a filing deadline: `§ 109 AO`, granted at discretion, with reasons. Advised cases beyond the statutory date require particular justification (`§ 109 Abs. 2 AO`).

## Verspätungszuschlag (§ 152 AO)

Discretionary in principle, but **mandatory** where the return arrives more than 14 months after the end of the assessment period (`§ 152 Abs. 2 AO`), subject to the exceptions in `§ 152 Abs. 3 AO` (assessed tax at zero, refund, extension granted).

Amount: 0.25 % of the assessed tax less prepayments and credits per commenced month, minimum 25 euro per month (`§ 152 Abs. 5 AO`).

It is a **separate administrative act**. Contesting it requires its own objection, even where it is printed on the same sheet as the income tax assessment.

## Zinsen (§§ 233a, 237 AO)

Interest runs from 15 months after the end of the assessment period (`§ 233a Abs. 2 AO`), both ways. The rate is 0.15 % per month, 1.8 % per year, after the BVerfG decision of 8 July 2021 and the second AO amendment act of 12 July 2022, and it is reviewed every three years.

## Schätzung (§ 162 AO)

The authority may estimate where bases cannot be determined (`§ 162 Abs. 1 S. 1 AO`), and must estimate where the taxpayer fails to cooperate (`§ 162 Abs. 2 AO`). Two attack lines, in this order:

1. **Substantive**: `§ 162 Abs. 1 S. 2 AO` obliges the authority to consider all circumstances of significance, including those that reduce tax. An estimate that raises rental income while ignoring depreciation and interest is defective on its face.
2. **Amount**: an estimate must be plausible, economically possible, and reasoned. But arguing only that the number is too high, without submitting the actual bases, rarely succeeds — file the return with the objection.

## Mitwirkung und Beweislast

`§ 90 AO` obliges cooperation in establishing the facts; `§ 88 AO` obliges the authority to investigate, including in the taxpayer's favour, and it may be asked to obtain its own files. The objective burden follows the norm's direction: the authority bears it for tax-increasing facts, the taxpayer for tax-reducing ones. In practice every deduction is the taxpayer's to prove.

`§ 364 AO` gives a right to be told the bases of taxation — useful where a notice states a total without showing how it was derived. It covers the bases of taxation, not internal administrative processes.

## Festsetzungsverjährung (§§ 169–171 AO)

Four years for income tax, five where the tax was recklessly understated, ten in cases of evasion (`§ 169 Abs. 2 AO`).

The start is deferred by `§ 170 Abs. 2 S. 1 Nr. 1 AO` where a return must be filed: the period begins at the end of the year in which the return was filed, at the latest after three years. A 2020 return filed in 2023 therefore runs out at the end of 2027, not 2024. Suspensions under `§ 171 AO` — pending objection, external audit, outstanding basic notice — extend it further.

## Örtliche Zuständigkeit (§§ 19, 26, 127 AO)

Competence follows the residence (`§ 19 Abs. 1 S. 1 AO`); with several residences for a single taxpayer, the predominant one (`§ 19 Abs. 1 S. 2 AO`). A change of residence transfers the file (`§ 26 S. 1 AO`), while the previous office may keep proceedings already begun (`§ 26 S. 2 AO`).

Two practical consequences. First, an argument about the centre of life to secure a deduction can move competence as a side effect — decide deliberately whether that is wanted. Second, `§ 127 AO` bars the annulment of a notice solely because the wrong office issued it, so a competence objection buys nothing and can trigger a file transfer that stalls the case. Where the point is only evidential, say expressly that no competence objection is raised.
