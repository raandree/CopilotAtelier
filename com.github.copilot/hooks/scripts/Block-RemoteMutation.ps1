<#
.SYNOPSIS
    PreToolUse hook that blocks remote-mutating and irreversible commands.
.DESCRIPTION
    Reads the VS Code PreToolUse hook payload from standard input and inspects
    any tool input that carries executable command text for operations the
    Copilot Atelier house rules forbid without explicit per-turn authorization:
    pushing to a remote, bypassing repository hooks, discarding work with a hard
    reset or forced clean, and mutating pull requests, issues, releases,
    repositories, workflows, secrets, or the GitHub API through the GitHub CLI.

    On a match the reason is written to standard error and the script exits
    with 2, which VS Code treats as a blocking error and shows to the model.
    The same reason goes to standard output as one JSON object with only the
    top-level permissionDecision and permissionDecisionReason, which the
    Copilot SDK host merges into its deny on exit 2. Every other tool call
    exits 0.

    This is a best-effort guardrail, not a containment boundary. It matches
    patterns in a command string, so an obfuscated or indirectly invoked push
    can evade it. It removes the accidental path; branch protection and a
    server-side policy remain the real enforcement. Known evasions include a
    variable or alias standing in for the subcommand (git $verb, or git -c
    alias.p=push p), a field name spelled with JSON escapes whose value hides
    the program behind an escaped quote, and arguments nested in arrays of
    arrays.

    The command-bearing fields are walked up to 64 levels deep and 20,000
    fields and nested objects, in payloads up to 1 MB; plain values in arrays
    do not count. When the walk cannot cover the payload, because it is nested
    deeper, larger, holds more fields or objects, or is not valid JSON, the
    raw payload text is also scanned, with its JSON escapes decoded and
    without its JSON punctuation, before the call is allowed. That errs
    toward blocking: there, a payload that only mentions a blocked command is
    blocked. The whole decision has a time limit, five seconds by default, of
    which the walk may use half. A payload not inspected within it is blocked,
    and so is one larger than 4 MB, so no payload outlasts the hook timeout,
    which fails open.

    A command that only mentions a blocked operation in a string literal is
    not an invocation. Text that parses as PowerShell and holds no indirect
    execution (Invoke-Expression, a computed command name, a nested shell with
    inline code, and similar) is read as a syntax tree: the literals that only
    feed a data-writing cmdlet (Write-Output, Set-Content, Out-File, and the
    like), a variable, or a commit message are blanked before the patterns run,
    and Start-Process for git or gh is read as the command line it launches.
    Everything else is scanned as written, so text that does not parse, the
    arguments of any other program, and every form of indirect execution err
    toward blocking as before.

    A push or a mutating GitHub CLI call can be authorized by the user, never
    by the agent. The UserPromptSubmit hook Add-RemoteGrant.ps1 records a Remote
    grant when the user's own prompt carries a Grant marker such as
    [[allow-remote: git push]], and this script consumes it: each operation the
    grant names may run once, or the stated number of times, in that session,
    until the user's next prompt or 15 minutes at most. The destructive local
    blocks (git reset --hard, git clean -f, --no-verify) are never lifted. A
    grant is honored only for a payload this script read completely and that
    names a session; whatever it had to scan as raw text stays blocked. An
    allowed call prints nothing, because a hook allow would approve the call in
    VS Code. The override COPILOT_ATELIER_ALLOW_REMOTE was removed on
    2026-10-12: set in the environment a host starts the hook with, it turned the
    guard off for every chat of that instance, and an agent could never set it
    for one command. An agent that can write files could forge a grant, so this
    stays a guard against accidents, not a containment boundary.
.PARAMETER InputJson
    Hook payload as JSON. Defaults to reading standard input. Tests pass the
    payload directly so they do not depend on redirected input.
.PARAMETER TimeLimitSecond
    Longest time, in seconds, the guard may take to decide, counted from its
    start. Defaults to 5. A value outside 0.1 to 10 is clamped into that range,
    and one that is not a number falls back to 5, rather than being rejected:
    a rejected parameter would exit 1, which VS Code treats as a warning. The
    hook never passes it; tests lower it.
.PARAMETER GrantRoot
    Directory holding the Remote grant files. Defaults to CopilotAtelier/grants
    under the per-user application data folder. Tests override it to stay off
    the real profile; the hook never passes it.
.NOTES
    Exit codes follow the VS Code hook contract: 0 allows, 2 blocks, and any
    other value is a non-blocking warning. The Copilot SDK host instead denies
    a preToolUse call on every non-zero exit, so this script uses only 0 and 2:
    an unreadable payload is allowed with a warning on standard error unless
    its raw text carries a blocked command.
#>

using namespace System.Management.Automation.Language

[CmdletBinding()]
param(
    [Parameter()]
    [AllowEmptyString()]
    [AllowNull()]
    [string]$InputJson,

    [Parameter()]
    [string]$TimeLimitSecond = '5',

    [Parameter()]
    [AllowEmptyString()]
    [AllowNull()]
    [string]$GrantRoot
)

# The time limit counts from here, so it also covers reading and parsing the payload.
$decisionClock = [System.Diagnostics.Stopwatch]::StartNew()

# Parse and clamp rather than validate: a rejected parameter exits 1, which
# VS Code treats as a warning, so a bad value would let a blocked command through.
$timeLimitValue = 0.0
$isNumber = [double]::TryParse(
    $TimeLimitSecond,
    [System.Globalization.NumberStyles]::Float,
    [System.Globalization.CultureInfo]::InvariantCulture,
    [ref]$timeLimitValue
)
if (-not $isNumber) {
    $timeLimitValue = 5
}
if (-not ($timeLimitValue -ge 0.1)) {
    $timeLimitValue = 0.1
} elseif ($timeLimitValue -gt 10) {
    $timeLimitValue = 10
}

# Each git rule anchors on the subcommand position so a branch name, commit
# message, or --grep value that merely contains the word does not trip it. The
# most consequential rule is listed first, and the reason a block reports is the
# first matching rule that no Grant marker can lift, else the first that matches.
# Kind names what a Remote grant can authorize: push, gh (a pull request, issue,
# release, repository, workflow, secret, or cache verb), and api. The three
# destructive local rules carry no Kind, so no marker lifts them.
$gitCommand = '(?i)\bgit(?:\.exe)?[''"]?(?=\s)'
# --% stops PowerShell parsing, so what follows it reaches the program as written; it is an option
# like any other here, or git --% push origin main would slip past every rule (review F2).
$gitOption = '(?:\s+(?:-c\s+\S+|--%|--?[\w-]+(?:=\S+)?))*'
$ghCommand = '(?i)\bgh(?:\.exe)?[''"]?(?=\s)'
$ghOption = '(?:\s+(?:-R\s+\S+|--(?:repo|hostname)\s+\S+|--%|--?[\w-]+(?:=\S+)?))*'
$operationRule = @(
    [pscustomobject]@{
        Reason = 'pushes to a git remote'
        Pattern = "$gitCommand$gitOption\s+push\b"
        Kind = 'push'
    }
    [pscustomobject]@{
        Reason = 'bypasses repository hooks'
        Pattern = "$gitCommand[^\r\n]*\s--no-verify\b"
        Kind = ''
    }
    [pscustomobject]@{
        Reason = 'discards work with a hard reset'
        Pattern = "$gitCommand$gitOption\s+reset\b[^\r\n]*?\s--hard\b"
        Kind = ''
    }
    [pscustomobject]@{
        Reason = 'force-deletes untracked files'
        Pattern = "$gitCommand$gitOption\s+clean\b(?![^\r\n]*\s-[a-z]*n)[^\r\n]*\s-[a-z]*f"
        Kind = ''
    }
    [pscustomobject]@{
        Reason = 'mutates a GitHub remote resource'
        Pattern = "$ghCommand$ghOption\s+(?<operation>pr\s+(?:create|merge|close|comment|review|edit|ready|reopen)|issue\s+(?:create|close|comment|edit|reopen)|release\s+(?:create|delete|edit|upload)|repo\s+(?:create|delete|archive|rename|edit)|workflow\s+(?:run|enable|disable)|secret\s+(?:set|delete)|cache\s+delete)\b"
        Kind = 'gh'
    }
    [pscustomobject]@{
        Reason = 'calls a mutating GitHub API endpoint'
        Pattern = "$ghCommand$ghOption\s+api\b[^\r\n]*(?:--method\s+(?:post|put|patch|delete)\b|\s-X\s+(?:post|put|patch|delete)\b|\bmutation\b)"
        Kind = 'api'
    }
)

# Every operation a Grant marker may name. Keep identical to Add-RemoteGrant.ps1,
# which writes the grants this script reads.
$grantableOperation = @(
    'git push'
    'git push --force'
    'gh pr create'
    'gh pr merge'
    'gh pr close'
    'gh pr comment'
    'gh pr review'
    'gh pr edit'
    'gh pr ready'
    'gh pr reopen'
    'gh issue create'
    'gh issue close'
    'gh issue comment'
    'gh issue edit'
    'gh issue reopen'
    'gh release create'
    'gh release delete'
    'gh release edit'
    'gh release upload'
    'gh repo create'
    'gh repo delete'
    'gh repo archive'
    'gh repo rename'
    'gh repo edit'
    'gh workflow run'
    'gh workflow enable'
    'gh workflow disable'
    'gh secret set'
    'gh secret delete'
    'gh cache delete'
    'gh api'
)

# Phrases are compared ordinally: a culture-sensitive -in treats a zero-width space or a soft hyphen as
# nothing, so a grant could name an operation that no command ever matches (review F4).
$grantableOperationSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$grantableOperation, [System.StringComparer]::Ordinal)

# A push the plain git push phrase does not cover: force, delete, mirror, and prune options, all, branches, and tags
# (every branch or every tag), short option clusters that hold f or d, and +ref or :ref refspecs. The text
# after the push word, up to the end of its statement, is read. git reads any unambiguous prefix of a long option
# (--del is --delete, and --branches is another name for --all), and it reads a name or an option the same when it
# is quoted or in parentheses, so both are read here. A prefix that two options share, which git rejects, is read
# as the stronger option as well: that only asks for the stronger marker (review of 2026-10-13, fifth pass, F4 and F5).
$forceLongOption = @('force', 'force-with-lease', 'force-if-includes', 'delete', 'mirror', 'prune', 'all', 'branches', 'tags')
$forceLongPrefix = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($forceLongName in $forceLongOption) {
    foreach ($forcePrefixLength in 1..$forceLongName.Length) {
        $null = $forceLongPrefix.Add($forceLongName.Substring(0, $forcePrefixLength))
    }
}

$forceLongPattern = (@($forceLongPrefix | Sort-Object -Property Length -Descending | ForEach-Object -Process { [regex]::Escape($_) }) -join '|')
$forcePushOption = [regex]::new(
    ('(?:^|\s)["''(]*(?:--(?:' + $forceLongPattern + ')(?:=\S*)?|-[a-z]*[fd][a-z]*|(?:\+:?|:)[^\s:]\S*)(?=["'')]*(?:\s|$))'),
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase,
    [TimeSpan]::FromSeconds(1)
)
$statementEnd = [regex]::new('\r?\n|;|&&|\|\||\|', [System.Text.RegularExpressions.RegexOptions]::None, [TimeSpan]::FromSeconds(1))

# Syntax that can run one command more than once. The guard counts the operations it reads, not the times
# they run, so a command that repeats asks for every use a marker can grant (review F3 and G2). The shapes
# are narrow on purpose, a loop head followed by its block, a function or a class with a body, a pipeline into
# ForEach-Object, the ForEach and Where methods, cmd's for /l, shell while and until loops, retry and watch
# wrappers (also behind a launcher such as npx or sudo; the watchers nodemon and watchexec by name), schedulers
# and event registration, so that prose does not match. It runs on the command text
# without the text of its string literals, which is not code (review G3). Code that a parsed text stores in
# a script block or runs from a variable is found in the syntax tree instead (Test-StoredCode), which sees
# the forms no list can name.
$repetitionSyntax = [regex]::new(
    '(?:\b(?:foreach|for|while|until)\s*\((?:[^()\r\n]|\([^()\r\n]*\))*\)\s*\{|\bswitch\s+(?:-\w+\s+)*\(|\bdo\s*\{|\bforeach-object\b|\|\s*(?:%|\?)\s*\{|\|\s*(?:foreach|where)(?:-object)?\b|(?:\.|::)\s*(?:foreach|where)\s*\(|\.\s*invoke\w*\s*\(|\s-parallel\b|\bfor\s+%*\w+\s+in\b(?:[^\r\n]*?\bdo\b|[^\r\n]*\r?\n\s*do\b)|\bfor\s+/[a-z]\b|\bxargs\b|\s-exec(?:dir)?\s|\b(?:function|filter|workflow|configuration)\s+[\w:.-]+\s*(?:\([^)\r\n]*\))?\s*\{|(?:^|[;|&{(]\s*|\n\s*)&\s*[\$(]|\bclass\s+[\w.-]+\s*(?::\s*[\w.,\[\] ]+)?\{|\bfor\s*\(\(|(?:^|[;|&({''"]\s*|\n\s*|\b(?:then|do|else|elif)\s+|\b(?:npx|sudo|doas|nohup|exec|time|command|env|setsid|timeout|stdbuf|nice|ionice|winpty)\s+(?:(?!(?:git|gh)\b)\S+\s+){0,3}?)(?:(?:while|until)\s|(?:[\w.~:-]*[\\/])*(?:watch|retry|repeat|parallel)\w*\b)|(?<![\w.-])(?:nodemon|watchexec|entr|fswatch|inotifywait)(?:\.(?:exe|cmd|bat))?(?=[\s"''`);|&,}]|$)|\b(?:schtasks|crontab|register-[\w-]*(?:scheduledtask|scheduledjob|objectevent|engineevent|cimindicationevent|wmievent|pssessionconfiguration)|new-scheduledtask\w*)\b)',
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase,
    [TimeSpan]::FromSeconds(1)
)

$maximumOperationMatch = 50
$grantLifetimeLimitSecond = 3600
$grantClockSkewSecond = 120
$maximumGrantFileLength = 65536
$maximumUsePerOperation = 20

# Field names that carry executable command text. Gating on the presence of one
# of these is tool-agnostic; gating on the tool name misses executors whose name
# lacks a shell keyword, and every miss would fail open.
$commandField = @('command', 'commandLine', 'cmd', 'script', 'args', 'arguments')

# Of those, the fields that name what runs; the others carry its arguments.
$executableField = @('command', 'commandLine', 'cmd', 'script')

# The same fields in raw JSON text: the field name, then a string value or a
# flat array of values.
$rawFieldPattern = '"(' + (($commandField | ForEach-Object { [regex]::Escape($_) }) -join '|') +
    ')"\s*:\s*(?:"((?:[^"\\]|\\.)*)"|\[([^\[\]]*)\])'

# Some patterns scan to the end of the line from every git word, which grows
# quadratically: 64 KB of git words took 21.5 seconds, past the 20-second hook
# timeout, and a timeout fails open in the Copilot SDK host. Many matches that
# each stay under a second add up the same way, so the limit covers the whole
# decision: every match gets only the time left, and a payload not inspected in
# time is blocked.
$timeLimit = [TimeSpan]::FromSeconds($timeLimitValue)
$notInspectedInTime = 'this command could not be inspected within the time limit'

# Parsing and the field walk cannot be interrupted, and 300,000 small objects
# kept the walk busy past the hook timeout. So only a payload up to 1 MB is
# parsed, and the walk stops after 20,000 fields and nested objects, or half
# the time limit; plain values in arrays cost only time. What it did not cover
# is scanned as raw text, which the time limit does bound. A payload over 4 MB
# is blocked unscanned: no model writes a tool call that large, and even the
# linear passes over it take seconds. Those passes run
# between the field join and the pattern scan and do not read the clock, so a
# decision can overrun the limit by about 1.5 seconds (6.3 seconds measured at
# worst). Reading the payload is linear as well: 96 MB took 15.9 seconds, so
# outlasting the hook timeout would take about 120 MB.
$maximumParseLength = 1MB
$maximumPayloadLength = 4MB
$maximumVisitCount = 20000
$walkTimeLimit = [TimeSpan]::FromTicks([long]($timeLimit.Ticks / 2))
$visitCount = 0

# The field walk stops below this depth. Whatever it cannot reach, it reports,
# and the raw payload text is scanned instead, so nesting cannot carry a
# command past the guard.
$maximumDepth = 64
$isWalkComplete = $true
$walkStopReason = $null

# The walk collects the command-bearing values here in document order, and
# each object's executables-first join, so either order reads as a command.
$commandPart = [System.Collections.Generic.List[string]]::new()
$objectCommand = [System.Collections.Generic.List[string]]::new()

# A brace between two fields in raw text means they may belong to different
# objects, so the raw join starts a new object there.
$braceCharacter = [char[]]'{}'

# A command string is read as PowerShell only up to this size, and only while its
# syntax tree stays this small, so parsing stays far inside the hook timeout.
$maximumMaskLength = 65536
$maximumMaskNodeCount = 20000

# Commands whose arguments are text they print, save, or search: a literal given
# to one of these is data, as long as nothing after it in the pipeline can run it,
# and as long as the name still means the cmdlet (see $definitionCommand).
$inertCommand = @(
    'write-output', 'echo', 'write-host', 'write-verbose', 'write-debug',
    'write-warning', 'write-information', 'write-error', 'set-content',
    'add-content', 'out-file', 'new-item', 'select-string'
)
# Ordinal, and matched against the name as written: .\echo.ps1 and C:\tools\write-output.cmd are programs
# that only look like the cmdlet.
$inertCommandSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$inertCommand, [System.StringComparer]::Ordinal)

# File writers whose text argument is data: [System.IO.File]::WriteAllText($path, $text) and the like.
$inertFileMember = @('writealltext', 'appendalltext', 'writealllines', 'appendalllines')

# The inert cmdlets that write text to a path. What they write is data only when the path is known to be a
# file: a path built at run time may name the Function drive, where Set-Content and New-Item define a function
# that the same command then runs (review of 2026-10-13, second pass, G1). An unknown target is not a
# known-inert target.
$fileWriterCommand = @('set-content', 'add-content', 'out-file', 'new-item')

# Every parameter of those four cmdlets, by name and by alias, in Windows PowerShell 5.1 and in PowerShell 7
# (a test compares this table with the cmdlets themselves). PowerShell binds a parameter by name, by alias, or by
# any unambiguous prefix of either, so a spelling that is not listed here may bind the path: -LP is an alias of
# -LiteralPath, not a prefix of it (review of 2026-10-13, third pass, H1). A name that is not listed is unknown,
# and a command with an unknown parameter has no readable target. path names the file the cmdlet writes, switch
# takes no argument, value takes one.
$writerParameterKind = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$writerParameterList = [ordered]@{
    'path' = @('Path', 'LiteralPath', 'PSPath', 'LP', 'FilePath', 'Name')
    'switch' = @(
        'Append', 'AsByteStream', 'Confirm', 'cf', 'Debug', 'db', 'Force', 'NoClobber', 'NoOverwrite',
        'NoNewline', 'PassThru', 'UseTransaction', 'usetx', 'Verbose', 'vb', 'WhatIf', 'wi'
    )
    'value' = @(
        'Credential', 'Encoding', 'ErrorAction', 'ea', 'ErrorVariable', 'ev', 'Exclude', 'Filter', 'Include',
        'InformationAction', 'infa', 'InformationVariable', 'iv', 'InputObject', 'ItemType', 'Type', 'OutBuffer',
        'ob', 'OutVariable', 'ov', 'PipelineVariable', 'pv', 'ProgressAction', 'proga', 'Stream', 'Target',
        'Value', 'WarningAction', 'wa', 'WarningVariable', 'wv', 'Width'
    )
}
foreach ($writerParameterGroup in $writerParameterList.Keys) {
    foreach ($writerParameterName in $writerParameterList[$writerParameterGroup]) {
        $writerParameterKind[$writerParameterName] = $writerParameterGroup
    }
}

# A path that names a drive or a provider rather than a file: function:name, env:name, HKCU:\..., and
# Microsoft.PowerShell.Core\Function::name. A single letter is a file system drive, as in C:\work.
$providerPath = [regex]::new('^\s*(?:[\w.\\-]+::|[A-Za-z][\w.-]+:)', [System.Text.RegularExpressions.RegexOptions]::None, [TimeSpan]::FromSeconds(1))

# A path inside, or the name of, a file that something runs by itself, so that what is written there is code and not
# data: a folder that git or a hook runner executes (.git\hooks\post-commit runs on the next commit), ssh's own
# folder, a PowerShell profile, a shell start-up file, a direnv file, the global git configuration, a file in a
# Startup folder, everything in VS Code's folder (its settings start a shell with arguments in every terminal, its
# launch and task files start programs, mcp.json starts servers), and a workspace file, which carries the same
# settings and tasks. A profile or a start-up file runs in the agent's own next terminal with no commit needed. A
# folder counts as well as a file in it, because -Path and -Name together form the path and neither half matches
# alone (reviews of 2026-10-13: fourth pass I1, fifth pass F3, F9, and F10, sixth pass N2).
$selfExecutingPath = [regex]::new(
    '(?:^|[\\/])\.(?:git|githooks|husky|ssh|vscode)(?:[\\/]|$)|(?:^|[\\/])\.(?:bashrc|bash_profile|bash_login|bash_logout|bash_aliases|zshrc|zshenv|zprofile|zlogin|zlogout|profile|envrc|gitconfig)$|profile\.ps1$|(?:^|[\\/])config\.fish$|(?:^|[\\/])conf\.d[\\/][^\\/]+\.fish$|(?:^|[\\/])fish[\\/]conf\.d(?:[\\/]|$)|(?:^|[\\/])Startup(?:[\\/]|$)|\.code-workspace$',
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase,
    [TimeSpan]::FromSeconds(1)
)

# A name that stands for more than one file, or for a file under another name: a wildcard, and a Windows short name
# such as PROGRA~1. A path that holds one is not a path the text spells out, so it is not a safe one (review of
# 2026-10-13, fifth pass, F2).
$unreadablePathName = [regex]::new('[*?\[]|~\d', [System.Text.RegularExpressions.RegexOptions]::None, [TimeSpan]::FromSeconds(1))

# A value that is one single-quoted string, a doubled quote inside it included. PowerShell and every POSIX shell read
# it as data, so a backtick inside it, such as a markdown code span in a commit message, is not a command
# substitution (review of 2026-10-13, seventh pass, R1).
$singleQuotedValue = [regex]::new("^'(?:[^']|'')*'\z", [System.Text.RegularExpressions.RegexOptions]::None, [TimeSpan]::FromSeconds(1))

# Commands that move the current location, after which a relative path may name another drive. Pop-Location
# returns to a place that an earlier Push-Location chose, perhaps in an earlier call, so a pop without a push in
# the same text leaves the location unknown too (review of 2026-10-13, third pass, H4).
$locationCommand = @('set-location', 'sl', 'cd', 'chdir', 'push-location', 'pushd')
$locationPushCommand = @('push-location', 'pushd')
$locationPopCommand = @('pop-location', 'popd')

# A command that repeats what follows it: the repeat and watch wrappers and the watchers, which the text pattern
# finds as bare words and the syntax tree finds by the name of a command that is quoted, called with the call
# operator, or given by its path (review of 2026-10-13, sixth pass, N4).
$repeaterCommand = [regex]::new(
    '^(?:(?:watch|retry|repeat|parallel)\w*|nodemon|watchexec|entr|fswatch|inotifywait|xargs)$',
    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase,
    [TimeSpan]::FromSeconds(1)
)

# Parameters that store a command's output in a variable named by their argument: -OutVariable and the like
# replace the value of a variable that the text assigned a literal, so the literal says nothing about it.
$variableParameter = @('outvariable', 'errorvariable', 'warningvariable', 'informationvariable', 'pipelinevariable', 'variable', 'ov', 'ev', 'wv', 'iv', 'pv')

# Common parameters that merely start like one of those, such as -wa for -WarningAction: spelled in full or by
# their alias they name another parameter, so they are not read as a prefix of -WarningVariable.
$commonNonVariableParameter = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@(
        'ErrorAction', 'ea', 'WarningAction', 'wa', 'InformationAction', 'infa', 'Debug', 'db', 'Verbose', 'vb',
        'OutBuffer', 'ob', 'ProgressAction', 'proga', 'WhatIf', 'wi', 'Confirm', 'cf', 'UseTransaction', 'usetx'
    ),
    [System.StringComparer]::OrdinalIgnoreCase
)

# What makes a command name untrustworthy. After an alias or a function takes over echo or Write-Output, a
# literal given to it is not data. They are defined by these commands, by a function statement, and by the
# Alias and Function drives, which Set-Content, New-Item, and an assignment such as $function:name = ...
# all reach. While any of them is present, no literal is treated as data.
$definitionCommand = @('set-alias', 'new-alias', 'sal', 'nal', 'import-alias', 'ipal', 'new-psdrive', 'ndr', 'mount')
$definitionDrive = [regex]::new('(?i)(?<![\w-])(?:alias|function):', [System.Text.RegularExpressions.RegexOptions]::None, [TimeSpan]::FromSeconds(1))

# Commands and members that read or write a variable by its name, where matching the names in the text
# cannot follow the data; so can the Variable drive. While one is present, a literal that is assigned to a
# variable is scanned.
$variableByNameCommand = @('get-variable', 'gv', 'set-variable', 'sv', 'new-variable', 'nv', 'clear-variable', 'clv', 'remove-variable', 'rv')
$variableByNameMember = @('getvariable', 'setvariable', 'psvariable', 'sessionstate')
$variableDrive = [regex]::new('(?i)(?<![\w-])variable:', [System.Text.RegularExpressions.RegexOptions]::None, [TimeSpan]::FromSeconds(1))

# Commands that evaluate or start what they are given: while one is present, no
# literal is treated as data.
$launcherCommand = @(
    'invoke-expression', 'iex', 'invoke-command', 'icm', 'start-process', 'start',
    'saps', 'start-job', 'sajb', 'start-threadjob', 'invoke-item', 'ii',
    'invoke-wmimethod', 'iwmi', 'invoke-cimmethod'
)

# Members that build or run code from a string.
$indirectMember = @('create', 'addscript', 'addcommand', 'addargument', 'invokescript', 'expandstring', 'invoke')

# Programs that run code handed to them, and the argument that hands it over. An
# empty pattern means any use. pwsh and powershell have their own test, because
# they accept every unambiguous prefix of a parameter name.
$interpreterInlineCode = @{
    'cmd' = '^/[ckr]'
    'bash' = '^-[a-z]*c[a-z]*$'
    'sh' = '^-[a-z]*c[a-z]*$'
    'zsh' = '^-[a-z]*c[a-z]*$'
    'dash' = '^-[a-z]*c[a-z]*$'
    'fish' = '^-[a-z]*c[a-z]*$'
    'ksh' = '^-[a-z]*c[a-z]*$'
    'wsl' = ''
    'node' = '^(?:-e|--eval|-p|--print)$'
    'nodejs' = '^(?:-e|--eval|-p|--print)$'
    'deno' = '^(?:eval|-e|--eval|-p|--print)$'
    'bun' = '^(?:-e|--eval|-p|--print)$'
    'python' = '^-c$'
    'python3' = '^-c$'
    'py' = '^-c$'
    'ruby' = '^-e$'
    'perl' = '^-e$'
    'php' = '^-r$'
}
$interpreterName = @($interpreterInlineCode.Keys) + @('pwsh', 'powershell')

# The interpreters of a general-purpose language: inline code in one of them can loop in ways that no pattern
# of this guard reads, so it counts as a repetition (Test-StoredCode).
$programmingInterpreter = @('node', 'nodejs', 'deno', 'bun', 'python', 'python3', 'py', 'ruby', 'perl', 'php')

$powerShellInlineName = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($fullName in 'command', 'encodedcommand', 'commandwithargs') {
    for ($length = 1; $length -le $fullName.Length; $length++) {
        $null = $powerShellInlineName.Add($fullName.Substring(0, $length))
    }
}
$null = $powerShellInlineName.Add('ec')
$null = $powerShellInlineName.Add('cwa')

# Set when a Start-Process call names git or gh with arguments that cannot be read.
$launchesGitIndirectly = $false

# Set when a command can run an operation more than once (see $repetitionSyntax).
$isRepetitive = $false

function Get-CommandBaseName {
    <#
        The lower-case leaf name of a command without its extension, so
        C:\Program Files\Git\cmd\git.exe, git.exe, and git read the same. Empty
        when the parser cannot name the command, as in & $name.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [CommandAst]$Command
    )

    $name = $Command.GetCommandName()
    if ([string]::IsNullOrEmpty($name)) {
        return ''
    }

    $leaf = $name -replace '^.*[\\/]', ''
    return ($leaf -replace '\.(?:exe|cmd|bat|com|ps1)$', '').ToLowerInvariant()
}

function Get-StaticString {
    <#
        The text of a bareword or a string with nothing in it to expand; $null for
        anything else, such as a variable or a sub-expression.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowNull()]
        [Ast]$Node
    )

    if ($Node -is [StringConstantExpressionAst]) {
        return $Node.Value
    }

    if ($Node -is [ExpandableStringExpressionAst] -and @($Node.NestedExpressions).Count -eq 0) {
        return $Node.Value
    }

    return $null
}

function Get-StaticStringList {
    <#
        The strings an argument holds, as one string or a comma list of strings;
        $null as soon as any part is not a known string.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter()]
        [AllowNull()]
        [Ast]$Node
    )

    $item = @($Node)
    if ($Node -is [ArrayLiteralAst]) {
        $item = @($Node.Elements)
    } elseif ($Node -is [ArrayExpressionAst]) {
        # @('a', 'b') holds one statement that holds one expression.
        $statement = @($Node.SubExpression.Statements)
        if ($statement.Count -ne 1 -or $statement[0] -isnot [PipelineAst]) {
            return $null
        }

        $element = @($statement[0].PipelineElements)
        if ($element.Count -ne 1 -or $element[0] -isnot [CommandExpressionAst]) {
            return $null
        }

        $expression = $element[0].Expression
        $item = if ($expression -is [ArrayLiteralAst]) { @($expression.Elements) } else { @($expression) }
    }

    $part = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $item) {
        $value = Get-StaticString -Node $entry
        if ($null -eq $value) {
            return $null
        }

        $part.Add($value)
    }

    return , $part.ToArray()
}

function Get-StartProcessRole {
    <#
        What the next element of a Start-Process call is, after a parameter name.
        Start-Process accepts any unambiguous prefix of a parameter name.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    if ('FilePath'.StartsWith($Name, [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'file'
    }

    if ('ArgumentList'.StartsWith($Name, [System.StringComparison]::OrdinalIgnoreCase) -or $Name -ieq 'Args') {
        return 'argument'
    }

    foreach ($switchName in 'Wait', 'PassThru', 'NoNewWindow', 'LoadUserProfile', 'UseNewEnvironment') {
        if ($switchName.StartsWith($Name, [System.StringComparison]::OrdinalIgnoreCase)) {
            return 'switch'
        }
    }

    return 'value'
}

function Get-LaunchedCommandLine {
    <#
        Reads a Start-Process call. When the program is git or gh, returns the
        command line it launches, so the patterns see git push in
        Start-Process git -ArgumentList push, and says when the arguments could not
        be read. When the program itself is not known, the arguments are offered to
        both.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [CommandAst]$Command
    )

    $result = [pscustomobject]@{ Line = [string[]]@(); Indirect = $false }
    $element = @($Command.CommandElements)
    $state = [pscustomobject]@{
        File = $null
        IsFileGiven = $false
        IsArgumentKnown = $true
        Argument = [System.Collections.Generic.List[string]]::new()
    }
    $positionalCount = 0
    $role = ''

    # A script block gets its own scope, so it changes the state object, not a variable.
    $bind = {
        param($State, $Role, $Node)

        switch ($Role) {
            'file' {
                $State.IsFileGiven = $true
                $State.File = Get-StaticString -Node $Node
            }
            'argument' {
                $list = Get-StaticStringList -Node $Node
                if ($null -eq $list) {
                    $State.IsArgumentKnown = $false
                } else {
                    foreach ($text in $list) {
                        $State.Argument.Add($text)
                    }
                }
            }
        }
    }

    for ($index = 1; $index -lt $element.Count; $index++) {
        $item = $element[$index]

        if ($item -is [CommandParameterAst]) {
            $parameterRole = Get-StartProcessRole -Name $item.ParameterName
            if ($null -ne $item.Argument) {
                $null = & $bind $state $parameterRole $item.Argument
                $role = ''
            } else {
                $role = if ($parameterRole -eq 'switch') { '' } else { $parameterRole }
            }

            continue
        }

        $boundRole = $role
        if ($boundRole -eq '') {
            $positionalCount++
            $boundRole = if ($positionalCount -eq 1) { 'file' } else { 'argument' }
        }

        $role = ''
        $null = & $bind $state $boundRole $item
    }

    if (-not $state.IsFileGiven) {
        return $result
    }

    $argumentLine = $state.Argument.ToArray() -join ' '
    if ($null -eq $state.File) {
        if ($state.IsArgumentKnown -and $state.Argument.Count -gt 0) {
            $result.Line = [string[]]@("git $argumentLine", "gh $argumentLine")
        }

        return $result
    }

    $program = (($state.File -replace '^.*[\\/]', '') -replace '\.exe$', '').ToLowerInvariant()
    if ($program -eq 'git' -or $program -eq 'gh') {
        if ($state.IsArgumentKnown) {
            $result.Line = [string[]]@("$program $argumentLine")
        } else {
            $result.Indirect = $true
        }
    }

    return $result
}

function Test-InlineCode {
    <#
        True when a command hands code to a program that runs it: pwsh or
        powershell with -Command or -EncodedCommand (or any prefix of either), or
        text on standard input; cmd /c; bash -c; node -e; and the like.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Base,

        [Parameter(Mandatory)]
        [CommandAst]$Command
    )

    $argument = @($Command.CommandElements | Select-Object -Skip 1)

    if ($Base -eq 'pwsh' -or $Base -eq 'powershell') {
        foreach ($item in $argument) {
            if ($item -is [CommandParameterAst]) {
                if ($script:powerShellInlineName.Contains($item.ParameterName)) {
                    return $true
                }

                continue
            }

            $text = $item.Extent.Text
            if ($text -eq '-') {
                return $true
            }

            if ($text -match '^[-/]([a-z]+)$' -and $script:powerShellInlineName.Contains($Matches[1])) {
                return $true
            }
        }

        return $false
    }

    if (-not $script:interpreterInlineCode.ContainsKey($Base)) {
        return $false
    }

    $pattern = [string]$script:interpreterInlineCode[$Base]
    if ($pattern -eq '') {
        return $true
    }

    foreach ($item in $argument) {
        if ($item.Extent.Text -match $pattern) {
            return $true
        }
    }

    return $false
}

function Get-InertCommandName {
    <#
        The name of the data-writing cmdlet a command is, in lower case, or an empty
        string when it is not one. The name counts as written: a path or an extension,
        as in .\echo.ps1 or C:\tools\write-output.cmd, names a program that only looks
        like a cmdlet. The module-qualified name of a standard module still counts.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [CommandAst]$Command
    )

    $name = $Command.GetCommandName()
    if ([string]::IsNullOrEmpty($name)) {
        return ''
    }

    $name = $name.ToLowerInvariant() -replace '^microsoft\.powershell\.(?:utility|management|host)\\', ''
    if ($script:inertCommandSet.Contains($name)) {
        return $name
    }

    return ''
}

function Test-InertCommand {
    <#
        True when a command is one of the data-writing cmdlets by its own name.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [CommandAst]$Command
    )

    return (-not [string]::IsNullOrEmpty((Get-InertCommandName -Command $Command)))
}

function Get-WriteParameterKind {
    <#
        What a parameter of a file-writing cmdlet takes: path for the parameters that name
        the file, switch for the ones that take nothing, value for the rest, and unknown for a
        name that is none of the cmdlets' parameters or aliases. PowerShell accepts any
        unambiguous prefix of a name or an alias, so a prefix counts: one that fits a path
        parameter and another is a path parameter, the careful side; one that fits parameters
        of different kinds is unknown.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $kind = $null
    if ($script:writerParameterKind.TryGetValue($Name, [ref]$kind)) {
        return $kind
    }

    $found = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($entry in $script:writerParameterKind.GetEnumerator()) {
        if ($entry.Key.StartsWith($Name, [System.StringComparison]::OrdinalIgnoreCase)) {
            $null = $found.Add($entry.Value)
        }
    }

    if ($found.Contains('path')) {
        return 'path'
    }

    if ($found.Count -eq 1) {
        return @($found)[0]
    }

    return 'unknown'
}

function Get-WriteTarget {
    <#
        The elements of a file-writing command that name the file: the argument of a path
        parameter, and the first argument that no parameter takes. A command whose
        arguments the text does not spell out, a splatted variable or a parameter that is
        none of the cmdlet's own, has no readable target: the result is empty.
    #>
    [CmdletBinding()]
    [OutputType([Ast[]])]
    param(
        [Parameter(Mandatory)]
        [CommandAst]$Command
    )

    $target = [System.Collections.Generic.List[Ast]]::new()
    $element = @($Command.CommandElements)
    $role = ''
    $positional = 0

    for ($index = 1; $index -lt $element.Count; $index++) {
        $item = $element[$index]

        if ($item -is [VariableExpressionAst] -and $item.Splatted) {
            return , [Ast[]]@()
        }

        if ($item -is [CommandParameterAst]) {
            $kind = Get-WriteParameterKind -Name $item.ParameterName
            if ($kind -eq 'unknown') {
                return , [Ast[]]@()
            }

            if ($null -ne $item.Argument) {
                if ($kind -eq 'path') {
                    $target.Add($item.Argument)
                }

                $role = ''
            } elseif ($kind -eq 'switch') {
                $role = ''
            } else {
                $role = $kind
            }

            continue
        }

        if ($role -eq 'path') {
            $target.Add($item)
            $role = ''
            continue
        }

        if ($role -eq 'value') {
            $role = ''
            continue
        }

        $positional++
        if ($positional -eq 1) {
            $target.Add($item)
        }
    }

    return , $target.ToArray()
}

function ConvertTo-ComparablePath {
    <#
        The path as the file system names the file, so that a rule that lists a file also sees its other
        spellings: Windows drops the dots and spaces that end a name, and file::$DATA and file:stream are
        the file itself. A drive qualifier is removed first, because it is not a stream: C:.git\hooks names
        .git\hooks on the current directory of drive C (reviews of 2026-10-13, fifth pass F2, sixth pass N1).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Path
    )

    $Path = $Path -replace '^\s*[A-Za-z]:', ''
    $name = foreach ($segment in ($Path -split '[\\/]')) {
        if ($segment -ceq '.' -or $segment -ceq '..') {
            $segment
            continue
        }

        $colon = $segment.IndexOf(':')
        if ($colon -ge 0) {
            $segment = $segment.Substring(0, $colon)
        }

        $segment.TrimEnd('.', ' ')
    }

    return (@($name) -join '/')
}

function Test-SafePath {
    <#
        True when an expression is certainly a path in the file system and not a drive or
        a provider: a literal that names no drive or provider (a list of them too), a
        parenthesis around such an expression, or a variable whose every assignment in the
        text is one. A path that is computed, as in ('func' + 'tion:x'), -join, or -f, that
        starts with a variable, or that comes from a command such as Join-Path is unknown,
        and an unknown path is not a safe one: it may name the Function drive, where
        Set-Content defines a function.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [Ast]$Node,

        [Parameter(Mandatory)]
        [hashtable]$Cache,

        [Parameter()]
        [int]$Depth = 0
    )

    if ($null -eq $Node -or $Depth -gt 4) {
        return $false
    }

    $literal = Get-StaticStringList -Node $Node
    if ($null -ne $literal) {
        foreach ($path in $literal) {
            if ([string]::IsNullOrWhiteSpace($path) -or $script:providerPath.IsMatch($path) -or $script:selfExecutingPath.IsMatch($path)) {
                return $false
            }

            # A wildcard or a short name stands for files the text does not name, and the rules list a file by the
            # name the file system resolves a spelling to.
            if ($script:unreadablePathName.IsMatch($path) -or $script:selfExecutingPath.IsMatch((ConvertTo-ComparablePath -Path $path))) {
                return $false
            }
        }

        return ($literal.Count -gt 0)
    }

    if ($Node -is [ParenExpressionAst]) {
        $pipeline = $Node.Pipeline -as [PipelineAst]
        if ($null -eq $pipeline -or @($pipeline.PipelineElements).Count -ne 1 -or $pipeline.PipelineElements[0] -isnot [CommandExpressionAst]) {
            return $false
        }

        return (Test-SafePath -Node $pipeline.PipelineElements[0].Expression -Cache $Cache -Depth ($Depth + 1))
    }

    if ($Node -isnot [VariableExpressionAst] -or -not $Node.VariablePath.IsVariable -or $Cache['dynamicVariable']) {
        return $false
    }

    $assignmentIndex = $Cache['assignment']
    if ($null -eq $assignmentIndex) {
        return $false
    }

    $variableKey = Get-VariableKey -VariablePath $Node.VariablePath
    if ($null -ne $Cache['taint'] -and $Cache['taint'].Contains($variableKey)) {
        return $false
    }

    $assignment = $assignmentIndex[$variableKey]
    if ($null -eq $assignment) {
        return $false
    }

    # Every write that names the variable asks again, and each ask walks every assignment: 32 KB of one
    # assignment and one write, repeated, took 21 seconds (review of 2026-10-13, third pass, H3). The answer
    # belongs to the variable, so it is worked out once. A variable that depends on itself is not safe.
    $memoKey = 'safe:' + $variableKey
    if ($Cache.ContainsKey($memoKey)) {
        return [bool]$Cache[$memoKey]
    }

    $Cache[$memoKey] = $false
    foreach ($item in $assignment) {
        if ($item.Operator -ne [TokenKind]::Equals -or $item.Right -isnot [CommandExpressionAst]) {
            return $false
        }

        if (-not (Test-SafePath -Node $item.Right.Expression -Cache $Cache -Depth ($Depth + 1))) {
            return $false
        }
    }

    $Cache[$memoKey] = $true
    return $true
}

function Test-SafeWriteTarget {
    <#
        True when every file a file-writing command names is a safe path (Test-SafePath),
        and no command of the text moved the location to somewhere a relative path would
        mean another drive. A command that names no file at all is not safe either.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [CommandAst]$Command,

        [Parameter(Mandatory)]
        [hashtable]$Cache
    )

    if ($Cache['dynamicLocation']) {
        return $false
    }

    # Get-WriteTarget returns its array as one object, so it is taken as it is: @() would wrap it again.
    $target = Get-WriteTarget -Command $Command
    if ($target.Count -eq 0) {
        return $false
    }

    foreach ($node in $target) {
        if (-not (Test-SafePath -Node $node -Cache $Cache)) {
            return $false
        }
    }

    return $true
}

function Test-VariableParameter {
    <#
        True for a parameter that stores output in a variable named by its argument:
        -OutVariable, -ErrorVariable, -PipelineVariable, -Variable, their aliases, and
        any prefix of them, a single letter included: -v binds -Variable of Tee-Object
        (review of 2026-10-13, third pass, H2).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($script:commonNonVariableParameter.Contains($Name)) {
        return $false
    }

    foreach ($candidate in $script:variableParameter) {
        if ($candidate.StartsWith($Name, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Test-GitProgram {
    <#
        True when a command is git itself, as git, git.exe, or the path of one of them.
        A script or a wrapper that is merely named git, such as .\git.ps1 or git.cmd, is
        another program.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [CommandAst]$Command
    )

    $name = $Command.GetCommandName()
    if ([string]::IsNullOrEmpty($name)) {
        return $false
    }

    $leaf = ($name -replace '^.*[\\/]', '').ToLowerInvariant()
    return ($leaf -ceq 'git' -or $leaf -ceq 'git.exe')
}

function Get-VariableKey {
    <#
        What names a variable: its path without a scope, in lower case, so $x, $script:X,
        and $using:x are one variable. A drive-qualified path such as env:name keeps its drive.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.VariablePath]$VariablePath
    )

    $name = $VariablePath.UserPath -replace '^(?i:global|script|local|private|using):', ''
    return $name.ToLowerInvariant()
}

function Get-InertRange {
    <#
        The source ranges of one command whose text is data. Element holds the
        arguments of a data-writing cmdlet and the message of git commit or
        git tag; Direct holds the value of a --message= token, which is one token
        with the option in front of it, and the expressions inside it that still run.
        A cmdlet that writes to a path holds no range unless the path is known to be
        a file (Test-SafeWriteTarget).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [CommandAst]$Command,

        [Parameter()]
        [hashtable]$Cache = @{}
    )

    $result = [pscustomobject]@{
        Element = [System.Collections.Generic.List[int[]]]::new()
        Direct = [System.Collections.Generic.List[pscustomobject]]::new()
    }

    $element = @($Command.CommandElements)

    $inertName = Get-InertCommandName -Command $Command
    if ($inertName -ne '') {
        # A parameter that stores output in a variable carries the text out of the cmdlet to wherever the
        # variable goes next: Write-Output 'git push' -OutVariable cmd; schtasks /tr $cmd.
        foreach ($parameterElement in $element) {
            if ($parameterElement -is [CommandParameterAst] -and (Test-VariableParameter -Name $parameterElement.ParameterName)) {
                return $result
            }
        }

        if ($script:fileWriterCommand -contains $inertName -and -not (Test-SafeWriteTarget -Command $Command -Cache $Cache)) {
            return $result
        }

        for ($index = 1; $index -lt $element.Count; $index++) {
            $item = $element[$index]
            if ($item -is [CommandParameterAst]) {
                if ($null -ne $item.Argument) {
                    $result.Element.Add([int[]]@($item.Argument.Extent.StartOffset, $item.Argument.Extent.EndOffset))
                }
            } else {
                $result.Element.Add([int[]]@($item.Extent.StartOffset, $item.Extent.EndOffset))
            }
        }

        return $result
    }

    if (-not (Test-GitProgram -Command $Command)) {
        return $result
    }

    # The subcommand is the first word that is not an option or an option's value.
    $subcommandIndex = -1
    for ($index = 1; $index -lt $element.Count; $index++) {
        $text = $element[$index].Extent.Text
        if ($text.StartsWith('-')) {
            if ($text -cin @('-C', '-c', '--git-dir', '--work-tree', '--namespace', '--super-prefix', '--config-env')) {
                $index++
            }

            continue
        }

        $subcommandIndex = $index
        break
    }

    if ($subcommandIndex -lt 0) {
        return $result
    }

    $subcommand = Get-StaticString -Node $element[$subcommandIndex]
    if ($subcommand -cne 'commit' -and $subcommand -cne 'tag') {
        return $result
    }

    for ($index = $subcommandIndex + 1; $index -lt $element.Count; $index++) {
        $text = $element[$index].Extent.Text
        if ($text -cmatch '^-[A-Za-z]*m$' -or $text -ceq '--message') {
            if ($index + 1 -lt $element.Count) {
                $next = $element[$index + 1]
                $result.Element.Add([int[]]@($next.Extent.StartOffset, $next.Extent.EndOffset))
                $index++
            }
        } elseif ($text -cmatch '^--message=') {
            $start = $element[$index].Extent.StartOffset + $text.IndexOf('=') + 1
            # What is expanded inside the value runs, so it stays in the text the patterns scan.
            $keep = @()
            if ($element[$index] -is [ExpandableStringExpressionAst]) {
                $keep = @($element[$index].NestedExpressions | ForEach-Object -Process { , [int[]]@($_.Extent.StartOffset, $_.Extent.EndOffset) })
            }

            $result.Direct.Add([pscustomobject]@{ First = $start; Last = $element[$index].Extent.EndOffset; Keep = $keep })
        }
    }

    return $result
}

function Test-TerminalOutput {
    <#
        True when the output of a pipeline goes nowhere that could run it: the pipeline is
        a statement of the command text itself, perhaps inside an if, a loop, or a try, and
        not part of an assignment, a parenthesis, a sub-expression, an argument, or a script
        block that is called later. Write-Output 'git push' as a statement prints text; in
        $x = Write-Output 'git push' or schtasks /tr (Write-Output 'git push') the text goes
        on to run. PipelineChainAst exists only in PowerShell 7, so it is matched by name.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [PipelineAst]$Pipeline
    )

    $node = $Pipeline.Parent
    while ($null -ne $node) {
        if ($node -is [NamedBlockAst]) {
            return ($node.Parent -is [ScriptBlockAst] -and $null -eq $node.Parent.Parent)
        }

        if ($node -is [StatementBlockAst] -or $node -is [IfStatementAst] -or $node -is [ForEachStatementAst] -or
            $node -is [ForStatementAst] -or $node -is [WhileStatementAst] -or $node -is [DoWhileStatementAst] -or
            $node -is [DoUntilStatementAst] -or $node -is [TryStatementAst] -or $node -is [CatchClauseAst] -or
            $node -is [SwitchStatementAst] -or $node.GetType().Name -ceq 'PipelineChainAst') {
            $node = $node.Parent
            continue
        }

        return $false
    }

    return $false
}

function Test-InertTail {
    <#
        True when a command that follows another in a pipeline only prints, searches, or writes
        the text it receives: it is one of the inert cmdlets, it stores no output in a variable
        (-OutVariable and the like carry the text to wherever the variable goes next), and a file
        writer names a file that is known.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [Ast]$Node,

        [Parameter(Mandatory)]
        [hashtable]$Cache
    )

    if ($Node -isnot [CommandAst] -or -not (Test-InertCommand -Command $Node)) {
        return $false
    }

    foreach ($element in @($Node.CommandElements)) {
        if ($element -is [CommandParameterAst] -and (Test-VariableParameter -Name $element.ParameterName)) {
            return $false
        }
    }

    if ($script:fileWriterCommand -contains (Get-InertCommandName -Command $Node) -and -not (Test-SafeWriteTarget -Command $Node -Cache $Cache)) {
        return $false
    }

    return $true
}

function Test-InertSink {
    <#
        True when nothing after the command can run the text it was given: nothing
        later in its pipeline, and nothing that takes the pipeline's output.
        Write-Output 'git push' | bash is a push, Write-Output 'x' | Set-Content f is
        not, and $x = Write-Output 'git push' hands the text to whatever uses $x. A
        Set-Content, Add-Content, Out-File, or New-Item after it counts only when it
        writes to a path that is known to be a file.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [CommandAst]$Command,

        [Parameter()]
        [hashtable]$Cache = @{}
    )

    $pipeline = $Command.Parent -as [PipelineAst]
    if ($null -eq $pipeline) {
        return $false
    }

    $isAfter = $false
    foreach ($item in @($pipeline.PipelineElements)) {
        if ([object]::ReferenceEquals($item, $Command)) {
            $isAfter = $true
            continue
        }

        if (-not $isAfter) {
            continue
        }

        if (-not (Test-InertTail -Node $item -Cache $Cache)) {
            return $false
        }
    }

    return ($isAfter -and (Test-TerminalOutput -Pipeline $pipeline))
}

function Test-InertFileWriter {
    <#
        True when a node is an argument of [System.IO.File]::WriteAllText and the other
        static writers of text: the text goes to a file, not to a command. The first
        argument is the file, and it must be a path that is safe to write data to
        (Test-SafePath): what goes into a file that runs by itself is code, and a path
        that the text does not spell out is no safer (review of 2026-10-13, fifth
        pass, F1).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [InvokeMemberExpressionAst]$Member,

        [Parameter(Mandatory)]
        [Ast]$Node,

        [Parameter(Mandatory)]
        [hashtable]$Cache
    )

    if (-not $Member.Static -or $Member.Expression -isnot [TypeExpressionAst] -or $Member.Member -isnot [StringConstantExpressionAst]) {
        return $false
    }

    if ($script:inertFileMember -cnotcontains ([string]$Member.Member.Value).ToLowerInvariant()) {
        return $false
    }

    $typeName = $Member.Expression.TypeName.FullName.ToLowerInvariant()
    if ($typeName -cne 'system.io.file' -and $typeName -cne 'io.file' -and $typeName -cne 'file') {
        return $false
    }

    $argument = @($Member.Arguments)
    if ($argument.Count -eq 0 -or $Cache['dynamicLocation'] -or -not (Test-SafePath -Node $argument[0] -Cache $Cache)) {
        return $false
    }

    foreach ($item in $argument) {
        if ($Node.Extent.StartOffset -ge $item.Extent.StartOffset -and $Node.Extent.EndOffset -le $item.Extent.EndOffset) {
            return $true
        }
    }

    return $false
}

function Test-InertAssignment {
    <#
        True when the literal on the right of an assignment is data: it goes to a plain
        variable, and every use of that variable in the text is itself inert, an argument
        that Get-InertRange names, a pipeline that ends in data-writing cmdlets, or a text
        writer. A variable that reaches anything else, such as schtasks $x, a member call,
        an expression, or another variable, may be run as text, so its literals stay
        scanned. So does a variable that is read by name or an assignment to a drive.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AssignmentStatementAst]$Assignment,

        [Parameter(Mandatory)]
        [hashtable]$Cache
    )

    $target = $Assignment.Left
    if ($target -is [ConvertExpressionAst]) {
        $target = $target.Child
    }

    # $function:name and $env:name are drives, not variables: IsVariable is false for them.
    if ($target -isnot [VariableExpressionAst] -or -not $target.VariablePath.IsVariable -or $Cache['dynamicVariable']) {
        return $false
    }

    $key = Get-VariableKey -VariablePath $target.VariablePath
    $cacheKey = 'variable:' + $key
    if ($Cache.ContainsKey($cacheKey)) {
        return [bool]$Cache[$cacheKey]
    }

    $result = $true
    foreach ($use in @($Cache['use'][$key])) {
        if ($Cache['target'].Contains($use)) {
            continue
        }

        if (-not (Test-InertString -String $use -Cache $Cache)) {
            $result = $false
            break
        }
    }

    $Cache[$cacheKey] = $result
    return $result
}

function Test-InertString {
    <#
        True when a string literal, or a use of a variable, is data: the right side of an
        assignment to a variable whose every use is inert, the source of a pipeline that
        ends in data-writing cmdlets, an argument that Get-InertRange names, or an
        argument of a text writer such as File.WriteAllText. Anything else, inside a
        sub-expression, a script block, or another member call, is left to the patterns.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [Ast]$String,

        [Parameter(Mandatory)]
        [hashtable]$Cache
    )

    $parent = $String.Parent
    while ($null -ne $parent) {
        if ($parent -is [AssignmentStatementAst]) {
            $right = $parent.Right
            $isRight = $String.Extent.StartOffset -ge $right.Extent.StartOffset -and $String.Extent.EndOffset -le $right.Extent.EndOffset
            if (-not $isRight) {
                return $false
            }

            # A variable read on the right copies its data somewhere this check does not follow.
            if ($String -is [VariableExpressionAst]) {
                return $false
            }

            return (Test-InertAssignment -Assignment $parent -Cache $Cache)
        }

        if ($parent -is [CommandAst]) {
            $key = '{0}:{1}' -f $parent.Extent.StartOffset, $parent.Extent.EndOffset
            if (-not $Cache.ContainsKey($key)) {
                $Cache[$key] = Get-InertRange -Command $parent -Cache $Cache
            }

            foreach ($range in $Cache[$key].Element) {
                if ($String.Extent.StartOffset -ge $range[0] -and $String.Extent.EndOffset -le $range[1]) {
                    return (Test-InertSink -Command $parent -Cache $Cache)
                }
            }

            return $false
        }

        if ($parent -is [CommandExpressionAst] -and $parent.Parent -is [PipelineAst]) {
            $sequence = @($parent.Parent.PipelineElements)
            if ($sequence.Count -gt 1 -and [object]::ReferenceEquals($sequence[0], $parent)) {
                for ($position = 1; $position -lt $sequence.Count; $position++) {
                    if (-not (Test-InertTail -Node $sequence[$position] -Cache $Cache)) {
                        return $false
                    }
                }

                return (Test-TerminalOutput -Pipeline $parent.Parent)
            }
        }

        # InvokeMemberExpressionAst is a MemberExpressionAst, so a text writer is judged first.
        if ($parent -is [InvokeMemberExpressionAst] -and (Test-InertFileWriter -Member $parent -Node $String -Cache $Cache)) {
            return $true
        }

        if ($parent -is [SubExpressionAst] -or $parent -is [ScriptBlockExpressionAst] -or $parent -is [MemberExpressionAst]) {
            return $false
        }

        $parent = $parent.Parent
    }

    return $false
}

function Hide-Text {
    <#
        Blanks the characters from First up to Last in a character buffer, keeping
        line breaks and the ranges listed in Keep, and returns how many it blanked.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [char[]]$Buffer,

        [Parameter(Mandatory)]
        [int]$First,

        [Parameter(Mandatory)]
        [int]$Last,

        [Parameter()]
        [AllowEmptyCollection()]
        [int[][]]$Keep = @()
    )

    $blanked = 0
    $limit = [Math]::Min($Last, $Buffer.Length)
    for ($position = [Math]::Max($First, 0); $position -lt $limit; $position++) {
        $isKept = $false
        foreach ($range in $Keep) {
            if ($position -ge $range[0] -and $position -lt $range[1]) {
                $isKept = $true
                break
            }
        }

        $value = $Buffer[$position]
        if (-not $isKept -and $value -ne "`r" -and $value -ne "`n" -and $value -ne ' ') {
            $Buffer[$position] = ' '
            $blanked++
        }
    }

    return $blanked
}

function Test-LiteralArgument {
    <#
        True when an argument is spelled out in the text: a string or a number, a string with
        nothing in it to expand, $true, $false, $null, or a list of them. A variable, a
        sub-expression, or a call is not: what it holds is decided somewhere else.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [AllowNull()]
        [Ast]$Node
    )

    if ($Node -is [ConstantExpressionAst]) {
        return $true
    }

    if ($Node -is [VariableExpressionAst]) {
        $userPath = [string]$Node.VariablePath.UserPath
        return ([string]::Equals($userPath, 'true', [System.StringComparison]::OrdinalIgnoreCase) -or
            [string]::Equals($userPath, 'false', [System.StringComparison]::OrdinalIgnoreCase) -or
            [string]::Equals($userPath, 'null', [System.StringComparison]::OrdinalIgnoreCase))
    }

    if ($Node -is [ArrayLiteralAst]) {
        foreach ($element in $Node.Elements) {
            if (-not (Test-LiteralArgument -Node $element)) {
                return $false
            }
        }

        return $true
    }

    return ($null -ne (Get-StaticStringList -Node $Node))
}

function Test-StoredCode {
    <#
        True when a parsed text holds code that is written once and can run any number of times,
        however the syntax around it looks: a script block that is a value or an argument, as in
        Sort-Object { ... }, Register-ObjectEvent -Action { ... }, or & { ... }; a function, a class,
        or a trap; a command or a call operator that takes its code from something the text does not
        spell out, as in . $block or Invoke-Expression $text; a member that builds code; a cast to a
        script block; compiled code (Add-Type). A function written to the Function drive counts too, but
        Get-CommandTextView sees that one, with the other drive writes. The guard counts the operations
        it reads, not the times they run, so for a text like this it cannot say how many there are
        (review of 2026-10-13, third pass, H5).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [Ast[]]$Node
    )

    foreach ($item in $Node) {
        if ($item -is [ScriptBlockExpressionAst] -or $item -is [FunctionDefinitionAst] -or
            $item -is [TypeDefinitionAst] -or $item -is [TrapStatementAst]) {
            return $true
        }

        if ($item -is [CommandAst]) {
            # & $name, . $block, and & (...) run code that is somewhere else.
            if ($null -eq $item.GetCommandName()) {
                return $true
            }

            $base = Get-CommandBaseName -Command $item

            # Add-Type compiles code that its type then runs, as often as something calls it.
            if ($base -eq 'add-type') {
                return $true
            }

            if ($script:launcherCommand -contains $base -or (Test-InlineCode -Base $base -Command $item)) {
                # Code in a language this guard does not read can loop in ways it cannot see.
                if ($script:programmingInterpreter -contains $base -and (Test-InlineCode -Base $base -Command $item)) {
                    return $true
                }

                foreach ($element in @($item.CommandElements | Select-Object -Skip 1)) {
                    $argument = if ($element -is [CommandParameterAst]) { $element.Argument } else { $element }
                    if ($null -ne $argument -and -not (Test-LiteralArgument -Node $argument)) {
                        return $true
                    }
                }
            }

            continue
        }

        if ($item -is [PipelineAst]) {
            $sequence = @($item.PipelineElements)
            for ($position = 1; $position -lt $sequence.Count; $position++) {
                if ($sequence[$position] -isnot [CommandAst]) {
                    continue
                }

                $target = Get-CommandBaseName -Command $sequence[$position]
                if ($script:interpreterName -contains $target -or $script:launcherCommand -contains $target) {
                    $source = $sequence[0]
                    if ($source -isnot [CommandExpressionAst] -or -not (Test-LiteralArgument -Node $source.Expression)) {
                        return $true
                    }
                }
            }

            continue
        }

        if ($item -is [InvokeMemberExpressionAst]) {
            if ($item.Member -isnot [StringConstantExpressionAst] -or $script:indirectMember -contains ([string]$item.Member.Value).ToLowerInvariant()) {
                return $true
            }

            continue
        }

        if ($item -is [ConvertExpressionAst] -and $item.Type.TypeName.FullName -match '(?i)(?:^|\.)(?:scriptblock|powershell)$') {
            return $true
        }

        # A DSC configuration is a function in all but name; its type exists in both engines, but a name match is cheap.
        if ($item.GetType().Name -ceq 'ConfigurationDefinitionAst') {
            return $true
        }
    }

    return $false
}

function Skip-Masking {
    <#
        The analysis of a command text used up its share of the decision time. The clock cannot wait: a hook
        that outlasts its timeout is allowed by the Copilot SDK host (review of 2026-10-13, third pass, H3). The text
        is then scanned as written, which finds every operation in it, and the walk reports that it did not read
        the payload completely, so no Remote grant can lift the block.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$View,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    $script:isWalkComplete = $false
    if ([string]::IsNullOrEmpty($script:walkStopReason)) {
        $script:walkStopReason = 'takes too long to analyze'
    }

    $View.Text = $Text
    $View.IsRepetitive = $true
    return $View
}

function Get-CommandTextView {
    <#
        Reads one command string the way PowerShell does and returns the text the
        patterns should scan, plus what the parse showed about git and gh launched
        through Start-Process.

        The text comes back as written unless it parses without error and holds no
        indirect execution. Then each literal that is data is blanked in place:
        what Test-InertString accepts, except a string that is not single-quoted
        and holds a backtick, which a POSIX shell reads as a command substitution
        (a single-quoted string is data to every shell). Blanked characters become
        spaces and line breaks stay, so the patterns see the same lines. A literal
        with $() or a variable in it keeps those expressions.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    $view = [pscustomobject]@{ Text = $Text; ExtraLine = [string[]]@(); LaunchesIndirectly = $false; IsRepetitive = $false }

    if ($Text.Length -eq 0) {
        return $view
    }

    # Text that is not read as PowerShell is tested for repetition as written.
    if ($Text.Length -gt $script:maximumMaskLength) {
        $view.IsRepetitive = Test-Repetition -Text $Text -Unparsed
        return $view
    }

    # Every pattern needs a git or gh word, so a text without one needs no parse.
    if ($Text.IndexOf('git', [System.StringComparison]::OrdinalIgnoreCase) -lt 0 -and
        $Text.IndexOf('gh', [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
        return $view
    }

    $tokens = $null
    $parseError = $null
    try {
        $root = [Parser]::ParseInput($Text, [ref]$tokens, [ref]$parseError)
    } catch {
        $view.IsRepetitive = Test-Repetition -Text $Text -Unparsed
        return $view
    }

    # Windows PowerShell does not know && and ||, so it rejects such text and the
    # text is scanned as written.
    if (@($parseError).Count -gt 0) {
        $view.IsRepetitive = Test-Repetition -Text $Text -Unparsed
        return $view
    }

    $node = @($root.FindAll({ $true }, $true))
    if ($node.Count -gt $script:maximumMaskNodeCount) {
        $view.IsRepetitive = Test-Repetition -Text $Text -Unparsed
        return $view
    }

    $command = @($node | Where-Object -FilterScript { $_ -is [CommandAst] })
    $stringNode = @($node | Where-Object -FilterScript { $_ -is [StringConstantExpressionAst] -or $_ -is [ExpandableStringExpressionAst] })
    $storesCode = Test-StoredCode -Node $node
    $namesRepeater = $false
    $extra = [System.Collections.Generic.List[string]]::new()
    $isIndirect = $false
    $hasDynamicVariable = $false
    $hasDynamicLocation = $false
    $pushCount = 0
    $popCount = 0

    foreach ($item in $command) {
        $name = $item.GetCommandName()
        if ($null -eq $name) {
            # & { ... } runs a block this parse already holds; & $name does not.
            if (@($item.CommandElements)[0] -isnot [ScriptBlockExpressionAst]) {
                $isIndirect = $true
            }

            continue
        }

        $base = Get-CommandBaseName -Command $item
        if ($script:repeaterCommand.IsMatch($base)) {
            $namesRepeater = $true
        }

        if ($base -eq 'start-process' -or $base -eq 'start' -or $base -eq 'saps') {
            $launch = Get-LaunchedCommandLine -Command $item
            foreach ($line in $launch.Line) {
                $extra.Add($line)
            }

            if ($launch.Indirect) {
                $view.LaunchesIndirectly = $true
            }
        }

        if ($script:launcherCommand -contains $base -or (Test-InlineCode -Base $base -Command $item)) {
            $isIndirect = $true
        }

        # An alias can make echo or Write-Output run anything, so no name is trusted after one is defined.
        if ($script:definitionCommand -contains $base) {
            $isIndirect = $true
        }

        if ($script:variableByNameCommand -contains $base) {
            $hasDynamicVariable = $true
        }

        # After a move of the location to a place the text does not spell out, a relative path may mean a drive.
        # A parameter written with a colon carries its destination, as in Set-Location -Path:(...), and - and +
        # move through the location history.
        if ($script:locationCommand -contains $base) {
            foreach ($argument in @($item.CommandElements | Select-Object -Skip 1)) {
                if ($argument -is [CommandParameterAst]) {
                    if ($null -eq $argument.Argument) {
                        continue
                    }

                    $argument = $argument.Argument
                }

                $destination = Get-StaticString -Node $argument
                if ($null -eq $destination -or $destination -ceq '-' -or $destination -ceq '+' -or $script:providerPath.IsMatch($destination)) {
                    $hasDynamicLocation = $true
                }
            }
        }

        if ($script:locationPushCommand -contains $base) {
            $pushCount++
        }

        if ($script:locationPopCommand -contains $base) {
            $popCount++
        }
    }

    if ($popCount -gt $pushCount) {
        $hasDynamicLocation = $true
    }

    # A parameter such as -OutVariable replaces a variable that the text assigned a literal.
    foreach ($parameter in @($node | Where-Object -FilterScript { $_ -is [CommandParameterAst] })) {
        if (Test-VariableParameter -Name $parameter.ParameterName) {
            $hasDynamicVariable = $true
        }
    }

    foreach ($pipeline in @($node | Where-Object -FilterScript { $_ -is [PipelineAst] })) {
        $sequence = @($pipeline.PipelineElements)
        for ($position = 1; $position -lt $sequence.Count; $position++) {
            if ($sequence[$position] -is [CommandAst]) {
                $target = Get-CommandBaseName -Command $sequence[$position]
                if ($script:interpreterName -contains $target -or $script:launcherCommand -contains $target) {
                    $isIndirect = $true
                }
            }
        }
    }

    foreach ($member in @($node | Where-Object -FilterScript { $_ -is [InvokeMemberExpressionAst] })) {
        $memberName = $null
        if ($member.Member -is [StringConstantExpressionAst]) {
            $memberName = ([string]$member.Member.Value).ToLowerInvariant()
        }

        if ($null -eq $memberName -or $script:indirectMember -contains $memberName) {
            $isIndirect = $true
        }
    }

    # A member that reads or writes a variable by name; a property such as .SessionState counts too, and it
    # can also move the location.
    foreach ($member in @($node | Where-Object -FilterScript { $_ -is [MemberExpressionAst] })) {
        if ($member.Member -isnot [StringConstantExpressionAst] -or $script:variableByNameMember -contains ([string]$member.Member.Value).ToLowerInvariant()) {
            $hasDynamicVariable = $true
            $hasDynamicLocation = $true
        }
    }

    foreach ($convert in @($node | Where-Object -FilterScript { $_ -is [ConvertExpressionAst] })) {
        if ($convert.Type.TypeName.FullName -match '(?i)(?:^|\.)(?:scriptblock|powershell)$') {
            $isIndirect = $true
        }

        # [ref]$x lets a method assign to $x.
        if ($convert.Type.TypeName.FullName -ieq 'ref') {
            $hasDynamicVariable = $true
        }
    }

    # A function named like an inert command takes that name over, as an alias does.
    foreach ($definition in @($node | Where-Object -FilterScript { $_ -is [FunctionDefinitionAst] })) {
        $functionName = ($definition.Name -replace '^(?i:global|script|local|private):', '').ToLowerInvariant()
        if ($script:inertCommandSet.Contains($functionName)) {
            $isIndirect = $true
        }
    }

    # The Alias and Function drives define commands and the Variable drive reads variables, however the
    # path is reached: Set-Item function:echo, New-Item -Path function:x, $function:x = .... Backticks are
    # dropped first, and the value of each string is read too, so fun`ction: and fun''ction: do not hide it.
    $plainText = $Text.Replace('`', '')
    if ($script:definitionDrive.IsMatch($plainText)) {
        $isIndirect = $true
        $storesCode = $true
    }

    if ($script:variableDrive.IsMatch($plainText)) {
        $hasDynamicVariable = $true
    }

    foreach ($string in $stringNode) {
        $stringValue = [string]$string.Value
        if ($script:definitionDrive.IsMatch($stringValue)) {
            $isIndirect = $true
            $storesCode = $true
        }

        if ($script:variableDrive.IsMatch($stringValue)) {
            $hasDynamicVariable = $true
        }
    }

    $view.ExtraLine = $extra.ToArray()
    if ($isIndirect) {
        $view.IsRepetitive = $storesCode -or $namesRepeater -or (Test-Repetition -Text $Text)
        return $view
    }

    # Where each variable is used, which occurrences only receive a value, and what every assignment to
    # a plain variable is, so that a literal assigned to a variable is data only when every use of the
    # variable is (Test-InertAssignment) and a path variable is safe only when every assignment is
    # (Test-SafePath). A variable that a loop, a parameter, or a multiple assignment binds is tainted: its
    # value is not what the assignments say.
    $variableUse = @{}
    $variableAssignment = @{}
    $taint = [System.Collections.Generic.HashSet[string]]::new()
    $assignmentTarget = [System.Collections.Generic.HashSet[Ast]]::new()
    foreach ($assignment in @($node | Where-Object -FilterScript { $_ -is [AssignmentStatementAst] })) {
        $left = $assignment.Left
        if ($left -is [ConvertExpressionAst]) {
            $left = $left.Child
        }

        if ($left -is [VariableExpressionAst]) {
            $null = $assignmentTarget.Add($left)
            if ($left.VariablePath.IsVariable) {
                $assignedKey = Get-VariableKey -VariablePath $left.VariablePath
                if (-not $variableAssignment.ContainsKey($assignedKey)) {
                    $variableAssignment[$assignedKey] = [System.Collections.Generic.List[AssignmentStatementAst]]::new()
                }

                $variableAssignment[$assignedKey].Add($assignment)
            }
        } else {
            foreach ($bound in @($left.FindAll({ param($candidate) $candidate -is [VariableExpressionAst] }, $true))) {
                $null = $taint.Add((Get-VariableKey -VariablePath $bound.VariablePath))
            }
        }
    }

    foreach ($loop in @($node | Where-Object -FilterScript { $_ -is [ForEachStatementAst] })) {
        $null = $taint.Add((Get-VariableKey -VariablePath $loop.Variable.VariablePath))
    }

    foreach ($parameterDefinition in @($node | Where-Object -FilterScript { $_ -is [ParameterAst] })) {
        $null = $taint.Add((Get-VariableKey -VariablePath $parameterDefinition.Name.VariablePath))
    }

    foreach ($variable in @($node | Where-Object -FilterScript { $_ -is [VariableExpressionAst] })) {
        $variableKey = Get-VariableKey -VariablePath $variable.VariablePath
        if (-not $variableUse.ContainsKey($variableKey)) {
            $variableUse[$variableKey] = [System.Collections.Generic.List[Ast]]::new()
        }

        $variableUse[$variableKey].Add($variable)
    }

    $buffer = $Text.ToCharArray()
    $blankedCount = 0
    $cache = @{
        use = $variableUse
        target = $assignmentTarget
        assignment = $variableAssignment
        taint = $taint
        dynamicVariable = $hasDynamicVariable
        dynamicLocation = $hasDynamicLocation
    }

    foreach ($string in $stringNode) {
        if ($script:decisionClock.Elapsed -gt $script:walkTimeLimit) {
            return (Skip-Masking -View $view -Text $Text)
        }

        $start = $string.Extent.StartOffset
        $end = $string.Extent.EndOffset
        if ($end -le $start) {
            continue
        }

        # A backtick keeps a string scanned, because a POSIX shell reads it in double quotes as a command
        # substitution. A single-quoted string is data to PowerShell and to every POSIX shell.
        if ($Text.IndexOf([char]96, $start, $end - $start) -ge 0 -and
            $string.StringConstantType -ne [StringConstantType]::SingleQuoted -and
            $string.StringConstantType -ne [StringConstantType]::SingleQuotedHereString) {
            continue
        }

        if (-not (Test-InertString -String $string -Cache $cache)) {
            continue
        }

        $first = $start
        $last = $end
        if ($string.StringConstantType -ne [StringConstantType]::BareWord) {
            $first = $start + 1
            $last = $end - 1
        }

        $keep = @()
        if ($string -is [ExpandableStringExpressionAst]) {
            $keep = @($string.NestedExpressions | ForEach-Object -Process { , [int[]]@($_.Extent.StartOffset, $_.Extent.EndOffset) })
        }

        $blankedCount += Hide-Text -Buffer $buffer -First $first -Last $last -Keep $keep
    }

    foreach ($item in $command) {
        if ($script:decisionClock.Elapsed -gt $script:walkTimeLimit) {
            return (Skip-Masking -View $view -Text $Text)
        }

        if (-not (Test-GitProgram -Command $item)) {
            continue
        }

        foreach ($range in (Get-InertRange -Command $item -Cache $cache).Direct) {
            $value = $Text.Substring($range.First, $range.Last - $range.First)
            if (($value.IndexOf([char]96) -ge 0 -and -not $script:singleQuotedValue.IsMatch($value)) -or -not (Test-InertSink -Command $item -Cache $cache)) {
                continue
            }

            $blankedCount += Hide-Text -Buffer $buffer -First $range.First -Last $range.Last -Keep $range.Keep
        }
    }

    if ($blankedCount -gt 0) {
        $view.Text = [string]::new($buffer)
    }

    # A loop or a function inside a string is text, not code: a pull request body that quotes one must not
    # count as a repetition. So a candidate is tested again with the text of every quoted string literal
    # blanked, nested expressions kept. A bareword stays: ForEach-Object and xargs are barewords too.
    if (Test-Repetition -Text $view.Text) {
        $codeBuffer = $Text.ToCharArray()
        foreach ($string in $stringNode) {
            if ($string.StringConstantType -eq [StringConstantType]::BareWord) {
                continue
            }

            $first = $string.Extent.StartOffset + 1
            $last = $string.Extent.EndOffset - 1
            if ($last -le $first) {
                continue
            }

            $keep = @()
            if ($string -is [ExpandableStringExpressionAst]) {
                $keep = @($string.NestedExpressions | ForEach-Object -Process { , [int[]]@($_.Extent.StartOffset, $_.Extent.EndOffset) })
            }

            $null = Hide-Text -Buffer $codeBuffer -First $first -Last $last -Keep $keep
        }

        $view.IsRepetitive = Test-Repetition -Text ([string]::new($codeBuffer))
    }

    # Code that is stored rather than run where it is written is a repetition however the text reads, and so is a
    # command that the tree names as a repeat or watch wrapper.
    if ($storesCode -or $namesRepeater) {
        $view.IsRepetitive = $true
    }

    return $view
}

function Add-CommandPart {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$InputObject,

        [Parameter()]
        [int]$Depth = 0
    )

    if ($null -eq $InputObject -or $InputObject -is [string]) {
        return
    }

    if ($Depth -gt $script:maximumDepth) {
        $script:isWalkComplete = $false
        $script:walkStopReason = "is nested deeper than $script:maximumDepth levels"
        return
    }

    $executable = [System.Collections.Generic.List[string]]::new()
    $argument = [System.Collections.Generic.List[string]]::new()

    foreach ($property in $InputObject.PSObject.Properties) {
        $script:visitCount++
        if ($script:visitCount -gt $script:maximumVisitCount -or $script:decisionClock.Elapsed -gt $script:walkTimeLimit) {
            $script:isWalkComplete = $false
            $script:walkStopReason = 'has too many values to walk in time'
            break
        }

        $value = $property.Value

        if ($property.Name -in $script:commandField) {
            $text = if ($value -is [string]) { $value } elseif ($value -is [array]) { @($value) -join ' ' } else { $null }
            if (-not [string]::IsNullOrWhiteSpace($text)) {
                $isViewed = $false
                if ($value -is [string] -and $property.Name -in $script:executableField) {
                    try {
                        $view = Get-CommandTextView -Text $text
                        $text = $view.Text
                        if ($view.ExtraLine.Count -gt 0) {
                            $text = $text + "`n" + ($view.ExtraLine -join "`n")
                        }

                        if ($view.LaunchesIndirectly) {
                            $script:launchesGitIndirectly = $true
                        }

                        if ($view.IsRepetitive) {
                            $script:isRepetitive = $true
                        }

                        $isViewed = $true
                    } catch {
                        # A parse that fails for any reason leaves the text scanned as written.
                        Write-Verbose -Message 'The command text could not be read as PowerShell; it is scanned as written.'
                    }
                }

                # Text that was not read as PowerShell is tested for repetition as written.
                if (-not $isViewed -and -not $script:isRepetitive -and (Test-Repetition -Text $text -Unparsed)) {
                    $script:isRepetitive = $true
                }

                $script:commandPart.Add($text)
                if ($property.Name -in $script:executableField) {
                    $executable.Add($text)
                } else {
                    $argument.Add($text)
                }
            }
        }

        foreach ($child in @($value)) {
            # Plain values, such as a long file list, can never hold a command
            # field and cost little, so only the clock bounds them; only an
            # object, which costs a recursion, counts toward the cap.
            if ($script:decisionClock.Elapsed -gt $script:walkTimeLimit) {
                $script:isWalkComplete = $false
                $script:walkStopReason = 'has too many values to walk in time'
                break
            }

            if ($child -is [psobject] -and $child.PSObject.Properties.Name.Count -gt 0 -and $child -isnot [string] -and $child -isnot [ValueType]) {
                $script:visitCount++
                if ($script:visitCount -gt $script:maximumVisitCount) {
                    $script:isWalkComplete = $false
                    $script:walkStopReason = 'has too many values to walk in time'
                    break
                }

                Add-CommandPart -InputObject $child -Depth ($Depth + 1)
            }
        }
    }

    if ($executable.Count -gt 0 -and $argument.Count -gt 0) {
        $script:objectCommand.Add((([string[]]$executable.ToArray() + [string[]]$argument.ToArray()) -join ' '))
    }
}

function Join-CommandPart {
    <#
        Returns the texts to scan for the command-bearing values: all of them in
        document order, and each object's executables before its arguments,
        because a tool may write them in either order, for example with its
        keys sorted. Each per-object join ends in a semicolon on its own line,
        which no pattern crosses, so one entry's executable never pairs with
        another entry's arguments. The raw text scan, which errs toward
        blocking and cannot tell objects apart reliably, also passes the values
        by kind; they are then joined across the whole payload as well,
        executables first and in reverse. On a payload dense with git words,
        each extra text adds about half again to the scan.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Part,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$ObjectCommand,

        [Parameter()]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$ExecutablePart,

        [Parameter()]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$ArgumentPart
    )

    if ($Part.Count -gt 0) {
        $Part -join ' '
    }

    if ($ObjectCommand.Count -gt 0) {
        ($ObjectCommand -join ";`n") + ';'
    }

    if ($ExecutablePart.Count -gt 0 -and $ArgumentPart.Count -gt 0) {
        ([string[]]$ExecutablePart.ToArray() + [string[]]$ArgumentPart.ToArray()) -join ' '
        $reversed = $Part.ToArray()
        [array]::Reverse($reversed)
        $reversed -join ' '
    }
}

function Block-ToolCall {
    <#
        Ends the script with exit 2 and the reason. MarkerOperation lists the
        operations a Grant marker could authorize for the blocked command; when it
        is empty, no marker can lift the block and the reason says so. IsRepetitive
        says the command can run an operation more than once, so the marker asks for
        every use.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Because,

        [Parameter()]
        [string[]]$MarkerOperation = @(),

        [Parameter()]
        [switch]$IsRepetitive
    )

    $reason = "Blocked by Copilot Atelier: $Because, and the house rules forbid remote-mutating " +
        'or irreversible commands without explicit per-turn authorization from the user. '

    if ($MarkerOperation.Count -gt 0) {
        $marker = '[[allow-remote: ' + ($MarkerOperation -join ', ') + ']]'
        $reason += "If the user asked for it in this turn, they can authorize it by adding $marker to their next " +
            'message; only a message from the user records a Remote grant, so never write or change one yourself. '
        if ($IsRepetitive) {
            $reason += 'The command can run an operation more than once (a loop, a function, a script block, code that is stored ' +
                'or scheduled, or a call operator) and the guard cannot count ' +
                'how often it runs, so the marker asks for every use it can grant. To ask for a single use, run the ' +
                'operation as its own command, with none of those around it. '
        }

        if (@($MarkerOperation | Where-Object -FilterScript { $_ -cmatch '^git push --force(?: x\d+)?$' }).Count -gt 0) {
            $reason += 'git push --force also covers --delete, --mirror, --prune, --all, --tags, and a +ref or :ref refspec. '
        }

        $reason += 'Otherwise hand them the exact command as a fenced code block in your reply, to run in their own terminal. '
    } else {
        $reason += 'No Grant marker lifts this block. If the user asked for it in this turn, hand them the exact ' +
            'command as a fenced code block in your reply, to run in their own terminal. '
    }

    $reason += 'Do not rewrite the command to evade this check.'

    # VS Code reads the reason from standard error on exit 2 and ignores standard
    # output. The Copilot SDK host ignores standard error then and merges one JSON
    # object from standard output into the deny, but only a top-level one: for a
    # PascalCase event it drops an object that also carries hookSpecificOutput
    # and shows the model only that the hook exited with code 2.
    [Console]::Error.WriteLine($reason)
    $decision = [ordered]@{
        permissionDecision = 'deny'
        permissionDecisionReason = $reason
    }
    [Console]::Out.WriteLine(($decision | ConvertTo-Json -Compress))
    exit 2
}

function Get-GrantKey {
    <#
        The file name part for a session. Duplicated in Add-RemoteGrant.ps1. The payload
        supplies the id, so it becomes a path component only when it is already a safe
        file name in lower case (a file system may not tell SESSX from sessx); any other
        id becomes h- and its SHA-256, so two ids never share a grant
        file (review F6: ../../x and ....x used to collide, and so did ids that share their
        first 64 characters) and no character that could traverse a directory survives. An
        id with no usable character at all gets no key. -creplace, because -replace
        ignores case and so lets U+0130 and U+212A through the class.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$SessionId
    )

    $usable = $SessionId -creplace '[^A-Za-z0-9._-]', ''
    if ([string]::IsNullOrEmpty($usable)) {
        return ''
    }

    if ($SessionId -cmatch '\A[a-z0-9_-]{1,64}\z') {
        return $SessionId
    }

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($SessionId))
    } finally {
        $sha.Dispose()
    }

    return 'h-' + [BitConverter]::ToString($hash).Replace('-', '').ToLowerInvariant()
}

function Test-WholeNumber {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Value
    )

    return ($Value -is [int] -or $Value -is [long])
}

function Get-GrantOperation {
    <#
        The operations of a Remote grant and what is left of each, or $null when
        the grant is not valid now: wrong schema or session, an unreadable or
        implausible time, a lifetime beyond an hour, an operation the guard does
        not list, or a count outside 0 to 20.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text,

        [Parameter(Mandatory)]
        [string]$Key
    )

    try {
        $grant = $Text | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return $null
    }

    if ($grant -isnot [pscustomobject]) {
        return $null
    }

    foreach ($name in 'schema', 'sessionKey', 'issuedAt', 'expiresAt', 'operations') {
        if (-not $grant.PSObject.Properties[$name]) {
            return $null
        }
    }

    if (-not (Test-WholeNumber -Value $grant.schema) -or $grant.schema -ne 1) {
        return $null
    }

    if ($grant.sessionKey -isnot [string] -or $grant.sessionKey -cne $Key) {
        return $null
    }

    if (-not (Test-WholeNumber -Value $grant.issuedAt) -or -not (Test-WholeNumber -Value $grant.expiresAt)) {
        return $null
    }

    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $lifetime = [long]$grant.expiresAt - [long]$grant.issuedAt
    if ($lifetime -lt 1 -or $lifetime -gt $script:grantLifetimeLimitSecond) {
        return $null
    }

    if ($now -gt [long]$grant.expiresAt -or [long]$grant.issuedAt -gt ($now + $script:grantClockSkewSecond)) {
        return $null
    }

    if ($grant.operations -isnot [pscustomobject]) {
        return $null
    }

    $operation = [ordered]@{}
    foreach ($property in $grant.operations.PSObject.Properties) {
        if (-not $script:grantableOperationSet.Contains($property.Name)) {
            return $null
        }

        $count = $property.Value
        if (-not (Test-WholeNumber -Value $count) -or $count -lt 0 -or $count -gt $script:maximumUsePerOperation) {
            return $null
        }

        $operation[$property.Name] = [int]$count
    }

    if ($operation.Count -eq 0) {
        return $null
    }

    return $operation
}

function Use-RemoteGrant {
    <#
        Consumes the Remote grant of a session for the operations a command
        needs, all or none. The file is opened exclusively, so concurrent tool
        calls of one session cannot spend the same use twice; a file another
        process holds for more than about a second is treated as no grant. Never
        creates or changes anything but the one grant file, and leaves it as it
        was when it does not cover the command. Returns $true when it consumed.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$SessionId,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Required,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Root
    )

    $key = Get-GrantKey -SessionId $SessionId
    if ([string]::IsNullOrEmpty($key) -or $Required.Count -eq 0) {
        return $false
    }

    if ([string]::IsNullOrWhiteSpace($Root)) {
        $profileRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
        if ([string]::IsNullOrWhiteSpace($profileRoot)) {
            return $false
        }

        $Root = [System.IO.Path]::Combine($profileRoot, 'CopilotAtelier', 'grants')
    }

    $path = [System.IO.Path]::Combine($Root, "grant-$key.json")
    $stream = $null
    $isUsedUp = $false

    try {
        # The decision has a time limit, so the wait for a held file is bounded by it too.
        $attemptLimit = [Math]::Min(10, [int](($script:timeLimit - $script:decisionClock.Elapsed).TotalMilliseconds / 100) - 5)
        for ($attempt = 0; $attempt -lt $attemptLimit -and $null -eq $stream; $attempt++) {
            if (-not [System.IO.File]::Exists($path)) {
                return $false
            }

            try {
                $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            } catch [System.IO.FileNotFoundException] {
                return $false
            } catch [System.IO.DirectoryNotFoundException] {
                return $false
            } catch [System.UnauthorizedAccessException] {
                return $false
            } catch [System.IO.IOException] {
                [System.Threading.Thread]::Sleep(100)
            }
        }

        if ($null -eq $stream -or $stream.Length -gt $script:maximumGrantFileLength) {
            return $false
        }

        $reader = [System.IO.StreamReader]::new($stream, [System.Text.UTF8Encoding]::new($false), $false, 4096, $true)
        try {
            $text = $reader.ReadToEnd()
        } finally {
            $reader.Dispose()
        }

        $operation = Get-GrantOperation -Text $text -Key $key
        if ($null -eq $operation) {
            return $false
        }

        foreach ($name in $Required.Keys) {
            if (-not $operation.Contains($name) -or $operation[$name] -lt [int]$Required[$name]) {
                return $false
            }
        }

        $left = [ordered]@{}
        foreach ($name in $operation.Keys) {
            $remaining = $operation[$name]
            if ($Required.Contains($name)) {
                $remaining -= [int]$Required[$name]
            }

            if ($remaining -gt 0) {
                $left[$name] = $remaining
            }
        }

        if ($left.Count -eq 0) {
            # Empty the file while the lock is held. A process that waited on the lock opens the file the moment it is
            # released, and the delete below runs only after that, so a file that still held the grant could be spent
            # a second time (found when a concurrent test failed under load).
            $stream.SetLength(0)
            $stream.Flush()
            $isUsedUp = $true
        } else {
            $grant = $text | ConvertFrom-Json
            $rewritten = [ordered]@{
                schema = 1
                sessionKey = $key
                issuedAt = [long]$grant.issuedAt
                expiresAt = [long]$grant.expiresAt
            }
            if ($grant.promptSha256 -is [string]) {
                $rewritten.promptSha256 = $grant.promptSha256
            }

            $rewritten.operations = $left
            $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes(($rewritten | ConvertTo-Json -Depth 4))
            $stream.SetLength(0)
            $stream.Position = 0
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush()
        }
    } catch {
        return $false
    } finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }

    if ($isUsedUp) {
        try {
            [System.IO.File]::Delete($path)
        } catch {
            Write-Verbose -Message 'A used-up grant file could not be removed.'
        }
    }

    return $true
}

function Get-PushPhrase {
    <#
        The Grant marker phrase a push needs: git push, or git push --force when
        the text after the push word, up to the end of its statement, carries a
        force, delete, mirror, or prune option, a short option cluster with f or
        d, or a +ref or :ref refspec. A variable that holds such an option or a refspec is not
        resolved: this reads the text. That is an accepted residual (review of 2026-10-13, fifth
        pass, F6; the owner ruled on it), documented in the hooks README.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Text,

        [Parameter(Mandatory)]
        [System.Text.RegularExpressions.Match]$Match
    )

    $rest = $Text.Substring($Match.Index + $Match.Length)

    try {
        $end = $script:statementEnd.Match($rest)
        $statement = if ($end.Success) { $rest.Substring(0, $end.Index) } else { $rest }

        if ($script:forcePushOption.IsMatch($statement)) {
            return 'git push --force'
        }
    } catch [System.Text.RegularExpressions.RegexMatchTimeoutException] {
        # Unclassified is as bad as a force push: it needs the stronger marker.
        return 'git push --force'
    }

    return 'git push'
}

function Test-Repetition {
    <#
        True when a command text holds syntax that can run an operation more than once: a
        loop, a function, a pipeline into ForEach-Object, xargs, or a call operator. A match
        that runs out of time counts as a repetition, the cautious answer. A text that could
        not be read as PowerShell (-Unparsed) has no syntax tree to show whether a brace is a
        script block that something runs again and again, so a brace in it counts too.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text,

        [Parameter()]
        [switch]$Unparsed
    )

    if ($Unparsed -and $Text.IndexOf('{') -ge 0) {
        return $true
    }

    try {
        if ($script:repetitionSyntax.IsMatch($Text)) {
            return $true
        }

        # PowerShell drops a backtick in a word, so wat`ch is watch; a text that holds one is read both ways.
        return ($Text.IndexOf('`') -ge 0 -and $script:repetitionSyntax.IsMatch($Text.Replace('`', '')))
    } catch [System.Text.RegularExpressions.RegexMatchTimeoutException] {
        return $true
    }
}

function Get-RawCommandText {
    <#
        Pulls the command-bearing fields out of raw JSON text and joins them the
        way the walk does, so a command split across fields, such as
        {"command":"git","args":["push"]}, reads as one command line there too.
        It shares the decision's time limit and blocks the call when that runs
        out.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text,

        [Parameter()]
        [switch]$DecodeValue
    )

    $part = [System.Collections.Generic.List[string]]::new()
    $objectJoin = [System.Collections.Generic.List[string]]::new()
    $executable = [System.Collections.Generic.List[string]]::new()
    $argument = [System.Collections.Generic.List[string]]::new()
    $executableAll = [System.Collections.Generic.List[string]]::new()
    $argumentAll = [System.Collections.Generic.List[string]]::new()
    try {
        $timeLeft = $script:timeLimit - $script:decisionClock.Elapsed
        if ($timeLeft -le [TimeSpan]::Zero) {
            Block-ToolCall -Because $script:notInspectedInTime
        }

        $fieldPattern = [regex]::new(
            $script:rawFieldPattern,
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase,
            $timeLeft
        )

        # Match and NextMatch rather than enumerating Matches: a timeout raised
        # inside foreach's enumeration would not reach the catch below as itself.
        # The loop runs once per field and can meet a flood of them, so it keeps
        # its lookups local. A per-object join needs an executable field, so a
        # text without one also skips the per-field brace search.
        $clock = $script:decisionClock
        $limit = $script:timeLimit
        $brace = $script:braceCharacter
        $executableName = [System.Collections.Generic.HashSet[string]]::new(
            [string[]]$script:executableField,
            [System.StringComparer]::OrdinalIgnoreCase
        )
        $hasExecutable = $false
        foreach ($name in $executableName) {
            if ($Text.IndexOf('"' + $name + '"', [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $hasExecutable = $true
                break
            }
        }

        $previousEnd = 0
        $match = $fieldPattern.Match($Text)
        while ($match.Success) {
            if ($clock.Elapsed -gt $limit) {
                Block-ToolCall -Because $script:notInspectedInTime
            }

            # A brace since the previous field starts another object.
            if ($hasExecutable -and $Text.IndexOfAny($brace, $previousEnd, $match.Index - $previousEnd) -ge 0) {
                if ($executable.Count -gt 0 -and $argument.Count -gt 0) {
                    $objectJoin.Add((([string[]]$executable.ToArray() + [string[]]$argument.ToArray()) -join ' '))
                }
                $executable.Clear()
                $argument.Clear()
            }

            $group = $match.Groups
            $isString = $group[2].Success
            $value = if ($isString) { $group[2].Value } else { $group[3].Value }
            if ($DecodeValue -and $value.Contains('\')) {
                try {
                    $value = [regex]::Unescape($value)
                } catch [System.ArgumentException] {
                    Write-Verbose -Message 'A field holds an escape Regex.Unescape rejects; it is joined as written.'
                }
            }

            if (-not $isString) {
                $value = $value.Replace('"', ' ').Replace('[', ' ').Replace(']', ' ').Replace(',', ' ')
            }

            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $part.Add($value)
                if ($executableName.Contains($group[1].Value)) {
                    $executable.Add($value)
                    $executableAll.Add($value)
                } else {
                    $argument.Add($value)
                    $argumentAll.Add($value)
                }
            }

            $previousEnd = $match.Index + $match.Length
            $match = $match.NextMatch()
        }
    } catch [System.Text.RegularExpressions.RegexMatchTimeoutException] {
        Block-ToolCall -Because $script:notInspectedInTime
    }

    if ($executable.Count -gt 0 -and $argument.Count -gt 0) {
        $objectJoin.Add((([string[]]$executable.ToArray() + [string[]]$argument.ToArray()) -join ' '))
    }

    # A brace between two fields only suggests a new object; a nested value or a
    # brace in a string looks the same. So the fields are also joined across the
    # whole payload, which errs toward blocking like the rest of this path.
    Join-CommandPart -Part $part -ObjectCommand $objectJoin -ExecutablePart $executableAll -ArgumentPart $argumentAll
}

if ([string]::IsNullOrEmpty($InputJson)) {
    # Decode explicitly: Windows PowerShell would otherwise use the console input
    # encoding, which mangles non-ASCII payloads that pwsh reads as UTF-8.
    $reader = [IO.StreamReader]::new([Console]::OpenStandardInput(), [Text.UTF8Encoding]::new($false))
    try {
        $InputJson = $reader.ReadToEnd()
    } finally {
        $reader.Dispose()
    }
}

if ([string]::IsNullOrWhiteSpace($InputJson)) {
    exit 0
}

if ($InputJson.Length -gt $maximumPayloadLength) {
    Block-ToolCall -Because 'this tool call is too large to inspect'
}

$isPayloadReadable = $true
if ($InputJson.Length -gt $maximumParseLength) {
    $isWalkComplete = $false
    $walkStopReason = 'is too large to walk field by field'
} else {
    try {
        $payload = $InputJson | ConvertFrom-Json -ErrorAction Stop
        Add-CommandPart -InputObject $payload.tool_input
    } catch {
        # Windows PowerShell rejects JSON nested past 100 levels and PowerShell 7
        # past 1024, so an unreadable payload is not necessarily a harmless one.
        $isPayloadReadable = $false
        $isWalkComplete = $false
    }
}

$scanText = [System.Collections.Generic.List[string]]::new()
foreach ($text in @(Join-CommandPart -Part $commandPart -ObjectCommand $objectCommand)) {
    $scanText.Add($text)
}

if (-not $isWalkComplete) {
    # Scan what the walk could not reach as raw text, also with its JSON escapes
    # decoded, so neither nesting nor malformed JSON hides a blocked command.
    # Each text is scanned on its own: one joined text would only make the
    # quadratic patterns slower.
    $rawText = [System.Collections.Generic.List[string]]::new()
    $rawText.Add($InputJson)
    if ($InputJson.Contains('\')) {
        try {
            $rawText.Add([regex]::Unescape($InputJson))
        } catch [System.ArgumentException] {
            Write-Verbose -Message 'The payload holds an escape Regex.Unescape rejects; it is scanned as written.'
        }
    }

    # The walk joins every command-bearing field it finds, which the raw text
    # cannot: there, field names and other fields sit between the parts of a
    # command split across fields. So the same fields are pulled out of the raw
    # text and joined, as written with each value decoded and, for a key spelled
    # with escapes, from the decoded text. They are short, so they go first.
    $fieldText = [System.Collections.Generic.List[string]]::new()
    foreach ($text in @(Get-RawCommandText -Text $InputJson -DecodeValue)) {
        $fieldText.Add($text)
    }
    if ($rawText.Count -gt 1) {
        foreach ($text in @(Get-RawCommandText -Text $rawText[1])) {
            $fieldText.Add($text)
        }
    }

    # An argument array reads as ["git","push"] in raw JSON. Without the JSON
    # punctuation it reads as the command line the walk would have joined.
    foreach ($text in @($rawText)) {
        $rawText.Add(($text -replace '["\[\],]', ' '))
    }

    $scanText.AddRange($fieldText)
    $scanText.AddRange($rawText)
}

if ($scanText.Count -eq 0) {
    exit 0
}

# Fold shell line continuations so a split command cannot hide the subcommand. PowerShell also reads pu`sh as push and
# --f`orce as --force, but a POSIX shell runs the text between two backticks, and deleting a backtick can glue it to
# the word before it (echo a`git push` becomes agit push). So a text that holds a backtick is read twice, as written
# and without its backticks (review of 2026-10-13, sixth pass, N3, and the author's probe of the same class in a
# command word).
$readWithoutBackticks = [System.Collections.Generic.List[string]]::new()
for ($index = 0; $index -lt $scanText.Count; $index++) {
    $scanText[$index] = $scanText[$index] -replace '[`^\\]\r?\n\s*', ' '
    if ($scanText[$index].IndexOf('`') -ge 0) {
        $readWithoutBackticks.Add($scanText[$index].Replace('`', ''))
    }
}

$scanText.AddRange($readWithoutBackticks)

# Every pattern needs a git or gh word. Searching for one costs a fraction of a
# pattern scan, which under PowerShell 7 takes about 70 ms per MB, so a text
# without either is not scanned at all.
$scanText = @(
    $scanText | Where-Object {
        $_.IndexOf('git', [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $_.IndexOf('gh', [System.StringComparison]::OrdinalIgnoreCase) -ge 0
    }
)

$nonGrantableReason = $null
$firstGrantableReason = $null
$required = @{}
$pushTotal = 0
$pushForce = 0
$phraseOrder = [System.Collections.Generic.List[string]]::new()

:operation foreach ($rule in $operationRule) {
    foreach ($text in $scanText) {
        $timeLeft = $timeLimit - $decisionClock.Elapsed
        if ($timeLeft -le [TimeSpan]::Zero) {
            $nonGrantableReason = $notInspectedInTime
            break operation
        }

        $found = [System.Collections.Generic.List[System.Text.RegularExpressions.Match]]::new()
        try {
            $pattern = [regex]::new(
                $rule.Pattern,
                [System.Text.RegularExpressions.RegexOptions]::IgnoreCase,
                $timeLeft
            )

            # Match and NextMatch rather than Matches: a MatchCollection matches lazily, so a
            # timeout would surface at a later Count, outside this try, where PowerShell
            # only ends that statement and the rule would be skipped. One more than the
            # most that a grant can cover is enough to know there are too many.
            $current = $pattern.Match($text)
            while ($current.Success -and $found.Count -le $maximumOperationMatch) {
                $found.Add($current)
                $current = $current.NextMatch()
            }
        } catch [System.Text.RegularExpressions.RegexMatchTimeoutException] {
            $nonGrantableReason = $notInspectedInTime
            break operation
        }

        if ($found.Count -eq 0) {
            continue
        }

        # A rule no marker can lift ends the scan: it decides the block and its reason.
        if (-not $rule.Kind -or $found.Count -gt $maximumOperationMatch) {
            $nonGrantableReason = "this command $($rule.Reason)"
            break operation
        }

        if (-not $firstGrantableReason) {
            $firstGrantableReason = "this command $($rule.Reason)"
        }

        $countInText = @{}
        foreach ($match in $found) {
            $phrase = switch ($rule.Kind) {
                'push' { Get-PushPhrase -Text $text -Match $match }
                'gh' { 'gh ' + ($match.Groups['operation'].Value.ToLowerInvariant() -replace '\s+', ' ') }
                default { 'gh api' }
            }

            $countInText[$phrase] = 1 + [int]$countInText[$phrase]
            if (-not $phraseOrder.Contains($phrase)) {
                $phraseOrder.Add($phrase)
            }
        }

        # The guard counts the operations it reads, not the times they run, so a command that can
        # repeat one asks for every use a marker can grant.
        if ($isRepetitive) {
            foreach ($phrase in @($countInText.Keys)) {
                $countInText[$phrase] = $maximumUsePerOperation
            }
        }

        # The same command can sit in more than one scanned text, so the most any one text shows counts. A push is
        # counted as one family across the texts: the two readings of one push, with and without its backticks, may
        # call it plain in one and forced in the other, and it needs the one stronger marker, not both.
        if ($rule.Kind -eq 'push') {
            $plainHere = [int]$countInText['git push']
            $forceHere = [int]$countInText['git push --force']
            $pushTotal = [Math]::Max($pushTotal, $plainHere + $forceHere)
            $pushForce = [Math]::Max($pushForce, $forceHere)
            continue
        }

        foreach ($phrase in @($countInText.Keys)) {
            if (-not $required.ContainsKey($phrase) -or $required[$phrase] -lt $countInText[$phrase]) {
                $required[$phrase] = $countInText[$phrase]
            }
        }
    }
}

if ($pushTotal -gt 0) {
    if ($pushTotal -gt $pushForce) {
        $required['git push'] = $pushTotal - $pushForce
    }

    if ($pushForce -gt 0) {
        $required['git push --force'] = $pushForce
    }
}

$phraseOrder = [System.Collections.Generic.List[string]]::new([string[]]@($phraseOrder | Where-Object -FilterScript { $required.ContainsKey($_) }))

if ($nonGrantableReason) {
    Block-ToolCall -Because $nonGrantableReason
}

if ($launchesGitIndirectly) {
    Block-ToolCall -Because 'this command launches git or gh through a command it cannot read'
}

if ($required.Count -gt 0) {
    # Only a payload this script read completely can carry a Remote grant: what it had
    # to scan as raw text is blocked as before, and no marker would help there.
    if ($isPayloadReadable -and $isWalkComplete) {
        $sessionId = ''
        foreach ($name in 'session_id', 'sessionId') {
            if ($payload.PSObject.Properties[$name] -and $payload.$name -is [string]) {
                $sessionId = [string]$payload.$name
                break
            }
        }

        if (Use-RemoteGrant -SessionId $sessionId -Required $required -Root $GrantRoot) {
            [Console]::Error.WriteLine('Block-RemoteMutation: allowed by a Remote grant: ' + ($phraseOrder -join ', ') + '.')
            exit 0
        }

        $markerOperation = foreach ($phrase in $phraseOrder) {
            if ($required[$phrase] -gt 1) { '{0} x{1}' -f $phrase, $required[$phrase] } else { $phrase }
        }
        Block-ToolCall -Because $firstGrantableReason -MarkerOperation @($markerOperation) -IsRepetitive:$isRepetitive
    }

    Block-ToolCall -Because $firstGrantableReason
}

if (-not $isPayloadReadable) {
    # Exit 0, not 1: the Copilot SDK host denies a preToolUse call on any other
    # non-zero exit, so a payload schema change would block every tool call.
    [Console]::Error.WriteLine('Block-RemoteMutation: hook payload is not valid JSON; allowing the tool call.')
} elseif (-not $isWalkComplete) {
    [Console]::Error.WriteLine(
        "Block-RemoteMutation: hook payload $walkStopReason and its raw text holds no blocked command; allowing the tool call."
    )
}

exit 0
