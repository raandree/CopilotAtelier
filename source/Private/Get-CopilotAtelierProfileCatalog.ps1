function Get-CopilotAtelierProfileCatalog
{
    <#
        .SYNOPSIS
            Returns the installation profile catalog, its mandatory Skills, and
            the declared Skill dependency map.

        .DESCRIPTION
            The catalog is the single source of truth for opt-in installation
            profiles. `complete` is the default and selects every Skill in the
            payload; the other profiles name an explicit subset.

            MandatorySkill lists Skills that the deployed lifecycle Instructions
            and shipped Custom agents load by name. They are added to every
            selection and cannot be excluded.

            Dependency maps a Skill to the Skills it hands part of its own
            workflow to. Only compositions are listed, never the "do not use for"
            pointers a Skill uses to redirect a reader elsewhere. The map must
            stay acyclic; Resolve-CopilotAtelierSkillSelection rejects a cycle.

        .OUTPUTS
            System.Management.Automation.PSCustomObject

        .EXAMPLE
            Get-CopilotAtelierProfileCatalog

            Returns the profile definitions, mandatory Skills, and dependencies.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param ()

    return [pscustomobject] @{
        DefaultProfile = 'complete'

        MandatorySkill = @(
            'agent-security-review'
            'long-running-job-monitor'
            'memory-bank'
        )

        Dependency = [ordered] @{
            'automatedlab-proxmox'      = @('long-running-job-monitor')
            'elster-form-capture'       = @('authenticated-web-extraction', 'german-tax-research')
            'evidence-package-assembly' = @('pandoc-docx-export')
            'mcp-builder'               = @('agent-security-review')
            'pandoc-docx-export'        = @('docx-to-markdown')
            'sampler-build-debug'       = @('long-running-job-monitor')
            'social-signal-sweep'       = @('authenticated-web-extraction', 'citation-integrity')
            'test-driven-development'   = @('pester-patterns')
        }

        Profile = [ordered] @{
            'complete' = [pscustomobject] @{
                Description = 'Every Skill in the payload. This is the default and the only selection that needs no argument.'
                IncludesEverySkill = $true
                Skill = @()
            }

            'engineering' = [pscustomobject] @{
                Description = 'Software and infrastructure engineering: build, test, review, debugging, DSC, lab, and Customization authoring.'
                IncludesEverySkill = $false
                Skill = @(
                    'agent-evals'
                    'agent-security-review'
                    'automatedlab-deployment'
                    'automatedlab-proxmox'
                    'changed-file-validation'
                    'code-review-and-quality'
                    'copilot-usage-stats'
                    'datum-configuration'
                    'debugging-and-error-recovery'
                    'dsc-troubleshooting'
                    'gilb-requirements-engineering'
                    'grill-me'
                    'long-running-job-monitor'
                    'mcp-builder'
                    'mecm-dsc-deployment'
                    'memory-bank'
                    'pester-patterns'
                    'pswritehtml-reporting'
                    'sampler-build-debug'
                    'sampler-framework'
                    'sampler-migration'
                    'skill-creator'
                    'subagent-dispatch'
                    'test-driven-development'
                    'windows-gui-screenshot-capture'
                    'winrm-troubleshooting'
                )
            }

            'research' = [pscustomobject] @{
                Description = 'Source-grounded research and drafting: verification, critique, co-authoring, and the German legal and tax domains.'
                IncludesEverySkill = $false
                Skill = @(
                    'agent-security-review'
                    'authenticated-web-extraction'
                    'citation-integrity'
                    'devils-advocate-review'
                    'doc-coauthoring'
                    'elster-form-capture'
                    'german-legal-research'
                    'german-tax-research'
                    'gilb-requirements-engineering'
                    'grammar-check'
                    'grill-me'
                    'long-running-job-monitor'
                    'memory-bank'
                    'social-signal-sweep'
                    'subagent-dispatch'
                )
            }

            'document-processing' = [pscustomobject] @{
                Description = 'Reading, producing, and delivering documents: PDF, Word, Excel, slides, transcripts, reports, branding, and Outlook.'
                IncludesEverySkill = $false
                Skill = @(
                    'agent-security-review'
                    'brand-logo-system'
                    'create-outlook-draft'
                    'docx-to-markdown'
                    'evidence-package-assembly'
                    'grammar-check'
                    'long-running-job-monitor'
                    'marp-slide-overflow'
                    'memory-bank'
                    'microsoft-todo-tasks'
                    'outlook-calendar-export'
                    'outlook-email-export'
                    'pandoc-docx-export'
                    'pdf-to-markdown'
                    'pswritehtml-reporting'
                    'send-outlook-email'
                    'whisper-pyannote-transcription'
                    'windows-gui-screenshot-capture'
                    'xlsx-to-markdown'
                )
            }
        }
    }
}
