# Antwort auf eine Belegaufforderung

End-to-end recipe for answering a Finanzamt request for documents, from the first read to the archived dispatch proof. Derived from a multi-year objection case with an eleven-point request and a final deadline.

## Contents

- [Phase 0 — Read the request literally](#phase-0--read-the-request-literally)
- [Phase 1 — Inventory per point](#phase-1--inventory-per-point)
- [Phase 2 — Control table against the transmitted return](#phase-2--control-table-against-the-transmitted-return)
- [Phase 3 — Decide each point](#phase-3--decide-each-point)
- [Phase 4 — Write the letter](#phase-4--write-the-letter)
- [Phase 5 — Build the attachments](#phase-5--build-the-attachments)
- [Phase 6 — Dispatch and proof](#phase-6--dispatch-and-proof)
- [Wohnsitz und Lebensmittelpunkt](#wohnsitz-und-lebensmittelpunkt)
- [Letzte Frist](#letzte-frist)
- [Pre-dispatch checklist](#pre-dispatch-checklist)

## Phase 0 — Read the request literally

Transcribe the request into a working file with the authority's own numbering and wording. Answer point 7 under the heading "7", with the authority's phrasing quoted, so the examiner can match answer to question without searching. Where a point contains several demands — computation *and* evidence *and* a description of use — split it into sub-points and answer each; a point counts as closed only when every demand in it is met.

Note per point what is demanded: a computation, a document, an explanation, or a confirmation from a third party. The last of these has the longest lead time and must be requested on day one.

## Phase 1 — Inventory per point

For each point, list what exists in the case, where it is, and what is missing. Classify each missing item as:

- **Obtainable in-house** — in an archive, a mailbox, a cloud folder not yet searched.
- **Obtainable from a third party** — employer, manager, bank, organiser. Request immediately and record the ticket or request date; a pending request that is disclosed is far better than a silent gap.
- **Not obtainable** — then decide between an `Eigenbeleg` with a stated reason and dropping the position.

Search the mail archive and the cloud storage before declaring a gap. In the reference case a first pass called four positions unprovable that a second pass found in full.

Verify what a found document actually says before promising it in a letter. Extract the text and grep it for the exact strings the working note claims — payee, purpose, place, date. A cover sheet that promises a booking the file does not contain is worse than no cover sheet.

## Phase 2 — Control table against the transmitted return

One row per contested position:

| Point | Position | Transmitted | Now evidenced | Difference | Treatment |
|---|---|---:|---:|---:|---|
| 6 | Arbeitsmittel | 2,787.00 | 2,863.00 | +76.00 | Nacherklärt, § 153 AO for the prior year |
| 9 | Fortbildung Ehefrau | 4,244.00 | 4,211.00 | −33.00 | Corrected downward, disclosed |
| 11 | Untervermietung | 2,041.00 | 2,015.00 | −26.00 | Corrected downward, disclosed |

The comparison base is the **transmitted data set** — the ELSTER or provider record of what was actually filed — not the current spreadsheet. Workbooks drift: a formula range picks up a row that was later excluded, an allocation key is "improved" to a self-computed value that departs from the one the tax office applied in the prior year. Both happened in the reference case and both would have contradicted the objection already on file.

Where the workbook and the filing disagree, the filing wins for the answer, and the workbook is corrected afterwards with a note of what changed and why.

## Phase 3 — Decide each point

Per point, one of four outcomes, and the letter must say which:

1. **Evidenced as declared** — attach the evidence, restate the amount, and derive it in the text.
2. **Corrected downward** — state the new amount, the reason, and the difference. Do not bury it.
3. **Corrected upward or newly declared** — state it, and check every other year for the same document before claiming it.
4. **Maintained without full proof** — state the taxpayer's position, the governing rule, and expressly that a specific proof is missing. Never let a preference read as a proof.

Where a point was already answered in an earlier assessment, refer to it precisely — date, tax number, what was submitted — and offer to resubmit on request rather than resending hundreds of pages. That keeps the package small and is normally accepted.

## Phase 4 — Write the letter

Structure, in this order:

1. Header block: sender, Finanzamt, place and date, `Steuernummer`, `IdNr.` of both spouses, `Veranlagungszeitraum`, the notice date, and the reference of the request being answered.
2. One paragraph naming what the letter answers and the deadline it meets.
3. The numbered points, each with: what was asked, what is submitted, the derivation of every figure as a small table, and the attachment number.
4. Corrections and disclosures, gathered where they arise but also visible in the point they belong to.
5. Applications, if any — provisional assessment, procedure to rest, suspension of enforcement.
6. `Anlagenverzeichnis`: number, title, page count, and the file name as sent.
7. Signature block for every taxpayer who must sign.

Rules for the body. Every amount that appears in a heading appears again in a derivation, so the examiner never has to reconstruct arithmetic. Quote the tax office's own earlier wording where a method was set by it — "Der Bescheid für 2021 legt einen Anteil von 25,64 % zugrunde" — because a method the authority chose is not one it easily rejects. And use German number format throughout: `1.234,56 €`, `25,64 %`, `31. Juli 2026`.

Before the letter is called final, strip every internal artefact: draft header, review-note references, status markers, "intern offen" lines, internal checklists, and any RDG or StBerG disclaimer. Run a full-text search for them; in the reference case this sweep was believed done a day before it actually was.

## Phase 5 — Build the attachments

Numbering, cover sheets, locator indexes, page ranges, and which sheets may be omitted are the subject of [`evidence-package-assembly`](../../evidence-package-assembly/SKILL.md). Three interfaces matter here:

- The `Anlagenverzeichnis` in the letter and the built files must agree on number, title, page count, and file name.
- Every page range quoted in the letter is filled from the build output, never typed by hand.
- Findings discovered while building — a statement that turns out to contain no relevant booking, a name misspelled by the manager, a position evidenced only by a card receipt rather than an invoice — belong on the cover sheet of the attachment **and** in the corresponding point of the letter.

## Phase 6 — Dispatch and proof

Choose the channel by what proves receipt:

| Channel | Proof | Use |
|---|---|---|
| Mein ELSTER, `Sonstige Nachricht` | `Transferticket` | Always, when a deadline is final |
| Email to the `Poststelle` | Sent-items copy only | As a second channel, or for bulky packages |
| Post, `Einschreiben mit Rückschein` | Postal receipt | Where originals must travel |

Check the authority mailbox size limit before sending. Where the package exceeds it, split into numbered messages — `Mail 1 von 5` in every subject line — keep the `Anlage` numbering continuous across them, and repeat the tax number and assessment period in each message so a separated part is still identifiable.

Archive the dispatch proof with the case immediately: the `Transferticket`, the sent messages, and the exact files sent. A submission that cannot be proven was not made.

## Wohnsitz und Lebensmittelpunkt

Requests increasingly ask where the taxpayer predominantly lived, because it drives home-office deductions, double housekeeping, and competence under `§ 19 AO`. Registration data is the authority's strongest single indication and, where it points the other way, must be addressed openly rather than omitted.

Evidence that works, in descending order of weight:

1. **Consumption and supply contracts** at the claimed address: electricity, gas, telecommunications, broadcasting fee — with payments visible on the account.
2. **Rent and ancillary payments** for the claimed dwelling, monthly and continuous.
3. **Everyday card transactions** in the surrounding area, spread across the whole year — a supermarket, a pharmacy, a filling station, cash withdrawals from local branches. Spread matters more than volume.
4. **Correspondence addressed to the dwelling** by third parties who chose the address themselves: banks, brokers, insurers.
5. **Place of work and its distance** from each dwelling, with the employment contract.
6. Household members' circumstances — employment and its location — where they support daily presence.

Handling rules. Include at least one item that cuts against the claimed result when the record contains one, and name it on the cover sheet; a visibly unfiltered selection is worth more than a clean one. Address the registration point head-on: state that it is undisputed and explain why the objective evidence outweighs it. And where a competence question could arise, say expressly that no competence objection is raised (`§ 127 AO`) — otherwise the argument may trigger a transfer of the file under `§ 26 AO` and stall the case.

## Letzte Frist

When the letter announces a **final** deadline and a decision on the file without further reminder:

- Treat the deadline as the dispatch date, not the completion date. Set an internal target two days earlier for the build and one day earlier for signatures.
- On the final day, do mechanical closure only: signatures, placeholder sweep, file-name matching, page counts, readability. New tax positions and material recomputation belong to a rested review, because a fatigued change to a figure enters the record permanently.
- Send even if one attachment is thinner than hoped, and say what is still outstanding and when it will follow. A package delivered on time with a named gap beats a perfect package that missed the date.

## Pre-dispatch checklist

- [ ] Every point of the request has a heading and an answer.
- [ ] Every figure in the letter is derived in the letter and evidenced by a named attachment.
- [ ] Control table shows no unexplained difference against the transmitted return.
- [ ] Every correction and every gap is disclosed in the point it belongs to.
- [ ] Requests to third parties are named with their date and status.
- [ ] `Anlagenverzeichnis` matches the built files: number, title, pages, file name.
- [ ] All internal markers, review references, and disclaimers removed.
- [ ] Every required signature present and legible in the signed PDFs.
- [ ] Attachment size checked against the mailbox limit; split plan prepared.
- [ ] Deadline computed with the script and stated in the working note.
- [ ] Dispatch proof archived after sending.
