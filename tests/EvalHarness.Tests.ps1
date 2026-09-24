BeforeAll {
    $script:evalRoot = Join-Path $PSScriptRoot '../skills/agent-evals/scripts'
    $script:pwshPath = (Get-Command pwsh -ErrorAction Stop).Source

    function Invoke-EvalScript {
        param([string] $Name, [string[]] $Argument)
        $startInfo = [Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $script:pwshPath
        $arguments = @('-NoProfile', '-NonInteractive', '-File', (Join-Path $script:evalRoot $Name)) + $Argument
        $startInfo.Arguments = ($arguments | ForEach-Object { '"' + $_.Replace('"', '\"') + '"' }) -join ' '
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $process = [Diagnostics.Process]::Start($startInfo)
        try {
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            # Bound the child so a regressed regex timeout cannot hang the CI suite.
            if (-not $process.WaitForExit(15000)) {
                Stop-Process -Id $process.Id -Force -ErrorAction Stop
                $process.WaitForExit()
                throw "Eval script '$Name' exceeded the 15-second test budget."
            }
            [pscustomobject]@{
                ExitCode = $process.ExitCode
                Text = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
            }
        }
        finally {
            $process.Dispose()
        }
    }
}

Describe 'Offline evaluation gates' -Tag 'Unit' {
    BeforeAll {
        function Invoke-OfflineEval {
            param([object[]] $Cases = @($script:case), [string] $Raw)
            $json = if ($PSBoundParameters.ContainsKey('Raw')) { $Raw } else {
                @{ cases = $Cases } | ConvertTo-Json -Depth 8
            }
            Set-Content -LiteralPath $script:evalFile -Value $json -Encoding utf8
            Invoke-EvalScript -Name 'run-evals.ps1' -Argument @(
                '-EvalFile', $script:evalFile, '-OutputsDir', $script:work, '-K', '2'
            )
        }
    }

    BeforeEach {
        $script:work = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:caseDir = Join-Path $script:work 'case-1'
        New-Item -ItemType Directory -Path $script:caseDir -Force | Out-Null
        $script:evalFile = Join-Path $script:work 'evals.json'
        $script:case = @{
            id = 'case-1'; set = 'regression'; prompt = 'Return READY'
            expect = 'READY'; match = 'exact'
        }
        Set-Content -LiteralPath (Join-Path $script:caseDir 'sample-1.txt') -Value 'READY'
        Set-Content -LiteralPath (Join-Path $script:caseDir 'sample-2.txt') -Value 'READY'
    }

    It 'Preserves trimmed case-insensitive exact matches' {
        Set-Content -LiteralPath (Join-Path $script:caseDir 'sample-2.txt') -Value ' ready '
        (Invoke-OfflineEval).ExitCode | Should -Be 0
    }

    It 'Uses best-of-k for capability but all-of-k for regression' {
        Set-Content -LiteralPath (Join-Path $script:caseDir 'sample-2.txt') -Value 'wrong'
        (Invoke-OfflineEval).ExitCode | Should -Be 1
        $script:case.set = 'capability'
        (Invoke-OfflineEval).ExitCode | Should -Be 0
    }

    It 'Matches contains text literally for <Expect>' -ForEach @(
        @{ Expect = '[READY]' }, @{ Expect = '*' }, @{ Expect = '?' }
    ) {
        $script:case.match = 'contains'
        $script:case.expect = $Expect
        (Invoke-OfflineEval).ExitCode | Should -Be 1
        foreach ($number in 1..2) {
            Set-Content -LiteralPath (Join-Path $script:caseDir "sample-$number.txt") -Value "before $Expect after"
        }
        (Invoke-OfflineEval).ExitCode | Should -Be 0
    }

    It 'Preserves case-insensitive contains and regex matching' -ForEach @(
        @{ Match = 'contains'; Expect = 'ready' }, @{ Match = 'regex'; Expect = '^ready\s*$' }
    ) {
        $script:case.match = $Match
        $script:case.expect = $Expect
        (Invoke-OfflineEval).ExitCode | Should -Be 0
    }

    It 'Requires all K samples even for a capability case' {
        $script:case.set = 'capability'
        Remove-Item -LiteralPath (Join-Path $script:caseDir 'sample-2.txt')
        $result = Invoke-OfflineEval
        $result.ExitCode | Should -Be 1
        $result.Text | Should -Match 'sample-2.txt'
    }

    It 'Rejects additional or misnumbered samples: <Name>' -ForEach @(
        @{ Name = 'sample-3.txt' }, @{ Name = 'sample-01.txt' }, @{ Name = 'sample-backup.txt' }
    ) {
        Set-Content -LiteralPath (Join-Path $script:caseDir $Name) -Value 'READY'
        $result = Invoke-OfflineEval
        $result.ExitCode | Should -Be 1
        $result.Text | Should -Match ([regex]::Escape($Name))
    }

    It 'Rejects invalid case fields before grading: <Field>' -ForEach @(
        @{ Field = 'set'; Value = 'regresion' }, @{ Field = 'id'; Value = '../outside' },
        @{ Field = 'id'; Value = '..\outside' }, @{ Field = 'id'; Value = '/outside' },
        @{ Field = 'prompt'; Value = '' }, @{ Field = 'expect'; Value = '' },
        @{ Field = 'expect'; Value = 42 }, @{ Field = 'match'; Value = 'wildcard' }
    ) {
        $script:case[$Field] = $Value
        $result = Invoke-OfflineEval
        $result.ExitCode | Should -Be 1
        $result.Text | Should -Match $Field
    }

    It 'Rejects duplicate case IDs even on a case-sensitive filesystem' {
        $duplicate = $script:case.Clone()
        $duplicate.id = 'CASE-1'
        $result = Invoke-OfflineEval -Cases @($script:case, $duplicate)
        $result.ExitCode | Should -Be 1
        $result.Text | Should -Match 'duplicate'
    }

    It 'Requires a nonempty cases array rather than a coerced object' -ForEach @(
        @{ Raw = '{"cases":[]}' },
        @{ Raw = '[{"cases":[{"id":"case-1","set":"regression","prompt":"Return READY","expect":"READY"}]}]' },
        @{ Raw = '{"cases":{"id":"case-1","set":"regression","prompt":"Return READY","expect":"READY"}}' }
    ) {
        (Invoke-OfflineEval -Raw $Raw).ExitCode | Should -Be 1
    }

    It 'Fails explicitly when a regex exceeds its matching budget' {
        $script:case.match = 'regex'
        $script:case.expect = '^(a+)+$'
        Set-Content -LiteralPath (Join-Path $script:caseDir 'sample-1.txt') -Value (('a' * 512) + '!')
        $result = Invoke-OfflineEval
        $result.ExitCode | Should -Be 1
        $result.Text | Should -Match 'time.?out|timed out'
    }

    It 'Defaults an omitted match field to contains' {
        $script:case.Remove('match')
        (Invoke-OfflineEval).ExitCode | Should -Be 0
    }

    It 'Rejects an invalid regex even when no output exists' {
        $script:case.match = 'regex'
        $script:case.expect = '['
        Remove-Item -LiteralPath $script:caseDir -Recurse
        $result = Invoke-OfflineEval
        $result.ExitCode | Should -Be 1
        $result.Text | Should -Match 'regex'
    }
}

Describe 'Trigger evaluation grading gates' -Tag 'Unit' {
    BeforeAll {
        function Invoke-TriggerGrade {
            param([string] $TargetSkill = 'alpha-skill')

            Set-Content -LiteralPath $script:queryFile -Encoding utf8 -Value (
                ConvertTo-Json -InputObject $script:queries -Depth 5
            )
            Invoke-EvalScript -Name 'run-trigger-evals.ps1' -Argument @(
                '-Mode', 'Grade', '-QueryFile', $script:queryFile,
                '-TargetSkill', $TargetSkill, '-WorkDir', $script:work, '-Repetitions', '2'
            )
        }
    }

    BeforeEach {
        $script:work = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:work | Out-Null
        $script:queryFile = Join-Path $script:work 'queries.json'
        $script:queries = @(
            @{ id = 'train-pos'; query = 'alpha work'; should_trigger = $true; split = 'train' },
            @{ id = 'train-neg'; query = 'beta work'; should_trigger = $false; split = 'train' },
            @{ id = 'validation-pos'; query = 'more alpha work'; should_trigger = $true; split = 'validation' },
            @{ id = 'validation-neg'; query = 'more beta work'; should_trigger = $false; split = 'validation' }
        )
        foreach ($query in $script:queries) {
            $defaultReply = if ($query.should_trigger) { 'SELECTED: alpha-skill' } else { 'SELECTED: none' }
            foreach ($rep in 1..2) {
                Set-Content -LiteralPath (Join-Path $script:work "$($query.id).rep$rep.out.txt") -Value $defaultReply
            }
        }
    }

    It 'Passes complete positive and near-miss negative replies on both splits' {
        (Invoke-TriggerGrade).ExitCode | Should -Be 0
    }

    It 'Preserves case-insensitive target identity' {
        (Invoke-TriggerGrade -TargetSkill 'ALPHA-SKILL').ExitCode | Should -Be 0
    }

    It 'Fails a misclassified positive or negative query: <Id>' -ForEach @(
        @{ Id = 'train-pos'; Reply = 'SELECTED: none' },
        @{ Id = 'validation-neg'; Reply = 'SELECTED: alpha-skill' }
    ) {
        foreach ($rep in 1..2) {
            Set-Content -LiteralPath (Join-Path $script:work "$Id.rep$rep.out.txt") -Value $Reply
        }
        (Invoke-TriggerGrade).ExitCode | Should -Be 1
    }

    It 'Never treats malformed output as a successful negative: <Label>' -ForEach @(
        @{ Label = 'empty'; Reply = '' }, @{ Label = 'backend error'; Reply = 'model request failed' },
        @{ Label = 'embedded verdict'; Reply = "Explanation`nSELECTED: none" },
        @{ Label = 'conflicting verdicts'; Reply = "SELECTED: none`nSELECTED: alpha-skill" }
    ) {
        Set-Content -LiteralPath (Join-Path $script:work 'train-neg.rep1.out.txt') -Value $Reply
        $result = Invoke-TriggerGrade
        $result.ExitCode | Should -Be 1
        $result.Text | Should -Match 'invalid'
    }

    It 'Fails incomplete evidence without dropping its query from the denominator' {
        Remove-Item -LiteralPath (Join-Path $script:work 'validation-pos.rep1.out.txt')
        Remove-Item -LiteralPath (Join-Path $script:work 'validation-pos.rep2.out.txt')
        $result = Invoke-TriggerGrade
        $result.ExitCode | Should -Be 1
        $result.Text | Should -Match 'validation\s+pass\s+1/2'
        $result.Text | Should -Match 'incomplete 1'
    }

    It 'Requires every requested repetition, not just one valid reply' {
        Remove-Item -LiteralPath (Join-Path $script:work 'train-neg.rep2.out.txt')
        (Invoke-TriggerGrade).ExitCode | Should -Be 1
    }

    It 'Rejects query IDs that escape the working directory' {
        $script:queries[0].id = '../outside'
        $result = Invoke-TriggerGrade
        $result.ExitCode | Should -Be 1
        $result.Text | Should -Match 'invalid id'
    }

    It 'Returns no-evidence exit code 2 when every reply is absent' {
        Get-ChildItem -LiteralPath $script:work -Filter '*.out.txt' -File | Remove-Item
        (Invoke-TriggerGrade).ExitCode | Should -Be 2
    }

    It 'Accepts another well-formed Skill name for a negative query' {
        foreach ($rep in 1..2) {
            Set-Content -LiteralPath (Join-Path $script:work "train-neg.rep$rep.out.txt") -Value 'SELECTED: beta-skill'
        }
        (Invoke-TriggerGrade).ExitCode | Should -Be 0
    }

    It 'Rejects invalid query identity and labels: <Field>' -ForEach @(
        @{ Field = 'id'; Value = '' }, @{ Field = 'id'; Value = '..\outside' },
        @{ Field = 'id'; Value = 'TRAIN-NEG' }, @{ Field = 'query'; Value = 42 },
        @{ Field = 'should_trigger'; Value = 'false' }, @{ Field = 'split'; Value = 'test' },
        @{ Field = 'split'; Value = @('train') }
    ) {
        $script:queries[0][$Field] = $Value
        (Invoke-TriggerGrade).ExitCode | Should -Be 1
    }

    It 'Rejects a split without both positive and negative queries' {
        $script:queries[2].should_trigger = $false
        (Invoke-TriggerGrade).ExitCode | Should -Be 1
    }

    It 'Does not execute instructions embedded in a reply' {
        $canary = Join-Path $script:work 'must-not-exist.txt'
        $replyText = "SELECTED: none`nSet-Content -LiteralPath '$canary' -Value compromised"
        Set-Content -LiteralPath (Join-Path $script:work 'train-neg.rep1.out.txt') -Value $replyText
        (Invoke-TriggerGrade).ExitCode | Should -Be 1
        Test-Path -LiteralPath $canary | Should -BeFalse
    }
}
