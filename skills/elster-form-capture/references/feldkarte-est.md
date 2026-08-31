# Feldkarte — official ERiC field numbers (Einkommensteuer)

Harvested at the live Mein ELSTER form for assessment years 2023 and 2024 and confirmed unchanged across both. Address every field through the `name` attribute — `[name="fields[<Kennzahl>]"]` — never through the `id`.

**Read the warning in [Sub-page and line numbers move](#sub-page-and-line-numbers-move) before you trust any number in the left two columns.**

## Contents

- [Sub-page and line numbers move](#sub-page-and-line-numbers-move)
- [Anlage V](#anlage-v)
- [Anlage V-Sonstige](#anlage-v-sonstige)
- [Anlage N](#anlage-n)
- [Anlage Vorsorgeaufwand](#anlage-vorsorgeaufwand)

## Sub-page and line numbers move

The `Anlage V` was reorganised for 2023 and renumbered *again* for 2024. Every Kennzahl survived both; no `Teilseite`/`Zeile` pair did.

| Item | 2023 | 2024 |
| --- | ---: | ---: |
| Mieteinnahmen Wohnungen | sub-page 2, line 12 | sub-page 2, line **13** |
| Schuldzinsen | sub-page 7, line 45 | sub-page 7, line **46** |
| Erhaltungsaufwendungen | sub-page 10, line 54 | sub-page 10, line **55** |
| umgelegte Kosten | sub-page 12, line 72 | sub-page **13**, line **73** |
| nicht umgelegte Kosten | sub-page 13, line 75 | sub-page **14**, line **76** |
| sonstige Kosten | sub-page 15, line 79 | sub-page **16**, line **80** |
| Überschuss / Zuordnung | sub-page 17, lines 84 / 85 | sub-page **18**, lines **85** / **86** |
| Untervermietung (`V-Sonstige`) | sub-page 2, line 22 | sub-page **3**, line **31** |
| Berufsunfähigkeit (`Vorsorgeaufwand`) | line 47 | line **45** |
| Unfall- und Haftpflicht | line 48 | line **46** |

The tables below carry the **2023** numbering. Use them to find the Kennzahl; confirm the location by the sub-page heading in the form.

## Anlage V

| Sub-page | Line | Item | Kennzahl |
| ---: | ---: | --- | --- |
| — | — | laufende Nummer der Anlage V ⚠️ sits on the property entry page, outside every sub-page | `eruVLaufende_Nummer_V` |
| 1 | 4 | Straße, Hausnummer | `eruVAllgLageE0700407` |
| 1 | 5 | Postleitzahl / Ort | `eruVAllgLageE0700503` / `…E0700504` |
| 1 | 6 | Einheitswert-Aktenzeichen | `eruVAllgLageE0700605` |
| 1 | 4/5 | angeschafft am / fertig gestellt am 🔒 mandatory | `eruVAllgLageE0700102` / `…E0700103` |
| 1 | 7 | Ferienwohnung / kurzfristig / Angehörige 🔒 mandatory | `eruVAllgNutzungE0700703` / `…E0700705` / `…E0700704` |
| 1 | 8 | Gesamtwohnfläche | `eruVAllgFlaechenE0700702` |
| 2 | 12 | Wohneinheit: Bezeichnung / Fläche / Miete | `eruVEinnMieteinnWhgEinzE0701202` / `…E0700302` / `…E0700201` |
| 2 | 15 | Summe Mieteinnahmen Wohnungen 🔒 locked | `eruVEinnMieteinnWhgSumE0700206` |
| 2 | 19 | an Angehörige vermietet ⚠️ easily confused with line 12 | `eruVEinnMieteinnWhg_AngehoeE0701903` / `…E0700603` / `…E0700604` |
| 2 | 20 / 21 | umgelegte Betriebskosten laufend / Nachzahlung | `eruVEinnUmlE0700501` / `…E0702106` |
| 2 | 24 | „nicht gesondert vereinbart" (checkbox) | `eruVEinnUmlE0702404` |
| 2 | 25 | vereinnahmte Mieten früherer Jahre, Kautionen | `eruVEinnUml_sonstE0700601` |
| 2 | 32 | **Summe der Einnahmen** 🔒 locked | `eruVEinnSumE0701401` |
| 3 | 33 | AfA: Art / Prozent / wie Vorjahr / Erläuterung / Betrag | `eruVWkAfA_GebDirektE0703302` / `…E0703303` / `…E0703304` / `…E0703305` / `…E0703306` |
| 3 | 35 | Summe AfA 🔒 locked | `eruVWkAfA_GebSumE0703511` |
| 5 | 39 | `§§ 7h, 7i`: wie Vorjahr / Erläuterung / Betrag | `eruVWkErhoe_AbsetzDirektE0703912` / `…E0703913` / `…E0703914` |
| 7 | 45 | Schuldzinsen: Einzelangabe / Betrag | `eruVWkSchuldzinsDirektE0704507` / `…E0704508` |
| 7 | 47 | Summe Schuldzinsen 🔒 locked | `eruVWkSchuldzinsSumE0703406` |
| 10 | 54 | Erhaltungsaufwand: Bezeichnung / Aussteller / Datum / Gesamt / abziehbar | `eruVWkErhalt_AW_dirEinzE0703707` / `…E0703708` / `…E0703709` / `…E0704410` / `…E0703911` |
| 10 | 54 | Summe Erhaltungsaufwand 🔒 locked | `eruVWkErhalt_AW_dirSumE0704412` |
| 12 | 72 | umgelegte Kosten: Einzelangabe / Betrag | `eruVWkWeitDirektE0707201` / `…E0707202` |
| 12 | 74 | Summe 🔒 locked | `eruVWkWeitSumE0704418` |
| 13 | 75 | nicht umgelegte Kosten: Einzelangabe / Betrag | `eruVWkVerw_KoDirektE0707501` / `…E0707502` |
| 13 | 77 | Summe 🔒 locked | `eruVWkVerw_KoSumE0705515` |
| 15 | 79 | sonstige Kosten: Einzelangabe / Betrag | `eruVWkSonstDirektE0707901` / `…E0707902` |
| 15 | 81 | Summe 🔒 locked | `eruVWkSonstSumE0705607` |
| 17 | 84 | **Überschuss** 🔒 locked, recomputed instantly | `eruVErm_Zuord_EkE0701601` |
| 17 | 85 | Zuordnung Ehemann / Ehefrau ⚠️ free field, keeps the stale value | `eruVErm_Zuord_EkE0701801` / `…E0701802` |

Entry mechanics differ per sub-page. Sub-pages **3, 5 and 10** open a **sub-form** (`button[id^="JumpToPage/"]` ending in `MZB…`), committed with `NextPage` under the label *Eintrag übernehmen*. Sub-pages **2, 7, 12, 13 and 15** add the row **inline** with `CreateMzbItem`.

The pair on the result sub-page is the trap worth repeating: the `Überschuss` is locked and recalculates the moment an amount changes anywhere in the `Anlage`, while the `Zuordnung` beneath it is free and does not follow. Reopen it after every amount change.

## Anlage V-Sonstige

| Sub-page | Line | Item | Kennzahl |
| ---: | ---: | --- | --- |
| 2 | 22 | Untervermietung: Bezeichnung / Ehemann / Ehefrau | `eruV_SonstigeUntervermEinzE0702603` / `…E0702604` / `…E0702605` |
| 2 | 22 | Summen 🔒 locked | `eruV_SonstigeUntervermSumE0702601` / `…E0702602` |

Sub-letting left the `Anlage V` for this separate attachment; a guide that still looks for it in `Anlage V` will report it missing.

## Anlage N

Only the sub-pages that a 2023 capture guide had omitted — the wage-tax certificate fields arrive as eData and are checked against the paper certificate rather than typed.

| Sub-page | Line | Item | Kennzahl |
| ---: | ---: | --- | --- |
| 12 | 61 / 62 | Tagespauschale: anderer Arbeitsplatz vorhanden / dauerhaft keiner | `eruNWkHomeofficeE0204507` / `eruNWkHomeofficeE0206206` |
| 13 | 63 | Fortbildung: Bezeichnung / Betrag, Summe | `eruNWkFortbEinzE0204804` / `…E0204808`, `eruNWkFortbSumE0204812` |
| 16 | 75 / 76 / 77 | Verpflegung Inland: über 8 Std. / An- und Abreise / 24 Std. | `eruNWkVMAInlE0205201` / `…E0205302` / `…E0205409` |
| 16 | 79 | Summe Auslandsverpflegung 🔒 locked, ELSTER computes it | `eruNWkVMAAuslSumE0205630` |

Foreign subsistence is entered per country in a sub-form whose *add* and *edit* buttons share an id prefix. Select on the full button text, or the second country overwrites the first.

`Arbeitsmittel` carry the ERiC number `/N/Wk/Arbeitsmittel/Einz/E0204402` in `data-eru-name`, in the repeat group `AufwendungenArbeitsmittel`.

## Anlage Vorsorgeaufwand

| Sub-page | Item | Kennzahl |
| ---: | --- | --- |
| 3 | private Basis-Krankenversicherung | `eruVORBeitr_p_KV_PV_InlE2003104` |
| 3 | Pflege-Pflichtversicherung | `eruVORBeitr_p_KV_PV_InlE2003202` |
| 3 | erstattete Beiträge | `eruVORBeitr_p_KV_PV_InlE2003302` |
| 3 | **Wahlleistungen** — never arrives as eData | `eruVORBeitr_p_KV_PV_InlWL_ZversE2003502` |
| 5 | steuerfreie AG-Zuschüsse ges. KV / priv. KV / ges. PV | `eruVORStfr_AG_ZuschE2003705` / `…E2003807` / `…E2003907` |
| 7 | **Berufsunfähigkeit** — never arrives as eData; group `FreiwBerufsunfaehigkeitsVersicherung` | `eruVORWeit_Sons_VorAWA_B_LPErwU_BU_VersEinzE2001501` / `…E2001502` |

Sub-pages **2, 3 and 5 are per person**: each spouse has their own entry, opened through *Angaben zu … bearbeiten* or *… hinzufügen*. Sub-page 7 covers both jointly.

The two rows marked "never arrives as eData" are the reason a `Vorsorgeaufwand` reporting *Daten vorhanden* can still be incomplete.
