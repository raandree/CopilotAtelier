---
agent: security-reviewer
description: Multi-phase PowerShell security code review producing Markdown + SARIF v2.1.0 findings scored with CVSS v4.0 Base.
---

# PowerShell Security Code Review

Drive a structured, multi-phase security code review for PowerShell projects. Use
custom detection rules aligned to CWE taxonomy, PSScriptAnalyzer, and Pester to
produce reports in Markdown and SARIF v2.1.0. Score findings with CVSS v4.0 Base
(CVSS-B) and annotate each with a confidence level.

## Instructions

Execute the phases below in order. Each phase builds on the memory bank and outputs
from the previous phase.

## Phase 1 — Initial Setup

The PowerShell modules in the source folder need to be checked for security and
malicious code. Please start with a memory bank to outline the task and track
the progress. Also create documentation to describe the overall purpose of the
project.

The memory bank should include:

- A **task backlog** with status tracking (not started / in progress / done).
- A **risk register** for tracking accepted risks, waivers, and suppressed
  findings discovered during the review.
- A **configuration section** that records:
  - The CVSS version used for scoring (default: **CVSS v4.0 Base**).
  - The report output formats (Markdown + SARIF).
  - The PSScriptAnalyzer version and profile in use.

## Phase 2.1 — Define Detection Rules

There are already some detection rules defined in the `scanner/rules` folder.
Please extend and improve these rules based on your research.

Browse the web and learn about PowerShell security coding guidelines. Then
create a Detection Rules file that combines the knowledge.

### Detection Rule Schema

Each rule **must** use the following format:

```text
Id          = 'PS001'
Name        = 'Invoke-Expression Usage'
Severity    = 'Medium'
Confidence  = 'High'
Category    = 'CodeExecution'
CWE         = 'CWE-94'
Description = 'Detects use of Invoke-Expression which can execute arbitrary code from strings'
ASTPattern  = 'CommandAst'
CommandName = 'Invoke-Expression'
Remediation = 'Replace Invoke-Expression with safer alternatives like & operator or dot-sourcing'
CVSSVersion = '4.0'
CVSSScore   = 5.3
References  = 'https://cwe.mitre.org/data/definitions/94.html'
```

**Required fields:** `Id`, `Name`, `Severity`, `Confidence`, `Category`, `CWE`,
`Description`, `Remediation`, `CVSSVersion`, `CVSSScore`.

**Optional fields:** `ASTPattern`, `CommandName`, `References`.

### Field definitions

| Field | Values / Notes |
|---|---|
| `Severity` | `Critical`, `High`, `Medium`, `Low`, `Info` |
| `Confidence` | `High`, `Medium`, `Low` — indicates how likely a match is a true positive |
| `CWE` | CWE identifier from MITRE CWE (e.g., `CWE-78`, `CWE-798`). Use the most specific applicable CWE. |
| `CVSSVersion` | `4.0` (preferred) or `3.1` for backward compatibility |
| `CVSSScore` | Numeric score 0.0–10.0. For CVSS v4.0, use the CVSS-B (Base) score. |
| `References` | Semicolon-separated URLs to CWE entries, OWASP pages, or vendor advisories |

### CWE mapping guidance for PowerShell rules

Use these CWE identifiers as starting points (refine as needed):

| Category | CWE | Description |
|---|---|---|
| Code Execution | CWE-94 | Improper Control of Generation of Code ('Code Injection') |
| OS Command Injection | CWE-78 | Improper Neutralization of Special Elements in OS Command |
| Hard-coded Credentials | CWE-798 | Use of Hard-coded Credentials |
| Sensitive Data in Logs | CWE-532 | Insertion of Sensitive Information into Log File |
| Broken Crypto | CWE-327 | Use of a Broken or Risky Cryptographic Algorithm |
| Deserialization | CWE-502 | Deserialization of Untrusted Data |
| Plaintext Transmission | CWE-319 | Cleartext Transmission of Sensitive Information |
| Insecure TLS | CWE-295 | Improper Certificate Validation |
| Path Traversal | CWE-22 | Improper Limitation of a Pathname to a Restricted Directory |
| Uncontrolled Search Path | CWE-426 | Untrusted Search Path |
| Missing Auth | CWE-862 | Missing Authorization |
| AMSI Bypass | CWE-693 | Protection Mechanism Failure |
| Supply Chain | CWE-1357 | Reliance on Insufficiently Trustworthy Component |

### PSScriptAnalyzer integration

In addition to custom rules, incorporate the following PSScriptAnalyzer
security-related built-in rules (reference the full list at
<https://learn.microsoft.com/en-us/powershell/utility-modules/psscriptanalyzer/rules/readme>):

**Error-level (must-fix):**

- `AvoidUsingComputerNameHardcoded`
- `AvoidUsingConvertToSecureStringWithPlainText`
- `AvoidUsingUsernameAndPasswordParams`

**Warning-level (should-fix):**

- `AvoidUsingAllowUnencryptedAuthentication`
- `AvoidUsingBrokenHashAlgorithms`
- `AvoidUsingInvokeExpression`
- `AvoidUsingPlainTextForPassword`
- `AvoidUsingEmptyCatchBlock`
- `UseUsingScopeModifierInNewRunspaces`

Also scan the web for additional PSScriptAnalyzer rules that are available on
GitHub, for example in the organization <https://github.com/dsccommunity>.

### Modern PowerShell security concerns

Create or extend rules for these additional security concerns:

1. **AMSI bypass detection** — look for patterns that disable or bypass the
   Antimalware Scan Interface (`[Ref].Assembly`, `amsiInitFailed`,
   `AmsiUtils`). Map to `CWE-693`.
2. **Constrained Language Mode evasion** — detect attempts to circumvent CLM
   restrictions via PowerShell runspace manipulation or COM objects.
3. **PowerShell downgrade attacks** — flag explicit invocations of `powershell
   -version 2` which bypass modern security features (AMSI, script block
   logging). Map to `CWE-693`.
4. **Logging bypass** — detect code that disables PowerShell transcription,
   script block logging, or module logging (e.g., setting
   `ScriptBlockLogging` registry keys to 0).
5. **SecureString misuse** — Microsoft recommends against `SecureString` for
   new development. Flag `ConvertTo-SecureString` with `-AsPlainText` usage
   and note the deprecation guidance.
6. **Supply chain risks** — look for:
   - `Install-Module` / `Install-PSResource` without `-Repository` or
     version pinning.
   - References to untrusted or non-default PSRepositories.
   - Module names that closely resemble popular modules (typosquatting
     indicators).
   - Missing SBOM references in module manifests (PowerShell 7.2+).
   Map to `CWE-1357`.
7. **Unencrypted remoting** — detect WinRM or SSH remoting configurations
   that do not enforce TLS/HTTPS. Map to `CWE-319`.

## Phase 2.2 — Realign the Detection Rules

The source code is PowerShell. In PowerShell it is normal to deal with
credentials in a semi-secure way.

A rule like 'Sensitive Data in Logs' should be only treated as critical if it
affects plaintext passwords, security keys, or tokens. Writing user names or IDs
to log files is essential for debugging.

A rule like 'High Entropy Strings' should be deemphasized. PowerShell by nature
uses high entropy strings to express the intent in code. Findings should be
analyzed further for security issues and not treated as critical by default.

A rule like 'Weak Hash Algorithm' (PS014) is informational. Weak hashing is
only a security concern when used for cryptographic purposes (password hashing,
certificate validation). Using MD5/SHA1 for checksums or cache keys is
acceptable. Set Confidence to `Low` when the context suggests non-cryptographic
use.

### Confidence calibration

After creating or updating rules, review each rule's `Confidence` field:

- **High** — the pattern almost always indicates a real security issue
  (e.g., `ConvertTo-SecureString -AsPlainText -Force` with a string literal).
- **Medium** — the pattern often indicates an issue but requires context
  analysis (e.g., `Invoke-Expression` may be used safely in build scripts).
- **Low** — the pattern frequently produces false positives and needs manual
  review (e.g., high-entropy strings, hostname checks in DSC code).

## Phase 2.3 — PowerShell Security Scanning Scripts

In the directory `scanner`, there is already the scanner script you have created
before. It was created to scan PowerShell code for the defined detection rules.
Please scan it and improve it where needed. Also make use of `PSScriptAnalyzer`
and `Pester` to generate the scripts.

### Scanner output requirements

The scanner must produce output in **two formats**:

1. **Markdown** — human-readable reports for direct review (default, as used in
   Phase 3).
2. **SARIF v2.1.0** — machine-readable JSON for integration with VS Code SARIF
   Viewer, GitHub Code Scanning, and Azure DevOps.

#### SARIF output guidance

Generate a valid SARIF v2.1.0 file (`Report/scan-results.sarif`) with:

```json
{
  "version": "2.1.0",
  "$schema": "https://docs.oasis-open.org/sarif/sarif/v2.1.0/errata01/os/schemas/sarif-schema-2.1.0.json",
  "runs": [
    {
      "tool": {
        "driver": {
          "name": "PSSecurityScanner",
          "version": "1.0.0",
          "rules": [
            {
              "id": "PS001",
              "shortDescription": { "text": "Invoke-Expression Usage" },
              "fullDescription": { "text": "Detects use of Invoke-Expression..." },
              "defaultConfiguration": { "level": "warning" },
              "helpUri": "https://cwe.mitre.org/data/definitions/94.html",
              "relationships": [
                {
                  "target": { "id": "94", "toolComponent": { "name": "CWE" } },
                  "kinds": ["superset"]
                }
              ]
            }
          ],
          "supportedTaxonomies": [
            { "name": "CWE", "guid": "..." }
          ]
        }
      },
      "taxonomies": [
        {
          "name": "CWE",
          "version": "4.16",
          "taxa": []
        }
      ],
      "results": []
    }
  ]
}
```

Key SARIF mapping:

| Custom Field | SARIF Property |
|---|---|
| `Id` | `result.ruleId` + `run.tool.driver.rules[].id` |
| `Severity` Critical/High → `"error"`, Medium → `"warning"`, Low/Info → `"note"` | `result.level` |
| `Confidence` | `result.rank` (0.0–100.0) or `result.properties.confidence` |
| `CWE` | `rule.relationships[].target.id` in CWE taxonomy |
| `CVSSScore` | `result.properties.cvssScore` |
| `File` + `Line` | `result.locations[].physicalLocation` |
| `Remediation` | `rule.help.text` or `result.fixes[]` |

## Phase 3 — Start the Code Review

Start the code review according to the process and the definitions in the memory
bank.

Reports should be created in the folder `Report`.

**Important**: Please create:

1. An **executive summary** covering all PowerShell modules.
2. One **detailed report** per PowerShell module.
3. A **SARIF file** (`Report/scan-results.sarif`) containing all findings in
   machine-readable format.

### Detailed report finding structure

Each finding in the detailed Markdown report should use:

```text
Rule:        <Rule Id> — <Rule Name>
CWE:         <CWE-xxx>
Category:    <Category>
Severity:    <Critical|High|Medium|Low|Info>
Confidence:  <High|Medium|Low>
File:        <Full File Path>
- Line: <Line number(s)>
  Code: <Code or line content>
- Line: <Line number(s)>
  Code: <Code or line content>
Description: <Description>
Remediation: <Suggestions for remediation>
CVSS Score:  <Score> (CVSS v4.0 Base)
References:  <URL(s)>
```

### Executive summary additions

The executive summary should include:

- Total findings count by severity and confidence.
- A **risk matrix** (severity × confidence) showing the distribution.
- Top 5 most affected files.
- Top CWE categories encountered.
- Count of PSScriptAnalyzer rule violations by rule name.
- List of accepted risks / waivers from the risk register (if any).

### Important notes — False positive mitigation

- Report 'High Entropy Detection' with care. It is very likely that we generate
  a lot of false positives. Set `Confidence = Low`.
- Report on 'Hardcoded Credentials' (PS009) or 'Credential Logging' (PS012)
  only if you actually find hard-coded credentials in the code or if the code
  very likely exposes the credentials in an inappropriate way, for example
  writing them to a log file or to the console.
- Some cmdlets in PowerShell like `Where-Object` only work when providing a
  scriptblock. This is not a security flaw and should be taken into account
  when reporting on 'Script Block Injection'.
- When looking for 'Character Substitution Obfuscation', please take into
  account that for solving string escaping issues in PowerShell, it is required
  to use characters like `'`, `"` or `` ` `` in various orders. Doing this is
  not necessarily a security issue.
- 'Hostname or Domain Checks' (PS030) are expected in code that configures
  machines. Only report if the hostname or domain is used in a suspicious way,
  for example to whitelist or blacklist connections without proper validation.
  If you think it is a security issue, investigate given the context of the
  code.
- PS002 (Add-Type Usage) should be reported only if the usage of `Add-Type`
  introduces potential security risks, such as executing untrusted code or
  loading assemblies from unverified sources.
- PS014 (Weak Hash Algorithm) is informational and not a security issue. Report
  it as `Info` severity with `Confidence = Low` unless the hash is used for
  cryptographic authentication or integrity.

### Triage and risk acceptance

When a finding is determined to be a false positive or an accepted risk:

1. Mark it as suppressed in the SARIF output using `result.suppressions` with
   `kind = "inSource"` or `kind = "external"` and `status = "accepted"`.
2. Record the rationale in the risk register (memory bank).
3. Exclude suppressed findings from the severity totals in the executive summary
   but list them separately under an "Accepted Risks" section.

## Phase 4 — Pending Tasks

Review the memory bank for pending tasks and print them out.

Include a summary of:

- Open findings requiring further investigation.
- Items in the risk register pending review.
- Any detection rules flagged for confidence recalibration.

## Phase 5 — Create Additional Documentation

Please create a `readme.md` in each folder to describe the content. Also create
a comprehensive `readme.md` in the root directory describing the project. The
main readme should have references to the other readmes and relevant
documentation documents.

The root `readme.md` should include:

- Project overview and purpose.
- Instructions for running the scanner.
- Description of report formats (Markdown + SARIF).
- How to view SARIF results in VS Code (install the SARIF Viewer extension).
- Link to CVSS v4.0 calculator: <https://www.first.org/cvss/calculator/4.0>.
- Link to CWE database: <https://cwe.mitre.org/>.
- Link to PSScriptAnalyzer rules: <https://learn.microsoft.com/en-us/powershell/utility-modules/psscriptanalyzer/rules/readme>.
- Link to SARIF specification: <https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html>.
- Link to OWASP Code Review Guide: <https://owasp.org/www-project-code-review-guide/>.
- Link to PowerShell security features: <https://learn.microsoft.com/en-us/powershell/scripting/security/security-features>.

## Phase 6 — Optional Tasks

Please run also the optional tasks.

Additional optional items to consider:

- Generate a **SARIF diff** if a previous scan baseline exists, marking findings
  as `new`, `unchanged`, or `absent` using `result.baselineState`.
- Run `PSScriptAnalyzer` with the `-Settings` parameter using a custom settings
  file that enables all security-related rules.
- Produce a **supply chain report** that inventories all external module
  dependencies, their sources, versions, and whether they are pinned.
- Validate that any `SecureString` usage follows current Microsoft guidance
  (avoid for new development, document legacy usage).

## References

- [SARIF Specification v2.1.0](https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html)
- [SARIF Tools & Viewers](https://sarifweb.azurewebsites.net/)
- [CVSS v4.0 Specification](https://www.first.org/cvss/v4-0/)
- [CWE — Common Weakness Enumeration](https://cwe.mitre.org/)
- [OWASP Code Review Guide](https://owasp.org/www-project-code-review-guide/)
- [PSScriptAnalyzer Rules Reference](https://learn.microsoft.com/en-us/powershell/utility-modules/psscriptanalyzer/rules/readme)
- [PowerShell Security Features](https://learn.microsoft.com/en-us/powershell/scripting/security/security-features)
- [OWASP Top Ten 2021 — A03:2021 Injection](https://owasp.org/Top10/A03_2021-Injection/)
- [CWE Top 25 Most Dangerous Software Weaknesses (2025)](https://cwe.mitre.org/top25/)
