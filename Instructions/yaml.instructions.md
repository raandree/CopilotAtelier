---
applyTo: "**/*.yml,**/*.yaml"
---

# YAML Best Practices and Standards

## Core Principles

### What is YAML?
- **Y**AML **A**in't **M**arkup **L**anguage
- Human-readable data serialization format
- Superset of JSON (all JSON is valid YAML)
- Three basic data structures: mappings (hashes/dictionaries), sequences (arrays/lists), scalars (strings/numbers)

### Design Goals
- **Readable**: Easy for humans to read and write
- **Portable**: Works across programming languages
- **Expressive**: Supports complex data structures
- **Minimal**: Low syntax overhead

## File Conventions

### File Extension
- **Preferred**: `.yaml` (recommended by yaml.info and the YAML specification)
- **Alternative**: `.yml` (widely used, but `.yaml` is unambiguous)
- Be consistent within a project — pick one and stick with it

### Encoding
- Use **UTF-8** encoding for all YAML files
- Do not use a BOM (Byte Order Mark)

### Newline at End of File
- Always end YAML files with a single newline character
- yamllint enforces this via the `new-line-at-end-of-file` rule

### Line Endings
- Prefer UNIX-style line endings (`\n`)
- Avoid DOS-style (`\r\n`) unless your toolchain requires it
- yamllint `new-lines` rule can enforce this

## YAML Versions

### Version Directive
```yaml
# Explicitly declare the YAML version
%YAML 1.2
---
key: value
```

### Key Differences Between YAML 1.1 and 1.2

| Feature | YAML 1.1 | YAML 1.2 |
|---|---|---|
| Truthy values | `yes`, `no`, `on`, `off`, `y`, `n` are booleans | Only `true`, `false`, `True`, `False`, `TRUE`, `FALSE` |
| Octal notation | `0777` (leading zero) | `0o777` (explicit `0o` prefix) |
| Sexagesimals | `1:30` parsed as 90 | Treated as string |
| Slash escaping | `\/` is invalid | `\/` is valid (JSON compatibility) |

- **Recommendation**: Write YAML as if targeting 1.2 — use `true`/`false` (not `yes`/`no`), use `0o` for octals, and quote ambiguous values
- Many parsers (e.g., PyYAML) still default to YAML 1.1 behaviour — be aware of this when choosing a library

## Security Considerations

### Avoid Unsafe Deserialization
```python
# DANGEROUS — allows arbitrary code execution
data = yaml.load(file, Loader=yaml.FullLoader)

# SAFE — only permits basic YAML types
data = yaml.safe_load(file)
```

### Language-Specific Tags
```yaml
# These tags can execute arbitrary code in some parsers!
# NEVER accept untrusted YAML containing these:
malicious: !!python/object/apply:os.system ['rm -rf /']
also_bad: !!python/object:__main__.Exploit {}
```

- **Always** use `safe_load` / `SafeLoader` (Python), `YAML.safe_load` (Ruby), or equivalent safe APIs
- Never deserialize YAML from untrusted sources without sanitisation
- Disable custom tags and constructors in production environments
- Treat YAML like code — review it for injection risks in CI/CD pipelines

### Secrets Management
```yaml
# BAD — hardcoded secrets
database:
  password: SuperSecret123!

# GOOD — use environment variable references or external secret stores
database:
  password: ${DB_PASSWORD}
```

- Never commit secrets, tokens, or passwords in YAML files
- Use environment variables, vault references, or encrypted secret stores
- Add patterns like `*secret*`, `*password*`, `*token*` to `.gitignore` or use git-secrets

## Indentation Rules

### Use Spaces, Never Tabs
```yaml
# Correct - using 2 spaces
parent:
  child:
    grandchild: value

# Incorrect - using tabs
parent:
child:  # TAB characters will cause errors
grandchild: value
```

### Consistent Indentation Levels
- **Standard**: Use 2 spaces per indentation level (most common)
- **Alternative**: 4 spaces (less common, but acceptable if consistent)
- **NEVER mix**: Always use the same indentation width throughout a file

```yaml
# Good - consistent 2-space indentation
root:
  level1:
    level2:
      level3: value

# Bad - mixed indentation
root:
  level1:
      level2:  # 4 spaces instead of 2
    level3: value  # Back to 2 spaces
```

### Indentation for Lists
```yaml
# Correct - list items at same level as parent
items:
  - first
  - second
  - third

# Also correct - inline
items: [first, second, third]

# Nested lists
outer:
  - item1
  - item2
  - nested:
      - subitem1
      - subitem2
```

### Sequence Indentation Styles
The YAML specification allows two ways to indent sequences inside a mapping:

```yaml
# Style 1: Indented sequences (default, most common)
mapping:
  - item1
  - item2

# Style 2: Zero-indented sequences (the dash IS the indentation)
mapping:
- item1
- item2
```

- The YAML creators recommend zero-indented sequences, but **indented sequences are more widely used**
- Be consistent within a project — yamllint's `indent-sequences` option enforces this
- **Recommendation**: use indented sequences (Style 1) for clarity

## Mappings (Key-Value Pairs)

### Basic Syntax
```yaml
# Simple key-value
key: value
name: John Doe
age: 30

# Nested mappings
person:
  name: John Doe
  age: 30
  address:
    street: 123 Main St
    city: Springfield
```

### Key Naming Conventions
```yaml
# Preferred - lowercase with underscores (snake_case)
database_connection: localhost
max_retry_count: 3

# Also acceptable - camelCase
databaseConnection: localhost
maxRetryCount: 3

# Acceptable - kebab-case
database-connection: localhost
max-retry-count: 3

# Less readable - PascalCase (avoid unless required)
DatabaseConnection: localhost
MaxRetryCount: 3
```

### Explicit Keys (Complex Keys)
```yaml
# When keys contain special characters
? "key with spaces"
: value

? [complex, key]
: value

# Better: avoid complex keys when possible
key_with_underscores: value
```

## Sequences (Lists/Arrays)

### Block Style (Preferred for Readability)
```yaml
# Simple list
fruits:
  - apple
  - banana
  - orange

# List of mappings
users:
  - name: Alice
    role: admin
  - name: Bob
    role: user
```

### Flow Style (Compact)
```yaml
# Inline list
fruits: [apple, banana, orange]

# Inline mapping
user: {name: Alice, role: admin}

# Mixed
users: [{name: Alice, role: admin}, {name: Bob, role: user}]
```

### When to Use Each Style
- **Block style**: Use for multi-item lists, better readability
- **Flow style**: Use for short lists (1-3 items), or when space is limited

## Scalars (Strings, Numbers, Booleans)

### Strings

#### Unquoted Strings
```yaml
# Simple strings don't need quotes
name: John Doe
message: Hello World

# Be careful with special characters
# These need quotes:
special: "value: with colon"
numbers: "123"  # If you want it as string, not number
```

#### Quoted Strings
```yaml
# Single quotes - literal (no escape sequences)
message: 'This is a string'
escaped: 'Use '' for a single quote'

# Double quotes - allow escape sequences
message: "Line 1\nLine 2"  # \n creates newline
path: "C:\\Users\\Name"    # \\ for backslash
unicode: "Unicode: \u0041"  # \u for unicode
```

#### Multi-line Strings

##### Literal Block Scalar (Preserve newlines)
```yaml
# Pipe | preserves newlines
script: |
  #!/bin/bash
  echo "Line 1"
  echo "Line 2"
  echo "Line 3"

# Result: "#!/bin/bash\necho \"Line 1\"\necho \"Line 2\"\necho \"Line 3\"\n"
```

##### Folded Block Scalar (Join lines)
```yaml
# Greater-than > folds newlines into spaces
description: >
  This is a long description
  that spans multiple lines
  but will be joined into
  a single line.

# Result: "This is a long description that spans multiple lines but will be joined into a single line.\n"
```

##### Block Chomping
```yaml
# Default - keep final newline
text: |
  content

# Strip final newlines: |-
text: |-
  content

# Keep all final newlines: |+
text: |+
  content


```

#### When to Quote Strings
```yaml
# Must quote
colon_value: "value: with colon"
hash_value: "value # with hash"
at_value: "@value starting with @"
backtick_value: "`value with backticks"
boolean_string: "true"  # To prevent interpretation as boolean
number_string: "123"    # To prevent interpretation as number

# No need to quote
simple: value
with_spaces: this is fine
with-dashes: also-fine
with_underscores: also_fine
```

#### Characters Forbidden at the Start of a Plain Scalar
These characters require quoting when they appear as the first character:
- `!` (tag), `&` (anchor), `*` (alias)
- `-` followed by space (block sequence entry)
- `:` followed by space (block mapping entry)
- `?` followed by space (explicit mapping key)
- `{`, `}`, `[`, `]` (flow collection indicators)
- `,` (flow entry separator)
- `#` (comment), `|`, `>` (block scalars)
- `@`, `` ` `` (reserved characters)
- `"`, `'` (quote characters)
- `%` (directive indicator)

#### Character Sequences Forbidden Inside Plain Scalars
- `: ` (colon followed by space) — mapping separator
- ` #` (space followed by hash) — starts a comment
- In flow collections, also forbidden: `[`, `]`, `{`, `}`, `,`

### Numbers
```yaml
# Integers
integer: 42
negative: -17
octal: 0o14        # Octal notation
hexadecimal: 0x1A  # Hex notation

# Floats
float: 3.14159
scientific: 1.23e+3
infinity: .inf
not_a_number: .nan

# As strings (quoted)
version: "1.0"
port: "8080"
```

### Booleans
```yaml
# True values
enabled: true
enabled: True
enabled: TRUE
enabled: yes
enabled: Yes
enabled: on

# False values
disabled: false
disabled: False
disabled: FALSE
disabled: no
disabled: No
disabled: off

# Recommended: use lowercase true/false for clarity
recommended_true: true
recommended_false: false
```

### Null Values
```yaml
# Explicit null
value: null
value: Null
value: NULL
value: ~

# Empty value (also null)
value:

# Recommended: use null for clarity
recommended:
```

**Caution**: Empty values create implicit nulls that may cause unexpected behaviour. yamllint's `empty-values` rule can forbid these.

### Dates and Timestamps
```yaml
# YAML automatically parses ISO-formatted dates!
release: 2024-01-15           # Parsed as a date object, NOT a string
version: 1.0                  # Parsed as float 1.0, NOT string "1.0"
timestamp: 2024-01-15T10:30:00Z  # Parsed as datetime

# Quote to keep as strings
release: "2024-01-15"
version: "1.0"
```

- Be especially careful with version numbers — `1.0` becomes float, `1.10` becomes `1.1`
- Always quote values that look like dates or version numbers if you need strings
- yamllint's `quoted-strings` rule with `extra-required` can enforce quoting for patterns like dates

## Comments

### Single-line Comments
```yaml
# This is a comment
key: value  # Inline comment

# Multi-line comment block
# Line 1 of comment
# Line 2 of comment
key: value
```

### Comment Best Practices
```yaml
# Good - explain WHY, not WHAT
# Retry count increased due to network instability in production
max_retries: 5

# Bad - states the obvious
# This sets the max retries
max_retries: 5

# Section headers
# ============================================================
# Database Configuration
# ============================================================
database:
  host: localhost
  port: 5432
```

## Anchors and Aliases (DRY Principle)

### Basic Anchors and Aliases
```yaml
# Define anchor with &
defaults: &default_settings
  timeout: 30
  retries: 3

# Reference with *
development:
  <<: *default_settings
  host: dev.example.com

production:
  <<: *default_settings
  host: prod.example.com
  timeout: 60  # Override specific value
```

### Merge Keys
```yaml
# Base configuration
base: &base
  name: Base
  version: 1.0

# Merge and extend
extended:
  <<: *base
  description: Extended configuration
  version: 2.0  # Overrides base version

# Result of extended:
# name: Base
# version: 2.0
# description: Extended configuration
```

### Multiple Merges
```yaml
default_timeouts: &timeouts
  connect_timeout: 5
  read_timeout: 30

default_retries: &retries
  max_retries: 3
  retry_delay: 1

service:
  <<: [*timeouts, *retries]
  host: example.com
```

## Document Structure

### Single Document
```yaml
# Simple document
key: value
another: value
```

### Multiple Documents in One File
```yaml
---
# Document 1
name: First Document
value: 123
---
# Document 2
name: Second Document
value: 456
...
```

### Document Markers
```yaml
# --- marks document start (optional for single document)
---
content: here

# ... marks document end (optional)
...
```

## Common YAML Structures

### Configuration Files
```yaml
---
application:
  name: MyApp
  version: 1.0.0
  
database:
  host: localhost
  port: 5432
  credentials:
    username: admin
    password: secure_password
    
logging:
  level: info
  outputs:
    - console
    - file
  file:
    path: /var/log/app.log
    max_size: 10MB
```

### CI/CD Pipeline (Azure Pipelines / GitHub Actions)
```yaml
---
name: Build Pipeline

trigger:
  branches:
    include:
      - main
      - develop

stages:
  - stage: Build
    jobs:
      - job: BuildJob
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - task: PowerShell@2
            displayName: 'Run Tests'
            inputs:
              targetType: 'inline'
              script: |
                Invoke-Pester -Output Detailed
```

### Docker Compose
```yaml
---
version: '3.8'

services:
  web:
    image: nginx:latest
    ports:
      - "80:80"
    volumes:
      - ./html:/usr/share/nginx/html
    environment:
      - NGINX_HOST=localhost
      - NGINX_PORT=80
    depends_on:
      - db
      
  db:
    image: postgres:13
    environment:
      POSTGRES_PASSWORD: example
    volumes:
      - db-data:/var/lib/postgresql/data

volumes:
  db-data:
```

## Type Safety and Explicit Typing

### Explicit Type Tags
```yaml
# String (when ambiguous)
version: !!str 1.0
port: !!str 8080

# Integer
count: !!int 42

# Float
price: !!float 19.99

# Boolean
enabled: !!bool true

# Null
value: !!null

# Binary
picture: !!binary |
  R0lGODlhDAAMAIQAAP//9/X17unp5WZmZgAAAOfn515eXvPz7Y6OjuDg4J+fn5
```

### When to Use Explicit Types
- When the intended type might be ambiguous
- When interfacing with strongly-typed systems
- When you need to ensure a specific interpretation

### Sets
```yaml
# The set type uses ? for unique items
colours: !!set
  ? red
  ? green
  ? blue

# Equivalent to a mapping with null values
colours_equivalent:
  red: null
  green: null
  blue: null
```

## Best Practices Summary

### DO
- ✅ Use 2-space indentation consistently
- ✅ Use lowercase `true`/`false` for booleans
- ✅ Quote strings that contain special characters
- ✅ Use block style for lists (better readability)
- ✅ Add comments to explain WHY, not WHAT
- ✅ Use anchors and aliases to avoid repetition
- ✅ Keep lines under 100 characters when possible
- ✅ Use meaningful key names
- ✅ Validate YAML with a linter
- ✅ Use `---` at document start for multi-document files

### DON'T
- ❌ Never use tabs for indentation
- ❌ Don't mix indentation widths
- ❌ Don't over-use flow style (less readable)
- ❌ Don't use complex keys unless necessary
- ❌ Don't leave trailing whitespace
- ❌ Don't trust unquoted strings with special characters
- ❌ Don't use deprecated YAML 1.0/1.1 syntax
- ❌ Don't repeat configuration (use anchors instead)
- ❌ Don't use `yaml.load()` — always use `safe_load()` or equivalent
- ❌ Don't commit secrets, tokens, or passwords in YAML files
- ❌ Don't rely on `yes`/`no`/`on`/`off` as booleans — use `true`/`false`
- ❌ Don't leave version numbers unquoted (`1.0` → `"1.0"`)
- ❌ Don't use `.yml` and `.yaml` extensions interchangeably in the same project

## Common Pitfalls

### Pitfall 1: Unquoted Special Characters
```yaml
# Wrong - will cause parse error
message: Value: with colon

# Right
message: "Value: with colon"
```

### Pitfall 2: Indentation Errors
```yaml
# Wrong - inconsistent indentation
parent:
  child1: value
    child2: value  # Too much indentation

# Right
parent:
  child1: value
  child2: value
```

### Pitfall 3: Tab Characters
```yaml
# Wrong - contains tabs (invisible here but causes errors)
key:value

# Right - uses spaces
key: value
```

### Pitfall 4: Boolean/Number Confusion
```yaml
# Interpreted as boolean true
norway: no  # !!!

# Interpreted as string "no"
norway: "no"

# Interpreted as number
version: 1.0

# Interpreted as string "1.0"
version: "1.0"
```

### Pitfall 5: Trailing Colons
```yaml
# Wrong - missing space after colon
key:value

# Right
key: value
```

### Pitfall 6: Octal Number Interpretation
```yaml
# YAML 1.1: leading zero means octal!
file_mode: 0644   # Interpreted as decimal 420, not 644!
beijing_code: 010 # Interpreted as decimal 8, not 10!

# Fix: quote it
file_mode: "0644"
beijing_code: "010"

# YAML 1.2: only 0o prefix is octal
octal_value: 0o644  # Explicit octal
```

### Pitfall 7: Automatic Date Parsing
```yaml
# These are silently parsed as dates, not strings!
release: 2024-01-15      # Date object!
country_code: NO         # Boolean false in YAML 1.1! (Norway problem)

# Fix: quote them
release: "2024-01-15"
country_code: "NO"
```

### Pitfall 8: Empty Values as Implicit Null
```yaml
# These are all null, which may not be intended
name:
value:  # also null
list:
  -     # null item in list

# If you mean empty string, use quotes
name: ""
```

### Pitfall 9: Reserved Characters
```yaml
# @ and ` (backtick) are reserved — always quote
handle: "@username"
command: "`ls -la`"
```

### Pitfall 10: Merge Key Conflicts
```yaml
# The << merge key inserts ALL keys from the anchor.
# Existing keys in the mapping take precedence.
defaults: &defaults
  timeout: 30
  retries: 3

service:
  <<: *defaults
  timeout: 60  # Overrides the anchor's value (OK)
  # retries: 3 is silently inherited — document this!
```

## Validation and Linting

### Validate YAML Syntax
```yaml
# Use online validators:
# - https://www.yamllint.com/
# - https://yamlchecker.com/

# Or command-line tools:
# yamllint file.yaml
# python -c "import yaml; yaml.safe_load(open('file.yaml'))"
```

### YAMLLint Configuration
```yaml
# .yamllint
---
extends: default

rules:
  line-length:
    max: 120
    level: warning
  indentation:
    spaces: 2
    indent-sequences: true
  comments:
    min-spaces-from-content: 2
  truthy:
    allowed-values: ['true', 'false']
    check-keys: true
```

### YAMLLint Rules Reference
All available yamllint rules:

| Rule | Purpose |
|---|---|
| `anchors` | Forbid undeclared aliases, duplicated anchors, or unused anchors |
| `braces` | Control use/spacing of flow mappings `{ }` |
| `brackets` | Control use/spacing of flow sequences `[ ]` |
| `colons` | Enforce spacing around colons (0 before, 1 after) |
| `commas` | Enforce spacing around commas (0 before, 1 after) |
| `comments` | Require space after `#`, min spacing from content |
| `comments-indentation` | Force comments to be indented like surrounding content |
| `document-end` | Require or forbid `...` document end marker |
| `document-start` | Require or forbid `---` document start marker |
| `empty-lines` | Limit consecutive blank lines (default max 2) |
| `empty-values` | Forbid empty values that create implicit nulls |
| `float-values` | Require numeral before decimal, forbid NaN/Inf/scientific |
| `hyphens` | Control spacing after hyphens (max 1 space) |
| `indentation` | Enforce indentation width and sequence indentation style |
| `key-duplicates` | Prevent duplicate keys in mappings |
| `key-ordering` | Enforce alphabetical ordering of keys (optional) |
| `line-length` | Limit line length (default 80, with non-breakable-words exception) |
| `new-line-at-end-of-file` | Require trailing newline at end of file |
| `new-lines` | Enforce line ending type (`unix` or `dos`) |
| `octal-values` | Forbid implicit (`010`) or explicit (`0o10`) octal values |
| `quoted-strings` | Require/forbid quoting, enforce quote style |
| `trailing-spaces` | Forbid trailing whitespace on lines |
| `truthy` | Forbid ambiguous boolean values (`yes`, `no`, `on`, `off`) |

### Disabling YAMLLint Rules with Comments
```yaml
# Disable a specific rule for the next line
# yamllint disable-line rule:line-length
very_long_value: this line is intentionally over the limit because it contains a URL or similar content

# Disable a rule for a block
# yamllint disable rule:truthy
on: value  # Would normally trigger truthy warning
# yamllint enable rule:truthy

# Disable all rules for a line
# yamllint disable-line
anything: goes here
```

## Tool-Specific Conventions

### PowerShell (build.yaml for Sampler)
```yaml
---
BuildWorkflow:
  '.':
    - build
    - test

  build:
    - Clean
    - Build_Module_ModuleBuilder
    - Build_NestedModules_ModuleBuilder
    - Create_changelog_release_output

  test:
    - Pester_Tests_Stop_On_Fail
    - Pester_if_Code_Coverage_Under_Threshold

ModuleBuildTasks:
  Sampler:
    - '*.build.Sampler.ib.tasks'
```

### Azure Pipelines
```yaml
---
trigger:
  - main

pool:
  vmImage: 'windows-latest'

variables:
  buildConfiguration: 'Release'

steps:
  - task: PowerShell@2
    inputs:
      targetType: 'inline'
      script: Write-Host "Building..."
```

## Summary Checklist

- ✅ Use `.yaml` file extension consistently
- ✅ UTF-8 encoding, no BOM, UNIX line endings
- ✅ End every file with a single newline
- ✅ Spaces only, never tabs
- ✅ Consistent 2-space indentation throughout the file
- ✅ Quote strings containing special characters or reserved sequences
- ✅ Quote values that look like dates (`"2024-01-15"`), versions (`"1.0"`), or booleans (`"yes"`)
- ✅ Use lowercase `true`/`false` for booleans — never `yes`/`no`/`on`/`off`
- ✅ Use `null` explicitly instead of empty values
- ✅ Comment WHY, not WHAT
- ✅ Use anchors and aliases to avoid repetition (DRY)
- ✅ Use `---` document start marker; use `...` end marker in multi-document files
- ✅ Use `safe_load` / `SafeLoader` — never `yaml.load()` with untrusted input
- ✅ Never commit secrets, tokens, or passwords in YAML files
- ✅ Validate with yamllint before committing
- ✅ Enable `truthy` rule to catch ambiguous booleans
- ✅ Keep lines under 120 characters (80 preferred)
- ✅ Use block style for readability; flow style only for short inline structures
- ✅ Be explicit when ambiguous (use quotes or type tags)
- ✅ Use consistent key naming convention (snake_case preferred)
