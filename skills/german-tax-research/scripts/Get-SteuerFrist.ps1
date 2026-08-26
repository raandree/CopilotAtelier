#requires -Version 7.0
<#
.SYNOPSIS
    Computes the deemed notification date and the resulting deadline for a German tax notice.

.DESCRIPTION
    Applies the notification fiction of § 122 Abs. 2, Abs. 2a, § 122a Abs. 4 AO to the
    dispatch date of a Steuerbescheid, then the one-month objection period of
    § 355 Abs. 1 AO, computed under § 108 AO with §§ 187 Abs. 1, 188 Abs. 2 und 3 BGB.

    Both the deemed notification day and the end of the period move to the next
    working day when they fall on a Saturday, Sunday, or a public holiday
    (§ 108 Abs. 3 AO). Public holidays are state law, so the state of the competent
    Finanzamt governs.

.PARAMETER BescheidDatum
    Date the notice was posted or dispatched — the date printed on the notice, not the
    date it arrived.

.PARAMETER Bundesland
    Federal state of the competent Finanzamt. 'Bundesweit' counts only the nationwide
    holidays and is the conservative default for a first estimate.

.PARAMETER Uebermittlung
    Transmission channel. 'PostAusland' applies the one-month fiction of
    § 122 Abs. 2 Nr. 2 AO instead of the day-count fiction.

.PARAMETER FristMonate
    Length of the period in months. 1 for the objection period (§ 355 Abs. 1 AO) and the
    action period (§ 47 FGO), 12 where the Rechtsbehelfsbelehrung is missing or defective
    (§ 356 Abs. 2 AO).

.EXAMPLE
    ./Get-SteuerFrist.ps1 -BescheidDatum '2026-02-25' -Bundesland Niedersachsen

    Notice posted 25 February 2026: the fourth day is Sunday 1 March 2026, so notification
    is deemed on Monday 2 March 2026 and the objection deadline is 2 April 2026.

.NOTES
    The three-day fiction applies to anything dispatched before 1 January 2025; the
    four-day fiction applies from that date (PostModG, BGBl. 2024 I Nr. 236). The script
    selects by the dispatch date.

    24 and 31 December are not statutory holidays even though tax offices are usually
    closed, so § 108 Abs. 3 AO does not move a deadline falling on them.

    The file is UTF-8 without a byte order mark, matching the repository convention, and
    therefore requires PowerShell 7 — Windows PowerShell 5.1 would decode the § sign and
    the umlauts with the ANSI code page.
#>
[CmdletBinding()]
[OutputType([PSCustomObject])]
param(
    [Parameter(Mandatory)]
    [datetime]$BescheidDatum,

    [Parameter()]
    [ValidateSet('Bundesweit', 'Baden-Wuerttemberg', 'Bayern', 'Berlin', 'Brandenburg',
        'Bremen', 'Hamburg', 'Hessen', 'Mecklenburg-Vorpommern', 'Niedersachsen',
        'Nordrhein-Westfalen', 'Rheinland-Pfalz', 'Saarland', 'Sachsen',
        'Sachsen-Anhalt', 'Schleswig-Holstein', 'Thueringen')]
    [string]$Bundesland = 'Bundesweit',

    [Parameter()]
    [ValidateSet('Post', 'Elektronisch', 'Datenabruf', 'PostAusland')]
    [string]$Uebermittlung = 'Post',

    [Parameter()]
    [ValidateRange(1, 12)]
    [int]$FristMonate = 1
)

function Get-EasterSunday {
    <#
        .SYNOPSIS
            Returns Easter Sunday of a Gregorian year (anonymous Gregorian algorithm).
    #>
    [CmdletBinding()]
    [OutputType([datetime])]
    param(
        [Parameter(Mandatory)]
        [int]$Year
    )

    # Anonymous Gregorian algorithm. The literals are the algorithm's own constants
    # (Metonic cycle, century correction, weekday offset) and carry no local meaning.
    $a = $Year % 19
    $b = [math]::Floor($Year / 100)
    $c = $Year % 100
    $d = [math]::Floor($b / 4)
    $e = $b % 4
    $f = [math]::Floor(($b + 8) / 25)
    $g = [math]::Floor(($b - $f + 1) / 3)
    $h = (19 * $a + $b - $d - $g + 15) % 30
    $i = [math]::Floor($c / 4)
    $k = $c % 4
    $l = (32 + 2 * $e + 2 * $i - $h - $k) % 7
    $m = [math]::Floor(($a + 11 * $h + 22 * $l) / 451)
    $month = [math]::Floor(($h + $l - 7 * $m + 114) / 31)
    $day = (($h + $l - 7 * $m + 114) % 31) + 1

    return [datetime]::new($Year, $month, $day)
}

function Get-GesetzlicherFeiertag {
    <#
        .SYNOPSIS
            Returns the statutory holidays of one year for one federal state.
    #>
    [CmdletBinding()]
    [OutputType([datetime[]])]
    param(
        [Parameter(Mandatory)]
        [int]$Year,

        [Parameter(Mandatory)]
        [string]$State
    )

    $easter = Get-EasterSunday -Year $Year

    $holidays = [System.Collections.Generic.List[datetime]]::new()
    # Nationwide holidays (§ 2 Abs. 2 EinigVtrG and the state acts, identical in all states).
    $holidays.Add([datetime]::new($Year, 1, 1))    # Neujahr
    $holidays.Add($easter.AddDays(-2))             # Karfreitag
    $holidays.Add($easter.AddDays(1))              # Ostermontag
    $holidays.Add([datetime]::new($Year, 5, 1))    # Tag der Arbeit
    $holidays.Add($easter.AddDays(39))             # Christi Himmelfahrt
    $holidays.Add($easter.AddDays(50))             # Pfingstmontag
    $holidays.Add([datetime]::new($Year, 10, 3))   # Tag der Deutschen Einheit
    $holidays.Add([datetime]::new($Year, 12, 25))  # 1. Weihnachtstag
    $holidays.Add([datetime]::new($Year, 12, 26))  # 2. Weihnachtstag

    $epiphany = @('Baden-Wuerttemberg', 'Bayern', 'Sachsen-Anhalt')
    $womensDay = @('Berlin', 'Mecklenburg-Vorpommern')
    $corpusChristi = @('Baden-Wuerttemberg', 'Bayern', 'Hessen', 'Nordrhein-Westfalen',
        'Rheinland-Pfalz', 'Saarland')
    $reformation = @('Brandenburg', 'Bremen', 'Hamburg', 'Mecklenburg-Vorpommern',
        'Niedersachsen', 'Sachsen', 'Sachsen-Anhalt', 'Schleswig-Holstein', 'Thueringen')
    $allSaints = @('Baden-Wuerttemberg', 'Bayern', 'Nordrhein-Westfalen',
        'Rheinland-Pfalz', 'Saarland')

    if ($State -in $epiphany) { $holidays.Add([datetime]::new($Year, 1, 6)) }
    if ($State -in $womensDay) { $holidays.Add([datetime]::new($Year, 3, 8)) }
    if ($State -in $corpusChristi) { $holidays.Add($easter.AddDays(60)) }
    if ($State -eq 'Saarland') { $holidays.Add([datetime]::new($Year, 8, 15)) }
    if ($State -eq 'Thueringen') { $holidays.Add([datetime]::new($Year, 9, 20)) }
    if ($State -in $reformation) { $holidays.Add([datetime]::new($Year, 10, 31)) }
    if ($State -in $allSaints) { $holidays.Add([datetime]::new($Year, 11, 1)) }

    if ($State -eq 'Sachsen') {
        # Buß- und Bettag: the Wednesday before 23 November.
        $reference = [datetime]::new($Year, 11, 23)
        $offset = (([int]$reference.DayOfWeek - [int][DayOfWeek]::Wednesday) + 7) % 7
        if ($offset -eq 0) { $offset = 7 }
        $holidays.Add($reference.AddDays(-$offset))
    }

    return $holidays.ToArray()
}

function Get-NaechsterWerktag {
    <#
        .SYNOPSIS
            Moves a date forward to the next working day under § 108 Abs. 3 AO.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [datetime]$Date,

        [Parameter(Mandatory)]
        [string]$State
    )

    $current = $Date.Date
    $reasons = [System.Collections.Generic.List[string]]::new()
    $holidays = Get-GesetzlicherFeiertag -Year $current.Year -State $State

    while ($true) {
        if ($current.Year -ne $holidays[0].Year) {
            $holidays = Get-GesetzlicherFeiertag -Year $current.Year -State $State
        }

        if ($current.DayOfWeek -eq [DayOfWeek]::Saturday) {
            $reasons.Add(('{0:dd.MM.yyyy} ist ein Samstag' -f $current))
        }
        elseif ($current.DayOfWeek -eq [DayOfWeek]::Sunday) {
            $reasons.Add(('{0:dd.MM.yyyy} ist ein Sonntag' -f $current))
        }
        elseif ($holidays -contains $current) {
            $reasons.Add(('{0:dd.MM.yyyy} ist ein gesetzlicher Feiertag in {1}' -f $current, $State))
        }
        else {
            break
        }

        $current = $current.AddDays(1)
    }

    return [PSCustomObject]@{
        Datum      = $current
        Verschoben = $reasons.ToArray()
    }
}

$hinweise = [System.Collections.Generic.List[string]]::new()

# § 122 Abs. 2 Nr. 1 und Abs. 2a AO: three days until 31.12.2024, four days from
# 01.01.2025 (PostModG). The dispatch date decides which version applies.
$fiktionsTage = if ($BescheidDatum.Date -ge [datetime]'2025-01-01') { 4 } else { 3 }

if ($Uebermittlung -eq 'PostAusland') {
    $fiktion = $BescheidDatum.Date.AddMonths(1)
    $fiktionsNorm = '§ 122 Abs. 2 Nr. 2 AO (ein Monat bei Übermittlung ins Ausland)'
}
else {
    $fiktion = $BescheidDatum.Date.AddDays($fiktionsTage)
    $fiktionsNorm = switch ($Uebermittlung) {
        'Elektronisch' { "§ 122 Abs. 2a AO ($fiktionsTage Tage nach Absendung)" }
        'Datenabruf' { "§ 122a Abs. 4 AO ($fiktionsTage Tage nach der Benachrichtigung)" }
        default { "§ 122 Abs. 2 Nr. 1 AO ($fiktionsTage Tage nach Aufgabe zur Post)" }
    }
}

$bekanntgabe = Get-NaechsterWerktag -Date $fiktion -State $Bundesland
foreach ($reason in $bekanntgabe.Verschoben) {
    $hinweise.Add("Bekanntgabe verschoben: $reason")
}

# §§ 187 Abs. 1, 188 Abs. 2 BGB: the period ends on the day of the later month bearing the
# same number; AddMonths clamps to the last day of a shorter month, which is § 188 Abs. 3 BGB.
$fristEndeRoh = $bekanntgabe.Datum.AddMonths($FristMonate)
$fristEnde = Get-NaechsterWerktag -Date $fristEndeRoh -State $Bundesland
foreach ($reason in $fristEnde.Verschoben) {
    $hinweise.Add("Fristende verschoben: $reason")
}

[PSCustomObject]@{
    BescheidDatum     = $BescheidDatum.Date
    Uebermittlung     = $Uebermittlung
    Bundesland        = $Bundesland
    Fiktionsnorm      = $fiktionsNorm
    BekanntgabeRoh    = $fiktion
    Bekanntgabe       = $bekanntgabe.Datum
    Fristlaenge       = "$FristMonate Monat(e)"
    FristEndeRoh      = $fristEndeRoh
    FristEnde         = $fristEnde.Datum
    VerbleibendeTage  = [int]($fristEnde.Datum - (Get-Date).Date).TotalDays
    Hinweise          = $hinweise.ToArray()
}
