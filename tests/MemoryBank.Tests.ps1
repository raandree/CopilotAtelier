BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $script:initializerPath = Join-Path $repoRoot (
        'skills/memory-bank/scripts/Initialize-MemoryBank.ps1'
    )
    $script:canonicalFiles = @(
        'index.md'
        'projectbrief.md'
        'productContext.md'
        'activeContext.md'
        'techContext.md'
        'progress.md'
        'systemPatterns.md'
        'promptHistory.md'
    )
}

Describe 'Initialize-MemoryBank' {
    It 'creates exactly the canonical base with populated templates' {
        $repositoryPath = Join-Path $TestDrive 'new-repository'
        New-Item -ItemType Directory -Path $repositoryPath -Force | Out-Null

        $result = & $script:initializerPath -Path $repositoryPath -Confirm:$false
        $memoryBankPath = Join-Path $repositoryPath '.memory-bank'
        $createdFiles = @(
            Get-ChildItem -LiteralPath $memoryBankPath -File |
                Select-Object -ExpandProperty Name |
                Sort-Object
        )

        $createdFiles | Should -Be ($script:canonicalFiles | Sort-Object)
        $result | Should -HaveCount 8
        @($result | Where-Object Action -eq 'Created') | Should -HaveCount 8

        foreach ($fileName in $script:canonicalFiles) {
            $filePath = Join-Path $memoryBankPath $fileName
            $content = Get-Content -LiteralPath $filePath -Raw
            $bytes = [IO.File]::ReadAllBytes($filePath)
            $content | Should -Not -BeNullOrEmpty
            $content | Should -Not -Match '<[^>]+>'
            $content | Should -Match '(?m)^status: [a-z-]+\r?$'
            $content |
                Should -Match '(?m)^last-verified: \d{4}-\d{2}-\d{2}\r?$'
            $content | Should -Match '(?m)^owner: [a-z0-9-]+\r?$'
            $content | Should -Match '(?m)^source: .+\r?$'
            $content | Should -Not -Match "`r" -Because "$fileName needs LF only"
            $bytes[-1] | Should -Be 10 -Because "$fileName needs a final LF"
            ($bytes.Length -ge 3 -and
                $bytes[0] -eq 0xEF -and
                $bytes[1] -eq 0xBB -and
                $bytes[2] -eq 0xBF) |
                Should -BeFalse -Because "$fileName must not have a BOM"
        }

        $indexContent = Get-Content -LiteralPath (
            Join-Path $memoryBankPath 'index.md'
        ) -Raw
        $indexContent | Should -Match '(?m)^loading-mode: routed\r?$'
        $indexContent | Should -Match '(?m)^## Full-read fallback\r?$'
    }

    It 'preserves existing files byte-for-byte and creates only missing files' {
        $repositoryPath = Join-Path $TestDrive 'partial-repository'
        $memoryBankPath = Join-Path $repositoryPath '.memory-bank'
        New-Item -ItemType Directory -Path $memoryBankPath -Force | Out-Null

        $projectBriefPath = Join-Path $memoryBankPath 'projectbrief.md'
        $existingBytes = [Text.Encoding]::UTF8.GetBytes(
            "# Existing project brief`n`nKeep this exact content.`n"
        )
        [IO.File]::WriteAllBytes($projectBriefPath, $existingBytes)
        $beforeHash = (Get-FileHash -LiteralPath $projectBriefPath).Hash

        $result = & $script:initializerPath -Path $repositoryPath -Confirm:$false
        $afterHash = (Get-FileHash -LiteralPath $projectBriefPath).Hash

        $afterHash | Should -Be $beforeHash
        @($result | Where-Object Action -eq 'Preserved') | Should -HaveCount 1
        @($result | Where-Object Action -eq 'Created') | Should -HaveCount 7
    }

    It 'is idempotent on a complete Memory Bank' {
        $repositoryPath = Join-Path $TestDrive 'complete-repository'
        New-Item -ItemType Directory -Path $repositoryPath -Force | Out-Null
        & $script:initializerPath -Path $repositoryPath -Confirm:$false | Out-Null

        $memoryBankPath = Join-Path $repositoryPath '.memory-bank'
        $beforeHashes = @{}
        foreach ($file in Get-ChildItem -LiteralPath $memoryBankPath -File) {
            $beforeHashes[$file.Name] = (Get-FileHash -LiteralPath $file.FullName).Hash
        }

        $result = & $script:initializerPath -Path $repositoryPath -Confirm:$false

        @($result | Where-Object Action -eq 'Preserved') | Should -HaveCount 8
        foreach ($file in Get-ChildItem -LiteralPath $memoryBankPath -File) {
            (Get-FileHash -LiteralPath $file.FullName).Hash |
                Should -Be $beforeHashes[$file.Name]
        }
    }

    It 'honors WhatIf without creating the Memory Bank' {
        $repositoryPath = Join-Path $TestDrive 'whatif-repository'
        New-Item -ItemType Directory -Path $repositoryPath -Force | Out-Null

        & $script:initializerPath -Path $repositoryPath -WhatIf | Out-Null

        Test-Path -LiteralPath (Join-Path $repositoryPath '.memory-bank') |
            Should -BeFalse
    }

    It 'plans missing files without writing to a partial base under WhatIf' {
        $repositoryPath = Join-Path $TestDrive 'partial-whatif-repository'
        $memoryBankPath = Join-Path $repositoryPath '.memory-bank'
        New-Item -ItemType Directory -Path $memoryBankPath -Force | Out-Null
        $projectBriefPath = Join-Path $memoryBankPath 'projectbrief.md'
        [IO.File]::WriteAllText($projectBriefPath, '# Existing')
        $beforeHash = (Get-FileHash -LiteralPath $projectBriefPath).Hash

        $result = & $script:initializerPath -Path $repositoryPath -WhatIf

        (Get-FileHash -LiteralPath $projectBriefPath).Hash | Should -Be $beforeHash
        @(Get-ChildItem -LiteralPath $memoryBankPath -File) | Should -HaveCount 1
        @($result | Where-Object Action -eq 'Preserved') | Should -HaveCount 1
        @($result | Where-Object Action -eq 'Planned') | Should -HaveCount 7
    }
}
