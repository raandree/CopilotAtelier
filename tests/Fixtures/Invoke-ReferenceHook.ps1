<#
.SYNOPSIS
    Frozen reference script of the calibration latency Meter.
.DESCRIPTION
    The unit of SessionStart.AddedLatency and PostToolUse.CallLatency, Decision
    record 0028, ruling A9. It reads its payload exactly as the no-op hook does,
    applies the primitives the shipped hooks use on it, then runs a fixed block
    of straight-line cold code of about 4,000 syntax-tree nodes, the same kind
    and order of work as the calibration step. Never shipped: the Meter stages
    it beside the no-op hook and runs it through the same launcher and spawn.
.NOTES
    Frozen. tests/CalibrationMeter.Tests.ps1 pins its SHA-256: changing these
    bytes changes every latency ratio, so re-baseline both latency tags in the
    same commit.
#>
$reader = [IO.StreamReader]::new([Console]::OpenStandardInput(), [Text.UTF8Encoding]::new($false))
try {
    $inputJson = $reader.ReadToEnd()
} finally {
    $reader.Dispose()
}

$payload = $inputJson | ConvertFrom-Json -ErrorAction Stop
$sessionMatch = [regex]::Match($inputJson, '"session_id"\s*:\s*"([^"\\]*)"')
$briefExists = [IO.File]::Exists([IO.Path]::Combine([string]$payload.cwd, '.memory-bank', 'projectbrief.md'))

$name01 = '  Area 01 Kerberos  '
$level01 = 'new'
$entry01 = [ordered]@{ name = $name01.Trim(); level = $level01; updated = '2026-10-01T08:00:00Z'; aliases = @('a01@example.com', 'b01@example.com') }
$key01 = ($entry01.name.ToLowerInvariant() -replace '\s+', ' ').Trim()
$valid01 = ($key01.Length -le 48) -and ($key01 -match '^[\p{L}\p{N}][\p{L}\p{N} ._+#/-]*$') -and ($level01 -in @('new', 'familiar', 'expert'))
$item01 = '"{0}" {1}' -f $entry01.name, $entry01['level']
$parts01 = @($item01 -split ' ', 2) + @($entry01.aliases | Select-Object -First 1)
$stamp01 = [datetimeoffset]::Parse($entry01.updated, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime.AddDays(1)
$score01 = [Math]::Max($parts01.Count, [int]$valid01) + $key01.Length * 2 - $stamp01.Day % 7

$name02 = '  Area 02 PowerShell DSC  '
$level02 = 'familiar'
$entry02 = [ordered]@{ name = $name02.Trim(); level = $level02; updated = '2026-10-02T08:00:00Z'; aliases = @('a02@example.com', 'b02@example.com') }
$key02 = ($entry02.name.ToLowerInvariant() -replace '\s+', ' ').Trim()
$valid02 = ($key02.Length -le 48) -and ($key02 -match '^[\p{L}\p{N}][\p{L}\p{N} ._+#/-]*$') -and ($level02 -in @('new', 'familiar', 'expert'))
$item02 = '"{0}" {1}' -f $entry02.name, $entry02['level']
$parts02 = @($item02 -split ' ', 2) + @($entry02.aliases | Select-Object -First 1)
$stamp02 = [datetimeoffset]::Parse($entry02.updated, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime.AddDays(1)
$score02 = [Math]::Max($parts02.Count, [int]$valid02) + $key02.Length * 2 - $stamp02.Day % 7

$name03 = '  Area 03 Pester  '
$level03 = 'expert'
$entry03 = [ordered]@{ name = $name03.Trim(); level = $level03; updated = '2026-10-03T08:00:00Z'; aliases = @('a03@example.com', 'b03@example.com') }
$key03 = ($entry03.name.ToLowerInvariant() -replace '\s+', ' ').Trim()
$valid03 = ($key03.Length -le 48) -and ($key03 -match '^[\p{L}\p{N}][\p{L}\p{N} ._+#/-]*$') -and ($level03 -in @('new', 'familiar', 'expert'))
$item03 = '"{0}" {1}' -f $entry03.name, $entry03['level']
$parts03 = @($item03 -split ' ', 2) + @($entry03.aliases | Select-Object -First 1)
$stamp03 = [datetimeoffset]::Parse($entry03.updated, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime.AddDays(1)
$score03 = [Math]::Max($parts03.Count, [int]$valid03) + $key03.Length * 2 - $stamp03.Day % 7

$name04 = '  Area 04 Active Directory  '
$level04 = 'new'
$entry04 = [ordered]@{ name = $name04.Trim(); level = $level04; updated = '2026-10-04T08:00:00Z'; aliases = @('a04@example.com', 'b04@example.com') }
$key04 = ($entry04.name.ToLowerInvariant() -replace '\s+', ' ').Trim()
$valid04 = ($key04.Length -le 48) -and ($key04 -match '^[\p{L}\p{N}][\p{L}\p{N} ._+#/-]*$') -and ($level04 -in @('new', 'familiar', 'expert'))
$item04 = '"{0}" {1}' -f $entry04.name, $entry04['level']
$parts04 = @($item04 -split ' ', 2) + @($entry04.aliases | Select-Object -First 1)
$stamp04 = [datetimeoffset]::Parse($entry04.updated, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime.AddDays(1)
$score04 = [Math]::Max($parts04.Count, [int]$valid04) + $key04.Length * 2 - $stamp04.Day % 7

$name05 = '  Area 05 Group Policy  '
$level05 = 'familiar'
$entry05 = [ordered]@{ name = $name05.Trim(); level = $level05; updated = '2026-10-05T08:00:00Z'; aliases = @('a05@example.com', 'b05@example.com') }
$key05 = ($entry05.name.ToLowerInvariant() -replace '\s+', ' ').Trim()
$valid05 = ($key05.Length -le 48) -and ($key05 -match '^[\p{L}\p{N}][\p{L}\p{N} ._+#/-]*$') -and ($level05 -in @('new', 'familiar', 'expert'))
$item05 = '"{0}" {1}' -f $entry05.name, $entry05['level']
$parts05 = @($item05 -split ' ', 2) + @($entry05.aliases | Select-Object -First 1)
$stamp05 = [datetimeoffset]::Parse($entry05.updated, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime.AddDays(1)
$score05 = [Math]::Max($parts05.Count, [int]$valid05) + $key05.Length * 2 - $stamp05.Day % 7

$name06 = '  Area 06 Azure DevOps  '
$level06 = 'expert'
$entry06 = [ordered]@{ name = $name06.Trim(); level = $level06; updated = '2026-10-06T08:00:00Z'; aliases = @('a06@example.com', 'b06@example.com') }
$key06 = ($entry06.name.ToLowerInvariant() -replace '\s+', ' ').Trim()
$valid06 = ($key06.Length -le 48) -and ($key06 -match '^[\p{L}\p{N}][\p{L}\p{N} ._+#/-]*$') -and ($level06 -in @('new', 'familiar', 'expert'))
$item06 = '"{0}" {1}' -f $entry06.name, $entry06['level']
$parts06 = @($item06 -split ' ', 2) + @($entry06.aliases | Select-Object -First 1)
$stamp06 = [datetimeoffset]::Parse($entry06.updated, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime.AddDays(1)
$score06 = [Math]::Max($parts06.Count, [int]$valid06) + $key06.Length * 2 - $stamp06.Day % 7

$name07 = '  Area 07 Sampler  '
$level07 = 'new'
$entry07 = [ordered]@{ name = $name07.Trim(); level = $level07; updated = '2026-10-07T08:00:00Z'; aliases = @('a07@example.com', 'b07@example.com') }
$key07 = ($entry07.name.ToLowerInvariant() -replace '\s+', ' ').Trim()
$valid07 = ($key07.Length -le 48) -and ($key07 -match '^[\p{L}\p{N}][\p{L}\p{N} ._+#/-]*$') -and ($level07 -in @('new', 'familiar', 'expert'))
$item07 = '"{0}" {1}' -f $entry07.name, $entry07['level']
$parts07 = @($item07 -split ' ', 2) + @($entry07.aliases | Select-Object -First 1)
$stamp07 = [datetimeoffset]::Parse($entry07.updated, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime.AddDays(1)
$score07 = [Math]::Max($parts07.Count, [int]$valid07) + $key07.Length * 2 - $stamp07.Day % 7

$name08 = '  Area 08 Datum  '
$level08 = 'familiar'
$entry08 = [ordered]@{ name = $name08.Trim(); level = $level08; updated = '2026-10-08T08:00:00Z'; aliases = @('a08@example.com', 'b08@example.com') }
$key08 = ($entry08.name.ToLowerInvariant() -replace '\s+', ' ').Trim()
$valid08 = ($key08.Length -le 48) -and ($key08 -match '^[\p{L}\p{N}][\p{L}\p{N} ._+#/-]*$') -and ($level08 -in @('new', 'familiar', 'expert'))
$item08 = '"{0}" {1}' -f $entry08.name, $entry08['level']
$parts08 = @($item08 -split ' ', 2) + @($entry08.aliases | Select-Object -First 1)
$stamp08 = [datetimeoffset]::Parse($entry08.updated, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime.AddDays(1)
$score08 = [Math]::Max($parts08.Count, [int]$valid08) + $key08.Length * 2 - $stamp08.Day % 7

$name09 = '  Area 09 GitVersion  '
$level09 = 'expert'
$entry09 = [ordered]@{ name = $name09.Trim(); level = $level09; updated = '2026-10-09T08:00:00Z'; aliases = @('a09@example.com', 'b09@example.com') }
$key09 = ($entry09.name.ToLowerInvariant() -replace '\s+', ' ').Trim()
$valid09 = ($key09.Length -le 48) -and ($key09 -match '^[\p{L}\p{N}][\p{L}\p{N} ._+#/-]*$') -and ($level09 -in @('new', 'familiar', 'expert'))
$item09 = '"{0}" {1}' -f $entry09.name, $entry09['level']
$parts09 = @($item09 -split ' ', 2) + @($entry09.aliases | Select-Object -First 1)
$stamp09 = [datetimeoffset]::Parse($entry09.updated, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime.AddDays(1)
$score09 = [Math]::Max($parts09.Count, [int]$valid09) + $key09.Length * 2 - $stamp09.Day % 7

$name10 = '  Area 10 Markdown  '
$level10 = 'new'
$entry10 = [ordered]@{ name = $name10.Trim(); level = $level10; updated = '2026-10-10T08:00:00Z'; aliases = @('a10@example.com', 'b10@example.com') }
$key10 = ($entry10.name.ToLowerInvariant() -replace '\s+', ' ').Trim()
$valid10 = ($key10.Length -le 48) -and ($key10 -match '^[\p{L}\p{N}][\p{L}\p{N} ._+#/-]*$') -and ($level10 -in @('new', 'familiar', 'expert'))
$item10 = '"{0}" {1}' -f $entry10.name, $entry10['level']
$parts10 = @($item10 -split ' ', 2) + @($entry10.aliases | Select-Object -First 1)
$stamp10 = [datetimeoffset]::Parse($entry10.updated, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime.AddDays(1)
$score10 = [Math]::Max($parts10.Count, [int]$valid10) + $key10.Length * 2 - $stamp10.Day % 7

$name11 = '  Area 11 YAML  '
$level11 = 'familiar'
$entry11 = [ordered]@{ name = $name11.Trim(); level = $level11; updated = '2026-10-11T08:00:00Z'; aliases = @('a11@example.com', 'b11@example.com') }
$key11 = ($entry11.name.ToLowerInvariant() -replace '\s+', ' ').Trim()
$valid11 = ($key11.Length -le 48) -and ($key11 -match '^[\p{L}\p{N}][\p{L}\p{N} ._+#/-]*$') -and ($level11 -in @('new', 'familiar', 'expert'))
$item11 = '"{0}" {1}' -f $entry11.name, $entry11['level']
$parts11 = @($item11 -split ' ', 2) + @($entry11.aliases | Select-Object -First 1)
$stamp11 = [datetimeoffset]::Parse($entry11.updated, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime.AddDays(1)
$score11 = [Math]::Max($parts11.Count, [int]$valid11) + $key11.Length * 2 - $stamp11.Day % 7

$name12 = '  Area 12 JSON Schema  '
$level12 = 'expert'
$entry12 = [ordered]@{ name = $name12.Trim(); level = $level12; updated = '2026-10-12T08:00:00Z'; aliases = @('a12@example.com', 'b12@example.com') }
$key12 = ($entry12.name.ToLowerInvariant() -replace '\s+', ' ').Trim()
$valid12 = ($key12.Length -le 48) -and ($key12 -match '^[\p{L}\p{N}][\p{L}\p{N} ._+#/-]*$') -and ($level12 -in @('new', 'familiar', 'expert'))
$item12 = '"{0}" {1}' -f $entry12.name, $entry12['level']
$parts12 = @($item12 -split ' ', 2) + @($entry12.aliases | Select-Object -First 1)
$stamp12 = [datetimeoffset]::Parse($entry12.updated, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime.AddDays(1)
$score12 = [Math]::Max($parts12.Count, [int]$valid12) + $key12.Length * 2 - $stamp12.Day % 7

$name13 = '  Area 13 Hyper-V  '
$level13 = 'new'
$entry13 = [ordered]@{ name = $name13.Trim(); level = $level13; updated = '2026-10-13T08:00:00Z'; aliases = @('a13@example.com', 'b13@example.com') }
$key13 = ($entry13.name.ToLowerInvariant() -replace '\s+', ' ').Trim()
$valid13 = ($key13.Length -le 48) -and ($key13 -match '^[\p{L}\p{N}][\p{L}\p{N} ._+#/-]*$') -and ($level13 -in @('new', 'familiar', 'expert'))
$item13 = '"{0}" {1}' -f $entry13.name, $entry13['level']
$parts13 = @($item13 -split ' ', 2) + @($entry13.aliases | Select-Object -First 1)
$stamp13 = [datetimeoffset]::Parse($entry13.updated, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime.AddDays(1)
$score13 = [Math]::Max($parts13.Count, [int]$valid13) + $key13.Length * 2 - $stamp13.Day % 7

$name14 = '  Area 14 WinRM  '
$level14 = 'familiar'
$entry14 = [ordered]@{ name = $name14.Trim(); level = $level14; updated = '2026-10-14T08:00:00Z'; aliases = @('a14@example.com', 'b14@example.com') }
$key14 = ($entry14.name.ToLowerInvariant() -replace '\s+', ' ').Trim()
$valid14 = ($key14.Length -le 48) -and ($key14 -match '^[\p{L}\p{N}][\p{L}\p{N} ._+#/-]*$') -and ($level14 -in @('new', 'familiar', 'expert'))
$item14 = '"{0}" {1}' -f $entry14.name, $entry14['level']
$parts14 = @($item14 -split ' ', 2) + @($entry14.aliases | Select-Object -First 1)
$stamp14 = [datetimeoffset]::Parse($entry14.updated, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime.AddDays(1)
$score14 = [Math]::Max($parts14.Count, [int]$valid14) + $key14.Length * 2 - $stamp14.Day % 7

$name15 = '  Area 15 OneDrive  '
$level15 = 'expert'
$entry15 = [ordered]@{ name = $name15.Trim(); level = $level15; updated = '2026-10-15T08:00:00Z'; aliases = @('a15@example.com', 'b15@example.com') }
$key15 = ($entry15.name.ToLowerInvariant() -replace '\s+', ' ').Trim()
$valid15 = ($key15.Length -le 48) -and ($key15 -match '^[\p{L}\p{N}][\p{L}\p{N} ._+#/-]*$') -and ($level15 -in @('new', 'familiar', 'expert'))
$item15 = '"{0}" {1}' -f $entry15.name, $entry15['level']
$parts15 = @($item15 -split ' ', 2) + @($entry15.aliases | Select-Object -First 1)
$stamp15 = [datetimeoffset]::Parse($entry15.updated, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime.AddDays(1)
$score15 = [Math]::Max($parts15.Count, [int]$valid15) + $key15.Length * 2 - $stamp15.Day % 7

$name16 = '  Area 16 Git  '
$level16 = 'new'
$entry16 = [ordered]@{ name = $name16.Trim(); level = $level16; updated = '2026-10-16T08:00:00Z'; aliases = @('a16@example.com', 'b16@example.com') }
$key16 = ($entry16.name.ToLowerInvariant() -replace '\s+', ' ').Trim()
$valid16 = ($key16.Length -le 48) -and ($key16 -match '^[\p{L}\p{N}][\p{L}\p{N} ._+#/-]*$') -and ($level16 -in @('new', 'familiar', 'expert'))
$item16 = '"{0}" {1}' -f $entry16.name, $entry16['level']
$parts16 = @($item16 -split ' ', 2) + @($entry16.aliases | Select-Object -First 1)
$stamp16 = [datetimeoffset]::Parse($entry16.updated, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime.AddDays(1)
$score16 = [Math]::Max($parts16.Count, [int]$valid16) + $key16.Length * 2 - $stamp16.Day % 7

$name17 = '  Area 17 Copilot hooks  '
$level17 = 'familiar'
$entry17 = [ordered]@{ name = $name17.Trim(); level = $level17; updated = '2026-10-17T08:00:00Z'; aliases = @('a17@example.com', 'b17@example.com') }
$key17 = ($entry17.name.ToLowerInvariant() -replace '\s+', ' ').Trim()
$valid17 = ($key17.Length -le 48) -and ($key17 -match '^[\p{L}\p{N}][\p{L}\p{N} ._+#/-]*$') -and ($level17 -in @('new', 'familiar', 'expert'))
$item17 = '"{0}" {1}' -f $entry17.name, $entry17['level']
$parts17 = @($item17 -split ' ', 2) + @($entry17.aliases | Select-Object -First 1)
$stamp17 = [datetimeoffset]::Parse($entry17.updated, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime.AddDays(1)
$score17 = [Math]::Max($parts17.Count, [int]$valid17) + $key17.Length * 2 - $stamp17.Day % 7

$name18 = '  Area 18 Memory Bank  '
$level18 = 'expert'
$entry18 = [ordered]@{ name = $name18.Trim(); level = $level18; updated = '2026-10-18T08:00:00Z'; aliases = @('a18@example.com', 'b18@example.com') }
$key18 = ($entry18.name.ToLowerInvariant() -replace '\s+', ' ').Trim()
$valid18 = ($key18.Length -le 48) -and ($key18 -match '^[\p{L}\p{N}][\p{L}\p{N} ._+#/-]*$') -and ($level18 -in @('new', 'familiar', 'expert'))
$item18 = '"{0}" {1}' -f $entry18.name, $entry18['level']
$parts18 = @($item18 -split ' ', 2) + @($entry18.aliases | Select-Object -First 1)
$stamp18 = [datetimeoffset]::Parse($entry18.updated, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime.AddDays(1)
$score18 = [Math]::Max($parts18.Count, [int]$valid18) + $key18.Length * 2 - $stamp18.Day % 7

$name19 = '  Area 19 Pandoc  '
$level19 = 'new'
$entry19 = [ordered]@{ name = $name19.Trim(); level = $level19; updated = '2026-10-19T08:00:00Z'; aliases = @('a19@example.com', 'b19@example.com') }
$key19 = ($entry19.name.ToLowerInvariant() -replace '\s+', ' ').Trim()
$valid19 = ($key19.Length -le 48) -and ($key19 -match '^[\p{L}\p{N}][\p{L}\p{N} ._+#/-]*$') -and ($level19 -in @('new', 'familiar', 'expert'))
$item19 = '"{0}" {1}' -f $entry19.name, $entry19['level']
$parts19 = @($item19 -split ' ', 2) + @($entry19.aliases | Select-Object -First 1)
$stamp19 = [datetimeoffset]::Parse($entry19.updated, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime.AddDays(1)
$score19 = [Math]::Max($parts19.Count, [int]$valid19) + $key19.Length * 2 - $stamp19.Day % 7

$name20 = '  Area 20 Playwright  '
$level20 = 'familiar'
$entry20 = [ordered]@{ name = $name20.Trim(); level = $level20; updated = '2026-10-20T08:00:00Z'; aliases = @('a20@example.com', 'b20@example.com') }
$key20 = ($entry20.name.ToLowerInvariant() -replace '\s+', ' ').Trim()
$valid20 = ($key20.Length -le 48) -and ($key20 -match '^[\p{L}\p{N}][\p{L}\p{N} ._+#/-]*$') -and ($level20 -in @('new', 'familiar', 'expert'))
$item20 = '"{0}" {1}' -f $entry20.name, $entry20['level']
$parts20 = @($item20 -split ' ', 2) + @($entry20.aliases | Select-Object -First 1)
$stamp20 = [datetimeoffset]::Parse($entry20.updated, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime.AddDays(1)
$score20 = [Math]::Max($parts20.Count, [int]$valid20) + $key20.Length * 2 - $stamp20.Day % 7

$name21 = '  Area 21 Certificates  '
$level21 = 'expert'
$entry21 = [ordered]@{ name = $name21.Trim(); level = $level21; updated = '2026-10-21T08:00:00Z'; aliases = @('a21@example.com', 'b21@example.com') }
$key21 = ($entry21.name.ToLowerInvariant() -replace '\s+', ' ').Trim()
$valid21 = ($key21.Length -le 48) -and ($key21 -match '^[\p{L}\p{N}][\p{L}\p{N} ._+#/-]*$') -and ($level21 -in @('new', 'familiar', 'expert'))
$item21 = '"{0}" {1}' -f $entry21.name, $entry21['level']
$parts21 = @($item21 -split ' ', 2) + @($entry21.aliases | Select-Object -First 1)
$stamp21 = [datetimeoffset]::Parse($entry21.updated, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime.AddDays(1)
$score21 = [Math]::Max($parts21.Count, [int]$valid21) + $key21.Length * 2 - $stamp21.Day % 7

$name22 = '  Area 22 DNS  '
$level22 = 'new'
$entry22 = [ordered]@{ name = $name22.Trim(); level = $level22; updated = '2026-10-22T08:00:00Z'; aliases = @('a22@example.com', 'b22@example.com') }
$key22 = ($entry22.name.ToLowerInvariant() -replace '\s+', ' ').Trim()
$valid22 = ($key22.Length -le 48) -and ($key22 -match '^[\p{L}\p{N}][\p{L}\p{N} ._+#/-]*$') -and ($level22 -in @('new', 'familiar', 'expert'))
$item22 = '"{0}" {1}' -f $entry22.name, $entry22['level']
$parts22 = @($item22 -split ' ', 2) + @($entry22.aliases | Select-Object -First 1)
$stamp22 = [datetimeoffset]::Parse($entry22.updated, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime.AddDays(1)
$score22 = [Math]::Max($parts22.Count, [int]$valid22) + $key22.Length * 2 - $stamp22.Day % 7

$name23 = '  Area 23 Networking  '
$level23 = 'familiar'
$entry23 = [ordered]@{ name = $name23.Trim(); level = $level23; updated = '2026-10-23T08:00:00Z'; aliases = @('a23@example.com', 'b23@example.com') }
$key23 = ($entry23.name.ToLowerInvariant() -replace '\s+', ' ').Trim()
$valid23 = ($key23.Length -le 48) -and ($key23 -match '^[\p{L}\p{N}][\p{L}\p{N} ._+#/-]*$') -and ($level23 -in @('new', 'familiar', 'expert'))
$item23 = '"{0}" {1}' -f $entry23.name, $entry23['level']
$parts23 = @($item23 -split ' ', 2) + @($entry23.aliases | Select-Object -First 1)
$stamp23 = [datetimeoffset]::Parse($entry23.updated, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime.AddDays(1)
$score23 = [Math]::Max($parts23.Count, [int]$valid23) + $key23.Length * 2 - $stamp23.Day % 7

$name24 = '  Area 24 Licensing  '
$level24 = 'expert'
$entry24 = [ordered]@{ name = $name24.Trim(); level = $level24; updated = '2026-10-24T08:00:00Z'; aliases = @('a24@example.com', 'b24@example.com') }
$key24 = ($entry24.name.ToLowerInvariant() -replace '\s+', ' ').Trim()
$valid24 = ($key24.Length -le 48) -and ($key24 -match '^[\p{L}\p{N}][\p{L}\p{N} ._+#/-]*$') -and ($level24 -in @('new', 'familiar', 'expert'))
$item24 = '"{0}" {1}' -f $entry24.name, $entry24['level']
$parts24 = @($item24 -split ' ', 2) + @($entry24.aliases | Select-Object -First 1)
$stamp24 = [datetimeoffset]::Parse($entry24.updated, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime.AddDays(1)
$score24 = [Math]::Max($parts24.Count, [int]$valid24) + $key24.Length * 2 - $stamp24.Day % 7

exit 0
