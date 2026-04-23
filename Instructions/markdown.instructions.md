---
applyTo: "**/*.md"
---

# Markdown Best Practices and Standards

## Core Principles

### What is Markdown?
- Lightweight markup language with plain text formatting syntax
- Created by John Gruber in 2004
- Designed to be easy to read and write
- Converts to HTML and other formats
- Multiple flavors: CommonMark, GitHub Flavored Markdown (GFM), etc.

### Design Philosophy
- **Readable**: Source should be as readable as rendered output
- **Simple**: Easy to learn and use
- **Portable**: Works across platforms and tools
- **Flexible**: Supports basic formatting and advanced features

## File Conventions

### File Extension
- Use `.md` for all Markdown files
- Rationale: shorter, more popular, no important conflicts with other extensions

### File Naming
- Use lowercase letters with hyphens to separate words
- Strip articles (`the`, `a`, `an`) from the start
- Base the filename on the document's top-level heading when practical
- Avoid consecutive hyphens, surrounding hyphens, or underscores

```markdown
<!-- Good -->
getting-started.md
api-reference.md
troubleshooting-guide.md

<!-- Bad -->
Getting Started.md
api_reference.md
the-getting-started-guide.md
getting--started-.md
```

### File Encoding and Newlines
- End every file with a single newline character (markdownlint MD047)
- Don't leave empty lines at the end of the file
- Use UTF-8 encoding

## Document Layout

Follow a consistent document structure:

```markdown
# Document Title

Short introduction (1-3 sentences providing a high-level overview).

## Topic

Content.

## Another Topic

More content.

## See Also

- [Related document](link)
```

### Layout Guidelines
- The first heading should be a level-one heading (`#`), ideally matching or closely matching the filename
- Follow the H1 with a brief introduction explaining what the document covers and who it is for
- Use a `## See Also` section at the bottom for miscellaneous links
- Prefer a single H1 that serves as the document title; all other headings should be H2 or deeper

## Character Line Limit

- Keep lines at or under 80 characters when practical
- **Exceptions** (these may exceed the limit):
  - Links and image references
  - Tables
  - Headings
  - Code blocks
- Wrap text before or after links when possible so surrounding text stays within 80 characters:

```markdown
<!-- Good: text before/after the link wraps, link itself may be long -->
*   See the
    [Markdown guide](https://example.com/markdown-style-guide)
    for more info.

<!-- Avoid: entire paragraph on one very long line -->
See the [Markdown guide](https://example.com/markdown-style-guide) for more info about writing good documentation with proper formatting.
```

- Rationale: consistent with code conventions, improves readability in editors and diffs

## Spelling and Capitalization

### Proper Names
- Preserve the original capitalization of product, project, and brand names
- Good: `GitHub`, `PowerShell`, `JavaScript`, `VS Code`
- Bad: `github`, `powershell`, `javascript`, `vs code`
- When in doubt, use the capitalization shown on the official website or Wikipedia

### Spelling
- Use correct American English spelling
- Use backticks or links around words you don't want spell checkers to flag (technical terms, paths, commands)
- Beware of case-sensitive abbreviations: `URL` not `url`, `API` not `Api`

### Informal Contractions
- In documentation, avoid informal abbreviations:
  - Good: repository, directory, documentation, configuration
  - Avoid: repo, dir, docs, config (unless they are actual folder/command names)

## Headings

### ATX-Style Headings (Preferred)
```markdown
# Heading 1
## Heading 2
### Heading 3
#### Heading 4
##### Heading 5
###### Heading 6
```

### Best Practices
- **Always** use a space after the `#` symbols
- Use only one H1 (`#`) per document (document title)
- Don't skip heading levels (go H1 → H2 → H3, not H1 → H3)
- Add blank lines before and after headings
- Headings must start at the beginning of the line (no indentation)

### Heading Case
- Use **sentence case**: capitalize the first letter; the rest follow normal sentence rules
- Exception: title case may be used for the document's top-level H1 (e.g., in a README)

```markdown
<!-- Good — sentence case -->
## Getting started with the module

<!-- Good — project title using title case for H1 only -->
# My Awesome Project

<!-- Bad — title case on every heading -->
## Getting Started With The Module
```

### Heading Punctuation
- **Don't** end headings with a colon `:`, period `.`, or semicolon `;`
- Question marks `?` are acceptable (FAQ-style documents)
- Keep headings short—use them as summaries, then explain below

```markdown
<!-- Good -->
# How to configure the module

<!-- Bad — trailing colon -->
# How to configure the module:

<!-- Bad — trailing period -->
# How to configure the module.
```

### Unique Heading Names
- Use unique, fully descriptive heading text so auto-generated anchor IDs are distinct and intuitive
- Avoid generic headings like "Summary" or "Example" repeated under different parents

```markdown
<!-- Bad — duplicate headings -->
## Foo
### Summary
### Example
## Bar
### Summary
### Example

<!-- Good — descriptive headings -->
## Foo
### Foo summary
### Foo example
## Bar
### Bar summary
### Bar example
```

```markdown
# Document Title

This is the introduction paragraph.

## Section One

Content for section one.

### Subsection 1.1

More detailed content.
```

### Setext-Style Headings (Alternative, Less Common)
```markdown
Heading 1
=========

Heading 2
---------
```

**Note**: ATX-style is preferred for consistency and clarity.

## Emphasis

### Bold
```markdown
**Bold text** using double asterisks
__Bold text__ using double underscores

Preferred: **bold**
```

### Italic
```markdown
*Italic text* using single asterisks
_Italic text_ using single underscores

Preferred: *italic*
```

### Bold and Italic
```markdown
***Bold and italic*** using triple asterisks
___Bold and italic___ using triple underscores
**_Mixed approach_**
*__Also mixed__*

Preferred: ***bold and italic***
```

### Best Practices
- Use asterisks (`*`) for consistency
- Don't use underscores in the middle of words
- Add spaces around emphasis for readability in source
- **No spaces inside emphasis markers** (markdownlint MD037)

```markdown
<!-- Good -->
This is **really** important.

<!-- Bad — spaces inside markers -->
This is ** really ** important.

<!-- Avoid - no spaces makes source harder to read -->
This is**really**important.
```

### Emphasis vs Headings
- **Never** use bold or italic text as a substitute for headings to introduce sections
- If text introduces a multi-line named section, use a proper heading (`##`, `###`, etc.)
- Headings provide document structure, enable navigation, and generate anchor links; emphasis does not

```markdown
<!-- Bad — using emphasis as a section title -->
**How to make omelets:**

Break an egg.

<!-- Good — use a heading -->
## How to make omelets

Break an egg.
```

## Lists

### Unordered Lists
```markdown
- Item 1
- Item 2
- Item 3

* Alternative using asterisks
* Item 2
* Item 3

+ Another alternative using plus
+ Item 2
+ Item 3

Preferred: Use dashes (-)
```

### Ordered Lists
```markdown
1. First item
2. Second item
3. Third item

<!-- Numbers can all be 1 (auto-numbered) -->
1. First item
1. Second item
1. Third item

<!-- But explicit numbering is preferred for clarity -->
1. First item
2. Second item
3. Third item
```

### Nested Lists
```markdown
1. First item
   - Nested bullet
   - Another nested bullet
2. Second item
   1. Nested number
   2. Another nested number
```

### Task Lists (GitHub Flavored Markdown)
```markdown
- [x] Completed task
- [ ] Incomplete task
- [ ] Another incomplete task
```

### Best Practices
- Use consistent markers (prefer `-` for unordered lists)
- Add blank lines before and after lists
- Indent nested items with 2 or 4 spaces (be consistent)
- For ordered lists, use sequential numbers for short lists; for long lists that may change, use all `1.` ("lazy numbering") so you don't have to renumber on every edit

```markdown
This is a paragraph.

- Item 1
- Item 2
  - Nested item 2.1
  - Nested item 2.2
- Item 3

This is another paragraph.
```

### List Item Case
- Each list item should have the same case it would have if concatenated with the preceding sentence
- If the list follows a heading (no lead-in sentence), capitalize the first letter

```markdown
<!-- Good — continues the sentence -->
I want to eat:

- apples
- bananas
- grapes

<!-- Good — follows a heading directly -->
## Ingredients

- Flour
- Sugar
- Butter
```

### List Item Punctuation
- If every item is a single short phrase, omit trailing periods
- If any item contains multiple sentences or starts with an uppercase letter, add periods to all items
- Non-period punctuation (`?`, `!`) is always kept regardless

```markdown
<!-- Good — short phrases, no periods -->
- apple
- banana
- orange

<!-- Good — full sentences, with periods -->
- Go to the market.
- Then buy some fruit. Check for freshness.
- Finally eat the fruit.

<!-- Good — uppercase start, with periods -->
- Get on top of the bike.
- Put your foot on the pedal.
- Push the pedal.
```

## Links

### Inline Links
```markdown
[Link text](https://www.example.com)
[Link with title](https://www.example.com "Title text")
```

### Reference Links
```markdown
[Link text][reference]
[Another link][ref2]

[reference]: https://www.example.com
[ref2]: https://www.example.com "Optional title"
```

### Automatic Links
```markdown
<https://www.example.com>
<email@example.com>
```

### Internal Links (Anchors)
```markdown
[Link to heading](#heading-id)

<!-- GitHub auto-generates IDs from headings -->
[Jump to Examples](#examples-section)
```

### Best Practices
- Use descriptive link text (not "click here", "here", "link", or "more")
- Use reference links for repeated URLs or long URLs that break readability
- Add titles for additional context
- **No spaces inside link text** (markdownlint MD039)
- URL-encode spaces (`%20`) and parentheses (`%28`, `%29`) in URLs for compatibility

```markdown
<!-- Good — descriptive link text -->
Read the [official documentation](https://docs.example.com) for details.
Check out the [style guide](/styleguide/docguide/style.html).

<!-- Bad — non-descriptive link text -->
[Click here](https://docs.example.com) for documentation.
See the Markdown guide for more info: [link](markdown.md).

<!-- Bad — spaces inside link brackets -->
[ a link ](https://www.example.com/)
```

### Reference Link Placement
- Place reference link definitions just before the next heading (after the section where they are first used)
- If a reference is used in multiple sections, define it at the end of the document
- Use reference links in tables to keep cell content short and readable

```markdown
## Section One

See the [Markdown guide][md-guide] for syntax details.

[md-guide]: https://www.markdownguide.org/

## Section Two

More content here.
```

### Path and URL Guidelines
- For links within the same project, use explicit relative paths (`path/to/page.md`), not full qualified URLs
- Avoid relative paths that go up multiple directories (`../../other/page.md`)—use absolute paths from the project root instead

## Images

### Inline Images
```markdown
![Alt text](path/to/image.png)
![Alt text](path/to/image.png "Image title")
```

### Reference Images
```markdown
![Alt text][image-reference]

[image-reference]: path/to/image.png "Optional title"
```

### Best Practices
- Always provide meaningful alt text for accessibility
- Use relative paths for images in the same repository
- Consider image size and optimization

```markdown
<!-- Good - descriptive alt text -->
![Screenshot of the application dashboard showing user statistics](./images/dashboard.png)

<!-- Avoid - non-descriptive alt text -->
![Image](./images/dashboard.png)
```

## Code

### Inline Code
```markdown
Use `inline code` for commands, variables, or short snippets.
Example: Run the `Get-Command` cmdlet.
```

### Code Blocks (Fenced)
````markdown
```
Plain code block without syntax highlighting
```

```powershell
# PowerShell code with syntax highlighting
Get-Process | Where-Object { $_.CPU -gt 100 }
```

```yaml
# YAML code with syntax highlighting
key: value
nested:
  item: value
```
````

### Code Blocks (Indented - Less Common)
```markdown
    Indent with 4 spaces for code block
    Another line of code
```

### Best Practices
- Always specify language for syntax highlighting in fenced code blocks
- Use fenced code blocks (```) instead of indented
- Escape backticks in inline code with double backticks
- **No spaces inside code span elements** (markdownlint MD038)

````markdown
<!-- Escaping backticks -->
Use ``code with `backticks` inside`` like this.
````

### What to Mark as Code
Use inline code or code blocks for:
- Executables and commands (e.g., `gcc`, `npm`, `Get-Process`)
- File paths and filenames (e.g., `src/index.ts`)
- Version numbers (e.g., `2.0.1`)
- Parameter and variable names (e.g., `$Name`, `--verbose`)
- Registry keys, environment variables, and other literals

**Don't** mark as code:
- Names of projects or products (e.g., PowerShell, GitHub, Linux)
- Names of libraries when referring to the project (e.g., React, jQuery)
- Use backticks to wrap text you want spell checkers to skip (e.g., `YourCustomTerm`)

### Use Code Span for Escaping
When you don't want text processed as Markdown (fake paths, example URLs), wrap it in backticks:

```markdown
An example shortlink: `docs/foo/bar.md`
An example query: `https://example.com/search?q=$TERM`
```

### Dollar Signs in Shell Code
Don't prefix shell commands with dollar signs `$` unless you are also showing the command's output in the same block. The `$` makes copy-paste harder and adds visual noise.

```markdown
<!-- Good — no dollar signs when output is not shown -->
```bash
echo "Hello"
ls -la
```

<!-- Good — dollar signs when showing output -->
```bash
$ echo "Hello"
Hello
$ ls -la
total 8
```

<!-- Bad — dollar signs with no output -->
```bash
$ echo "Hello"
$ ls -la
```
```

### Common Language Identifiers
```markdown
```bash        # Bash/Shell scripts
```powershell  # PowerShell
```python      # Python
```javascript  # JavaScript
```json        # JSON
```yaml        # YAML
```markdown    # Markdown
```csharp      # C#
```html        # HTML
```css         # CSS
```sql         # SQL
```
```

## Blockquotes

### Basic Blockquote
```markdown
> This is a blockquote.
> It can span multiple lines.
```

### Nested Blockquotes
```markdown
> First level
>> Second level
>>> Third level
```

### Blockquotes with Other Elements
```markdown
> ## Heading in Blockquote
>
> - List item 1
> - List item 2
>
> **Bold text** in blockquote.
```

### Best Practices
- Add blank line before and after blockquotes
- Use for quotes, notes, or callouts

```markdown
Regular paragraph.

> **Note**: This is an important note to remember.

Another paragraph.
```

## Horizontal Rules

### Creating Horizontal Rules
```markdown
---

***

___

Preferred: --- (three hyphens)
```

### Best Practices
- Add blank lines before and after horizontal rules
- Use three hyphens (`---`) for consistency
- Don't overuse - only for major section breaks

## Tables (GitHub Flavored Markdown)

### Basic Table
```markdown
| Header 1 | Header 2 | Header 3 |
|----------|----------|----------|
| Cell 1   | Cell 2   | Cell 3   |
| Cell 4   | Cell 5   | Cell 6   |
```

### Alignment
```markdown
| Left Aligned | Center Aligned | Right Aligned |
|:-------------|:--------------:|--------------:|
| Left         | Center         | Right         |
| Text         | Text           | Text          |
```

### Best Practices
- Align columns in source for readability
- Use alignment syntax when appropriate
- Keep tables simple - complex tables are hard to maintain
- Surround tables with blank lines (markdownlint MD058)
- Every row must have the same number of cells (markdownlint MD056)
- Use leading and trailing pipes on every row for compatibility

```markdown
| Command        | Description                          |
|:---------------|:-------------------------------------|
| `Get-Process`  | Gets running processes               |
| `Get-Service`  | Gets Windows services                |
| `Get-Command`  | Gets all available PowerShell cmdlets|
```

### Never Use ASCII Box Art for Structured Data
- **Never** use box-drawing characters (─, │, ┌, └, ├, ┤, etc.) inside code fences to represent tables, layered architectures, or numbered step lists
- ASCII box art is invisible to tools like pandoc — it exports as raw monospace text, not as a formatted table
- Use proper markdown tables or mermaid diagrams instead
- If the data is tabular (rows and columns), use a pipe table
- If the data is a flow or hierarchy, use a mermaid diagram (flowchart, graph, or gantt)

```markdown
<!-- WRONG — ASCII box art in a code fence, renders as monospace text in exports -->
```
┌─────────────────────────────────────┐
│  1. Init & Clean                    │
│     Remove previous build artifacts │
├─────────────────────────────────────┤
│  2. Resolve Dependencies            │
└─────────────────────────────────────┘
```

<!-- RIGHT — proper markdown table, renders as a formatted table everywhere -->
| Step | Phase | Description |
|:----:|-------|-------------|
| 1 | **Init & Clean** | Remove previous build artifacts |
| 2 | **Resolve Dependencies** | Download modules from PSGallery |
```

### When to Use Tables vs Lists
- **Use tables** when you have uniform tabular data with 2+ dimensions and many parallel items with distinct attributes
- **Use lists** when your data is mostly prose, uneven across rows, or only has one meaningful column
- Avoid tables where most cells are empty, or where one column contains long paragraphs
- Use reference links inside table cells to keep content short and manageable

```markdown
<!-- Good — tabular data benefits from table format -->
| Transport  | Favored by | Advantages     |
|------------|------------|----------------|
| Bicycle    | Commuters  | Eco-friendly   |
| Train      | Travelers  | Fast, reliable |

<!-- Better as a list — data is too irregular for a table -->
## Apple
- Juicy, firm, sweet
- Keeps doctors away

## Banana
- Convenient, soft
- 16 degrees average acute curvature
```

### Table Formatting Hacks
- Use `<br>` to create line breaks within a table cell
- Use HTML `<ul><li>` for lists within cells when necessary
- Use reference links to keep cell content compact

## Line Breaks and Paragraphs

### Paragraphs
```markdown
This is paragraph one.

This is paragraph two.
```

### Line Breaks
```markdown
Line one
Line two (two spaces at end of line one)

Or use a backslash\
Like this
```

### Best Practices
- Use blank lines to separate paragraphs
- Avoid trailing whitespace for line breaks—use a trailing backslash `\` or `<br>` instead, since trailing spaces are invisible and easily stripped by editors
- Don't add extra blank lines for spacing (markdownlint MD012 limits to 1)
- Best practice: avoid forced line breaks altogether; use separate paragraphs instead

## Escaping Characters

### Backslash Escapes
```markdown
\* Not italic \*
\# Not a heading
\[Not a link\]
\`Not code\`
```

### Characters That Can Be Escaped
```markdown
\   backslash
`   backtick
*   asterisk
_   underscore
{}  curly braces
[]  square brackets
()  parentheses
#   hash
+   plus
-   minus
.   dot
!   exclamation
```

## Extended Syntax (GitHub Flavored Markdown)

### Strikethrough
```markdown
~~Strikethrough text~~
```

### Emoji
```markdown
:smile: :heart: :thumbsup:
```

### Footnotes
```markdown
Here's a sentence with a footnote[^1].

[^1]: This is the footnote content.
```

### Definition Lists
```markdown
Term
: Definition of the term

Another term
: Another definition
```

### Automatic URL Linking
```markdown
GitHub automatically converts URLs to links:
https://www.example.com
```

### Disabling Automatic URL Linking
Wrap a URL in backticks to prevent it from being converted to a clickable link:

```markdown
`https://www.example.com`
```

### Heading IDs and Anchor Links
Many processors support custom heading IDs or auto-generate them from heading text:

```markdown
### My Great Heading {#custom-id}

[Link to heading](#custom-id)
```

GitHub's algorithm: lowercase → remove punctuation → spaces to dashes → URI-encode.

### Highlight, Subscript, and Superscript
Not universally supported; check your processor:

```markdown
==highlighted text==
H~2~O    (subscript)
X^2^     (superscript)
```

If unsupported, use HTML: `<mark>`, `<sub>`, `<sup>`.

## Comments in Markdown

Markdown has no native comment syntax. Use this widely-supported convention for hidden comments that don't appear in rendered output:

```markdown
[This is a comment that will be hidden.]: #
```

- Place blank lines before and after the comment
- Useful for leaving notes to future editors

## Admonitions

Use blockquotes with emoji and bold text to create note/warning/tip callouts:

```markdown
> :memo: **Note:** This is important information.

> :warning: **Warning:** Do not delete this file.

> :bulb: **Tip:** Use keyboard shortcuts to save time.
```

## Prefer Markdown Over HTML

- Use standard Markdown syntax wherever possible; avoid HTML hacks
- HTML reduces readability of the source, limits portability, and can break rendering in some processors
- Acceptable HTML uses:
  - `<br>` for line breaks inside table cells
  - `<img>` when you need to control image dimensions
  - `<details>`/`<summary>` for collapsible sections
  - `<sub>`, `<sup>` for sub/superscript when Markdown syntax is unsupported
- Inline Markdown (bold, italic, code) does **not** work inside block-level HTML tags like `<div>`, `<table>`, or `<p>`

## Best Practices Summary

### Document Structure
- ✅ Use one H1 per document (title)
- ✅ Follow logical heading hierarchy
- ✅ Add blank lines between sections
- ✅ Use consistent list markers
- ✅ Start lists and code blocks on new lines

### Formatting
- ✅ Use ATX-style headings (`#`)
- ✅ Use asterisks for emphasis (`*italic*`, `**bold**`)
- ✅ Use dashes for unordered lists (`-`)
- ✅ Use fenced code blocks with language specification
- ✅ Add alt text to all images

### Readability
- ✅ Keep lines under 100 characters when possible
- ✅ Use blank lines generously for visual separation
- ✅ Align table columns in source
- ✅ Use descriptive link text
- ✅ Write meaningful alt text for images

### Compatibility
- ✅ Test in target Markdown processor (GitHub, VS Code, etc.)
- ✅ Avoid processor-specific syntax when portability matters
- ✅ Use standard Markdown for maximum compatibility
- ✅ Document when using extended syntax

## Common Pitfalls

### Pitfall 1: Missing Blank Lines
```markdown
<!-- Wrong -->
# Heading
Content immediately after

<!-- Right -->
# Heading

Content with blank line after heading
```

### Pitfall 2: Incorrect List Indentation
```markdown
<!-- Wrong -->
- Item 1
 - Nested item (only 1 space)
- Item 2

<!-- Right -->
- Item 1
  - Nested item (2 spaces)
- Item 2
```

### Pitfall 3: Missing Language in Code Blocks
````markdown
<!-- Less useful -->
```
function Get-Data {
    # Code without syntax highlighting
}
```

<!-- Better -->
```powershell
function Get-Data {
    # Code with syntax highlighting
}
```
````

### Pitfall 4: Not Escaping Special Characters
```markdown
<!-- Wrong - will render as emphasis -->
File_name_with_underscores

<!-- Right -->
File\_name\_with\_underscores
```

### Pitfall 5: ASCII Box Art Instead of Tables
```markdown
<!-- Wrong — box-drawing characters in a code fence -->
<!-- Exports as ugly monospace text in Word/PDF, not a real table -->
```
┌────────────────────┐
│  Layer 1: CI/CD     │
├────────────────────┤
│  Layer 2: Build     │
└────────────────────┘
```

<!-- Right — use a markdown table or mermaid diagram -->
| Layer | Component |
|:-----:|----------|
| 1 | CI/CD |
| 2 | Build |
```

### Pitfall 6: Inconsistent Formatting
```markdown
<!-- Wrong - mixed emphasis syntax -->
This is *italic* and this is _also italic_.
This is **bold** and this is __also bold__.

<!-- Right - consistent syntax -->
This is *italic* and this is *also italic*.
This is **bold** and this is **also bold**.
```

## Documentation Organization and Structure

### Documentation Placement Requirements

#### Root README.md (Mandatory)
Every project **must** have a `README.md` file in the project root directory. This is the primary entry point for anyone discovering your project.

**Required Content:**
- **Project Title** - Clear, concise name of the project
- **Project Description** - Brief explanation of what the project does and why it exists
- **Installation Instructions** - How to install/setup the project
- **Getting Started** - Basic usage examples to help users start quickly
- **Optional but Recommended:**
  - Features list
  - Prerequisites
  - Configuration options
  - Examples section with common use cases
  - Contributing guidelines
  - License information
  - Links to detailed documentation

**When to Create:**
- At project initialization
- Before first commit
- If missing from an existing project, create immediately

#### Folder-Level README.md (Best Practice)
Each folder that serves a general purpose **should** have its own `README.md` file to explain:
- **Purpose** - Why this folder exists
- **Contents** - What type of files/modules belong here
- **Usage** - How to use or interact with the folder's contents
- **Structure** - Organization of files within the folder (if complex)
- **Examples** - Sample usage relevant to this folder's purpose

**When to Create Folder READMEs:**
- ✅ Source/module directories (`source/`, `src/`)
- ✅ Test directories (`tests/`, `test/`)
- ✅ Documentation directories (`docs/`, `documentation/`)
- ✅ Script directories (`scripts/`, `tools/`)
- ✅ Configuration directories (`config/`, `configs/`)
- ✅ Any folder with multiple subdirectories or complex structure
- ✅ Any folder that users or contributors will navigate to

**When Folder READMEs Are Optional:**
- ❌ Simple output/build directories
- ❌ Node_modules or dependency directories
- ❌ Temporary/cache directories
- ❌ Folders with obvious single purpose and few files

**Folder README Example:**
```markdown
# Tests

This folder contains all unit and integration tests for the module.

## Structure

- `general/` - Tests covering overall module compliance (PSScriptAnalyzer, help documentation)
- `functions/` - Function-specific tests organized by function name
- `integration/` - Integration tests for end-to-end scenarios

## Running Tests

Execute all tests:
\```powershell
.\tests\pester.ps1
\```

Run specific tests:
\```powershell
.\tests\pester.ps1 -Include "Get-Example.Tests.ps1"
\```

## Test Coverage

We aim for 80%+ code coverage. Each public function must have:
- Parameter validation tests
- Functional tests for all code paths
- Error handling tests
\```

### README Structure

#### Root README.md Template
```markdown
# Project Name

Brief description of the project.

## Features

- Feature 1
- Feature 2
- Feature 3

## Installation

\```powershell
Install-Module -Name ModuleName
\```

## Usage

\```powershell
Get-Example -Name 'Test'
\```

## Examples

### Example 1: Basic Usage
Description and code.

### Example 2: Advanced Usage
Description and code.

## Contributing

Guidelines for contributors.

## License

License information.
```

### Changelog Management Best Practices

#### When to Update the Changelog

**MANDATORY**: The changelog **must** be updated with **every** pull request that changes functionality, fixes bugs, adds features, or makes breaking changes.

**Update the changelog when:**
- ✅ Adding new features or functionality
- ✅ Changing existing behavior
- ✅ Fixing bugs or issues
- ✅ Making breaking changes
- ✅ Deprecating features
- ✅ Removing features
- ✅ Improving security
- ✅ Updating dependencies (if significant)

**Do NOT update for:**
- ❌ Documentation-only changes (README updates, comment changes)
- ❌ Code formatting/style changes with no functional impact
- ❌ CI/CD pipeline changes that don't affect the module
- ❌ Test-only changes (unless fixing test bugs)

#### Changelog Structure and Format

Follow the [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) format:

```markdown
# Change log for ProjectName

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- New feature description with context
- Links to relevant issues: [issue #123](https://github.com/owner/repo/issues/123)

### Changed
- Modified behavior description
- **BREAKING CHANGE**: Description of breaking change

### Deprecated
- Features that will be removed in future versions

### Removed
- **BREAKING CHANGE**: Removed feature description

### Fixed
- Bug fix description
- Fixes [Issue #456](https://github.com/owner/repo/issues/456)

### Security
- Security vulnerability fixes

## [1.0.0] - 2025-01-03

### Added
- Initial release with core features
```

#### Change Categories (Use Standard Headers)

Use these categories in this order:

1. **Removed** - For removed features (usually breaking changes)
2. **Added** - For new features
3. **Changed** - For changes in existing functionality
4. **Deprecated** - For soon-to-be removed features
5. **Fixed** - For bug fixes
6. **Security** - For security fixes

**Category Guidelines:**
- **Breaking Changes**: ALWAYS prefix with `BREAKING CHANGE:` and place under `Removed` or `Changed`
- **Issue References**: Link to GitHub issues using format `[issue #123](link)` or `Fixes [Issue #123](link)`
- **Resource/Component Name**: Start entries with the affected component/resource name
- **Be Descriptive**: Explain what changed and why, not just what was done

#### Example Changelog Entries

**Good Examples:**
```markdown
### Added
- SqlSetup
  - Added support for major version upgrade ([issue #1561](https://github.com/owner/repo/issues/1561)).
- New public command `Get-SqlDscDatabase` to retrieve database information.

### Changed
- **BREAKING CHANGE**: ScheduledTask
  - StartTime has changed the type from DateTime to String.
  - StartTime is now processed on the device, rather than at compile time.
    Fixes [Issue #148](https://github.com/owner/repo/issues/148).
- Updated minimum PowerShell version to 5.1.

### Fixed
- Computer
  - Fix Get-ComputerDomain function to retrieve the computer NETBIOS domain name
    instead of the user domain. Fixes [Issue #XXX](link).
```

**Bad Examples (Avoid):**
```markdown
### Changed
- Updated code  # Too vague
- Fixed bug  # Which bug? What component?
- Made improvements  # What improvements?
```

#### Version Consistency Requirements

**CRITICAL**: Ensure version numbers match across:
- Module manifest (`.psd1` file) - `ModuleVersion`
- Changelog.md - Version headers
- Git tags (if used)
- Release notes

**Version Format:**
- Use semantic versioning: `MAJOR.MINOR.PATCH`
- Include release date: `## [1.2.3] - 2025-01-03`
- Keep "Unreleased" section at top for work in progress

#### Audience Considerations

Write for your target audience:

**For IT Professional/Admin Modules:**
- Use plain language, avoid developer jargon
- Focus on what changed for the **user**, not implementation details
- Explain **impact** and **how to adapt** for breaking changes
- Provide examples when helpful

**What to Include:**
- ✅ "The `Name` parameter now accepts wildcards"
- ✅ "Fixed issue where service fails to start on Windows Server 2022"
- ✅ "BREAKING CHANGE: The default value for `Timeout` changed from 30 to 60 seconds"

**What to Avoid:**
- ❌ "Refactored internal helper function `Get-InternalState`"
- ❌ "Updated unit test mocks for better coverage"
- ❌ "Changed variable name from `$x` to `$result`"

#### Unreleased Section

**Always maintain an `[Unreleased]` section:**
- Place at the top of the changelog
- All PRs add entries here
- Remains until next version release
- Gets renamed to version number on release

```markdown
## [Unreleased]

### Added
- Feature being worked on

### Fixed
- Bug fix pending release
```

#### Release Process

When creating a new release:

1. **Rename `[Unreleased]`** section to the new version with date
2. **Create a new empty `[Unreleased]`** section at the top
3. **Verify version matches** module manifest
4. **Review all entries** for clarity and completeness
5. **Check all issue links** are valid

```markdown
# Change log for ProjectName

## [Unreleased]

## [2.0.0] - 2025-01-15

### Added
- New feature from unreleased

### Changed
- **BREAKING CHANGE**: Major change that was in unreleased
```

#### Quality Checklist for Changelog Entries

Before committing changelog updates:

- [ ] Entry is in the `[Unreleased]` section
- [ ] Entry uses the correct category (Added/Changed/Fixed/etc.)
- [ ] Breaking changes are clearly marked with `BREAKING CHANGE:`
- [ ] Component/resource name is included
- [ ] Description is clear and user-focused
- [ ] Related issue numbers are linked
- [ ] Entry ends with a period
- [ ] No internal/developer jargon used

#### Changelog Validation

**In CI/CD pipelines**, consider adding tests to verify:
- Changelog has been updated (for non-documentation PRs)
- Format follows Keep a Changelog standard
- Unreleased section exists
- Version numbers are valid semantic versions

Example test (conceptual):
```powershell
# Verify changelog was updated
$filesChanged | Should -Contain 'CHANGELOG.md' -Because 'the CHANGELOG.md must be updated with at least one entry in the Unreleased section for each PR'
```

### Module Documentation Pattern
```markdown
# Get-Example

## Synopsis
Brief description of the function.

## Syntax

\```powershell
Get-Example [-Name] <String> [[-Path] <String>] [<CommonParameters>]
\```

## Description
Detailed description of what the function does.

## Parameters

### -Name
Description of Name parameter.

- Type: String
- Required: Yes
- Position: 0

### -Path
Description of Path parameter.

- Type: String
- Required: No
- Position: 1

## Examples

### Example 1
\```powershell
Get-Example -Name 'Test'
\```

Description of what this example does.

## Inputs

- System.String

## Outputs

- System.Management.Automation.PSCustomObject

## Notes
Additional notes and information.
```

## Linting and Validation

### Markdownlint Rules
Common rules to follow:
- MD001: Heading levels should increment by one (no skipping H2 → H4)
- MD003: Heading style should be consistent (prefer `atx`)
- MD004: Unordered list style should be consistent (prefer `dash`)
- MD005: Consistent indentation for list items at the same level
- MD007: Unordered list indentation (2 spaces default)
- MD009: No trailing spaces (except for intentional line breaks)
- MD010: No hard tabs—use spaces
- MD011: No reversed link syntax (`(text)[url]` → `[text](url)`)
- MD012: No multiple consecutive blank lines (max 1)
- MD013: Line length (80 characters, with exceptions for links/tables/headings/code)
- MD014: Don't prefix shell commands with `$` unless showing output
- MD018: Space required after `#` in ATX headings
- MD019: Only one space after `#` (no multiple spaces)
- MD022: Headings should be surrounded by blank lines
- MD023: Headings must start at the beginning of the line
- MD024: No duplicate headings with the same content (use `siblings_only: true` for changelogs)
- MD025: Single top-level heading (one H1 per document)
- MD026: No trailing punctuation in headings (`.`, `;`, `:`, `!`)
- MD027: Only one space after blockquote `>` symbol
- MD028: No blank lines inside a blockquote (use `>` on blank lines)
- MD029: Ordered list item prefix (`one_or_ordered` style)
- MD031: Fenced code blocks should be surrounded by blank lines
- MD032: Lists should be surrounded by blank lines
- MD033: Avoid inline HTML (prefer pure Markdown)
- MD034: No bare URLs—wrap in angle brackets or use link syntax
- MD035: Horizontal rule style should be consistent (prefer `---`)
- MD036: Don't use emphasis (bold/italic) instead of a heading
- MD037: No spaces inside emphasis markers
- MD038: No spaces inside code span elements
- MD039: No spaces inside link text brackets
- MD040: Fenced code blocks should have a language specified
- MD041: First line should be a top-level heading
- MD042: No empty links (`[text]()`)
- MD044: Proper names should have correct capitalization
- MD045: Images should have alternate text (accessibility)
- MD046: Code block style should be consistent (prefer `fenced`)
- MD047: Files should end with a single newline character
- MD048: Code fence style should be consistent (prefer `backtick`)
- MD049: Emphasis style should be consistent (prefer `asterisk`)
- MD050: Strong style should be consistent (prefer `asterisk`)
- MD051: Link fragments should reference valid heading anchors
- MD055: Table pipe style should be consistent (prefer `leading_and_trailing`)
- MD056: Table column count must be consistent across all rows
- MD058: Tables should be surrounded by blank lines
- MD059: Link text should be descriptive (not "click here", "here", "link", "more")

### VS Code Extensions
- `markdownlint` - Linting and style checking
- `Markdown All in One` - Shortcuts and formatting
- `Markdown Preview Enhanced` - Enhanced preview

## Summary Checklist

- ✅ File uses `.md` extension with lowercase-hyphen naming
- ✅ File is UTF-8 encoded and ends with a single newline (MD047)
- ✅ Document follows title → intro → content → See Also layout
- ✅ Lines are ≤ 80 characters (except links, tables, headings, code)
- ✅ One H1 heading per document (MD025)
- ✅ Logical heading hierarchy (no skipped levels) (MD001)
- ✅ Headings use sentence case with no trailing punctuation (MD026)
- ✅ Heading names are unique and descriptive (MD024)
- ✅ Blank lines around headings, lists, code blocks, tables
- ✅ Consistent emphasis syntax (prefer asterisks) with no inner spaces (MD037)
- ✅ Emphasis is never used as a substitute for headings (MD036)
- ✅ Consistent list markers (prefer dashes) with proper indentation (MD005, MD007)
- ✅ List item case and punctuation are consistent
- ✅ Ordered lists use lazy numbering (`1.`) for maintainability
- ✅ Fenced code blocks with language specification (MD040)
- ✅ Shell code examples don't include `$` prompt (MD014)
- ✅ Descriptive link text (not "click here") and alt text on images (MD045, MD059)
- ✅ Reference links defined after first use, before next heading
- ✅ No bare URLs—wrapped in angle brackets or proper link syntax (MD034)
- ✅ No trailing spaces—use `\` for line breaks instead
- ✅ Escaped special characters where needed
- ✅ Tables aligned in source, used only for genuinely tabular data
- ✅ Markdown preferred over inline HTML (MD033)
- ✅ Proper names spelled and capitalised correctly (MD044)
- ✅ Tested in target Markdown processor
