---
name: elster-form-capture
description: >-
  Drive the Mein ELSTER web form by machine to capture a German tax return —
  Hauptvordruck, Anlage N, V, V-Sonstige, KAP, Vorsorgeaufwand — while the
  taxpayer authenticates and transmits personally. Covers the stable ERiC field
  numbers behind `name="fields[…]"`, sub-page navigation, repeat rows,
  sub-forms, mandatory-field traps, eData gaps, and a machine comparison of
  every target amount against the summary page.
  USE FOR: ELSTER, Mein ELSTER, Steuererklärung erfassen, Formular ausfüllen,
  Anlage V, Anlage N, Anlage Vorsorgeaufwand, Teilseite, Wiederholzeile,
  Kennzahl, ERiC, eruV/eruN field ids, Daten vorhanden, Prüfen und Steuer
  berechnen, Transferticket, eData, Entwurf fortsetzen, automating a German
  tax portal form with Playwright.
  DO NOT USE FOR: deciding what is deductible or drafting an Einspruch (use
  german-tax-research), login and cookies (use authenticated-web-extraction),
  reading receipts (use pdf-to-markdown, xlsx-to-markdown), Anlagen bundles
  (use evidence-package-assembly).
compatibility: >-
  A Mein ELSTER account the user signs into personally, and browser automation
  tools with Playwright access to the shared page. No credentials, cookies, or
  certificates are ever handled by the model.
---

# ELSTER Form Capture (Mein ELSTER)

Type a prepared tax return into the Mein ELSTER web form without typing it. The model fills fields, reads every value back, and proves the result against the portal's own summary page; the taxpayer signs in, reviews, and presses Send.

The value is not the typing. Three full capture runs produced the same finding each time: **the attempt to drive the form mechanically is the fastest audit of the capture guide that feeds it.** Broken line references, a wrong postcode, an amount in a field that only accepts whole euros — all surfaced in seconds, where transcribing by hand would have surfaced them in front of the form, under deadline.

This Skill supplies the mechanics. The tax reasoning belongs to [`german-tax-research`](../german-tax-research/SKILL.md).

## When to Use

- A prepared return must be entered into Mein ELSTER, or an existing draft continued.
- A capture guide lists amounts per `Anlage` and someone has to get them into the form.
- A draft is reported "finished" and the claim needs verifying against the form.
- The final check before transmission must catch positions that were recorded as captured but are absent.

## Outcome

The portal reports **"Es sind keine Fehler vorhanden"**, a provisional tax computation is displayed, every target amount is found by machine in the summary text, and the draft is closed through *Speichern und Verlassen*. Nothing is transmitted.

## Non-negotiables

1. **Never press *Versenden des Formulars*.** Transmission is the taxpayer's declaration of knowledge under `§ 150 Abs. 2 S. 1 AO`. Filling fields is assistance; sending is not delegable.
2. **Never handle credentials.** The user signs in and shares the page. No password, no certificate file, no PIN, no cookie jar reaches the model.
3. **Read every written value back** from the DOM after the server has acknowledged it. A `fill()` that was not committed looks identical to one that was.
4. **The final check is a machine comparison, not reading.** Values produced by someone else are demonstrably reviewed less carefully than values one typed. This is the rule that found 1,330 € of missing deductions in a return whose status table said "finished".
5. **Never create a second draft.** Continue the existing one. Two drafts for the same year is a filing accident waiting to happen.

## The one fact that decides everything

**The official field numbers are stable across assessment years. The sub-page and line numbers are not.**

The `Anlage V` was renumbered for 2023 and *again* for 2024. Apportioned costs moved from sub-page 12 to 13 to sub-page 13 line 73; the result and allocation from 17 to 18; sub-letting moved out of `Anlage V` into a new `Anlage V-Sonstige`, then within it from sub-page 2 line 22 to sub-page 3 line 31. Across all of it, not one `data-eru-name` changed.

Therefore: **address fields by Kennzahl, verify by sub-page heading, and never trust a line number from a guide written for another year.** When the guide disagrees with the form, the guide is wrong — correct the guide, not your memory.

## Workflow

### 1 — Harvest the field map before typing anything

For each `Anlage`, open its sub-pages and dump the field inventory. Do not guess a Kennzahl from a previous year without confirming it exists on this year's page.

```javascript
return await page.evaluate(() => JSON.stringify({
  url: location.pathname,
  h1: document.querySelector('h1').innerText.replace(/\s+/g, ' ').trim(),
  fields: Array.from(document.querySelectorAll('main input[name],main select[name],main textarea[name]'))
    .filter(e => e.name.includes('fields['))
    .map(e => {
      let row = e.closest('div');
      for (let i = 0; i < 7 && row; i++) { if (/Zeile\s*\d+/.test(row.innerText)) break; row = row.parentElement; }
      const m = row ? row.innerText.replace(/\s+/g, ' ').match(/Zeile (\d+\w?)/) : null;
      return (m ? m[1] : '?') + ' | ' + e.name + ' | ' + e.tagName + (e.disabled ? ' DISABLED' : '');
    })
}));
```

The `Zeile` climb matters: the line number is not on the input, it is on an ancestor. Seven levels covers every layout seen so far.

Common Kennzahlen are collected in [`references/feldkarte-est.md`](references/feldkarte-est.md) — load it when you start an `Anlage V`, `V-Sonstige`, `N`, or `Vorsorgeaufwand`, and treat it as a head start, not as truth.

### 2 — Check the guide against the map

Every divergence is a finding. Correct the guide in the repository as you go; a guide that silently disagrees with the form will mislead the next year too.

### 3 — Capture one Anlage at a time, reading back each value

```javascript
async function setField(kz, val) {
  const el = page.locator(`[name="fields[${kz}]"]`);
  const tag = await el.evaluate(e => e.tagName);
  if (tag === 'SELECT') { await el.selectOption({ label: val }); }
  else { await el.fill(val); await el.blur(); }
  await page.waitForTimeout(600);
}
```

### 4 — Prove the control sum per Anlage

ELSTER computes the locked sum fields itself. Read the sum, compare it to the guide, and accept only rounding differences you can explain.

### 5 — Run the completeness test

An `Anlage` is finished only when **every sub-page that should carry something shows "Daten vorhanden"** in the navigation tree. This is the cheapest completeness check the form offers and the one that catches "recorded as done, absent from the form".

```javascript
return await page.evaluate(() => JSON.stringify(
  Array.from(document.querySelectorAll('main li button'))
    .map(b => (b.getAttribute('aria-label') || b.innerText).replace(/\s+/g, ' ').trim())
    .filter(s => /^\s*(Daten vorhanden|\d+ -)/.test(s))));
```

### 6 — Close through the application, never the address bar

*Speichern und Formular verlassen*, then `#saveAufgabe` in the confirmation dialog.

## Anchors that hold

| Target | Anchor | Example |
|---|---|---|
| Field, across form instances | `name` attribute | `[name="fields[eruVEinnUmlE0700501]"]` |
| Field, official ERiC number | `data-eru-name` | `/N/Wk/Arbeitsmittel/Einz/E0204402` |
| New repeat-row field | `mzbs[<group>].newItem.fields[<kz>]` | group is a name or a GUID |
| Existing repeat-row field | `mzbs[<group>].items[<n>].fields[<kz>]` | |
| Create a repeat row | `button[id^="CreateMzbItem/"]` | add `[id*="<group>"]` when the page has several |
| Add another repeat row | `button[id^="AddMzbItem/"]` | |
| Open a sub-form | `button[id^="JumpToPage/"]` | ⚠️ see gotcha 29 |
| Sub-page navigation | `button#NextPage`, `button#PreviousPage` | |
| Breadcrumb to an Anlage | `button[id="fbc_FormData://est-<year>-v1/Startseite[0]/<Anlage>[0]"]` | survives sub-page changes |
| Person within an Anlage | index in the path: `VAnlageN[0]` / `VAnlageN[1]` | |
| Attachment selection | `#anlagenAuswahl`, checkboxes with `VAnlage…`, then `button#Continue` | |
| Completeness | the words "Daten vorhanden" in the accessible name | |
| Value came from eData | the words "Übernommen aus Bescheinigungen" at the field | |

## Gotchas

These are corrections, not advice. Every one cost a failed attempt.

### Navigation and modals

1. The year option value is `2024-v1`, not `2024`. Select by visible label.
2. After the data transfer a modal blocks everything: `closeButton_datenuebernahmeModal`.
3. Resuming a draft raises `modal.formularSpeicherposition` ("continue where you left off?"). Switching from check mode to entry mode raises `modal.form.standard.wechsel`.
4. Incomplete entries raise `modal.form.standard.fehler` on page turn. Proceed with `button#correctlater`.
5. The navigation tree lives in a collapsed sidebar; its buttons are invisible and unclickable until `#lug` is pressed — and it collapses again after every submit. Navigating through the sub-page list in the content area is more reliable.
6. Direct navigation via the address bar raises a `beforeunload` dialog. The call returns late; resume it through the deferred-result id until it yields.

### Fields and values

7. Whole euros or cents is decided by the label, not by the field type: `(Euro)` rejects cents, `(Euro, Cent)` accepts them. Wage-tax certificate lines and creditable foreign taxes take cents.
8. Sum fields are locked (`disabled`, `data-keep-disabled="true"`) and maintained by ELSTER. So are some fields that look like inputs — the total of foreign subsistence allowances, for instance.
9. **ELSTER does not round commercially. It rounds in the taxpayer's favour**: deductible amounts up, deduction-reducing amounts down. Proof in one pair: employee and employer pension contributions are both 8,146.80 €, and the form shows 8,147 € and 8,146 €. A checking script must allow both directions and know the direction of effect.
10. Select lists are addressed by label, not by value.
11. An `id` may not begin with a digit, and sub-page GUIDs often do. Use `button[id="…"]`, never `button#40c9beaa…`.
12. **A locked sum does not carry its free companion field forward.** In `Anlage V` the result line is locked and recomputed instantly after a change; the allocation line beneath it is free and keeps the stale value. Checking only the locked sum hides the difference. Reopen the allocation page after every amount change.
13. Text areas for explanations cap at 999 characters.

### Repeat rows and sub-forms

14. `fill()` alone does not make a repeat row committable. The button stays disabled until the server acknowledges the value — visible in `data-old-value`. Blur, then wait.
15. **The target index of a repeat row moves.** After the first *Eintrag übernehmen*, the button you remembered points at the *same* entry and overwrites it. Re-acquire `AddMzbItem` before every further entry.
16. Sub-forms have their own commit button with its own name, for example *Auswärtstätigkeit im Ausland übernehmen*.
17. Some sub-pages carry several repeat groups. `button[id^="CreateMzbItem/"]` alone hits the first one; add `[id*="<group>"]`.
18. Repeat-group names are sometimes speaking (`AufwendungenArbeitsmittel`, `Fortbildungskosten`) and sometimes GUIDs. Target `[name$=".newItem.fields[<kz>]"]` when the group name is unstable.
19. **The *add* button of a sub-form shares its id prefix with the *edit* button.** After the first entry, `[id^="JumpToPage/"][id*="<group>"]` with `.first()` selects *edit entry 0* and the second entry overwrites the first. The difference is only the trailing index. Match on the full button text instead.

### Mandatory fields and plausibility

20. Mandatory fields can lock page turns. `Anlage V` sub-page 1 demands the acquisition or completion date plus three yes/no usage answers before it lets you leave.
21. **A mandatory field can sit outside every sub-page.** The running number of an `Anlage V` lives on the object's entry page and only surfaces in the final validation.
22. Plausibility rules force statements the facts do not supply. Declared rent obliges either an apportioned-service-charge figure or the "not separately agreed" checkbox — a decision the form forces, not the case.
23. **The previously transmitted return is the best source for mandatory fields.** Acquisition dates, `Einheitswert` file numbers, and postcodes are all in last year's ERiC printout when they are nowhere in the case file. Looking there also caught a wrong postcode in the capture guide.

### eData

24. **A transferred zero can itself be the error.** An employer reported 0.00 € for statutory health insurance; ELSTER then complained about missing basic contributions. The field must be **emptied**, not left at zero.
25. The data transfer is incomplete by design. Supplementary health benefits and occupational disability premiums never arrive as eData and must be typed — even though the `Anlage` reports "Daten vorhanden".
26. eData fields are checked against the paper certificate, not retyped.

### Tooling

27. `page.pdf()` is unavailable in the embedded browser (`Page.printToPDF wasn't found`), and the Playwright sandbox has no `require`. Compare against the *text* of the summary page, not against a PDF.
28. Name filters collide on prefixes. `^Weiter` matches *Weitere Optionen* and opens the account menu; `übernehmen` matches the progress bar. Use the full name or `exact`.
29. **`page.goto()` discards a select box the server has not yet acknowledged** — the `beforeunload` dialog takes the change with it. Three running numbers were set in a loop; only the last survived. Treat select lists like inputs: set, wait, navigate *inside the application*, read back.

## The final check: never by reading

Collect every target amount from the capture guide, open the summary page in check mode, and search its text.

```javascript
const txt = await page.evaluate(() => document.querySelector('main').innerText.replace(/[ \t]+/g, ' '));
const soll = [['Anlage N Arbeitsmittel', '715'], ['Anlage V 1 Überschuss', '-13.621']];
return JSON.stringify(soll.map(([n, v]) => (txt.includes(v) ? 'OK   ' : 'FEHLT') + ' | ' + n + ' = ' + v));
```

A bare `includes` is a presence test, not a mapping test — it proves the amount exists somewhere, not that it sits in the right line. Pair it with the per-`Anlage` control sums from step 4, which do prove placement.

Also confirm what is *absent*: the "Belege werden nachgereicht" checkbox, an address silently carried in from a certificate, and any question the validation does not force but a reviewer will ask about.

⚠️ **The summary page is reached through *Weiter* on the check screen, which lands on the send page.** Do not press *Absenden*. Leave through *Speichern und Formular verlassen*.

## When numbers change after the letter is signed

A late correction invalidates any signed PDF that quotes the figures. After changing an amount in the form, re-check every downstream artifact — the calculation workbook, its checking script, the statement of grounds, and any scanned signature copy. Mark a superseded signed file rather than deleting it.

## References

- [`references/feldkarte-est.md`](references/feldkarte-est.md) — official field numbers for `Anlage V`, `V-Sonstige`, `N`, and `Vorsorgeaufwand`, harvested at the form. Load it when starting one of those attachments.
