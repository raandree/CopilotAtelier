---
applyTo: "**/*.json,**/*.jsonc"
---

# JSON and JSONC Best Practices and Standards

## Core Specification

### JSON (RFC 8259)

- JSON is defined by [RFC 8259](https://www.rfc-editor.org/rfc/rfc8259)
- Valid data types: string, number, boolean (`true`/`false`), null, object, array
- Strings must use **double quotes** (`"` not `'`)
- No trailing commas after the last element
- No comments
- No undefined or NaN values
- Keys must be strings (double-quoted)

### JSONC (JSON with Comments)

- JSONC is a superset of JSON used by VS Code, TypeScript, ESLint, and other tools
- Supports single-line comments (`//`) and block comments (`/* */`)
- Supports trailing commas
- **Not standardized** — only use JSONC when the consuming tool explicitly supports it (e.g., VS Code `settings.json`, `tsconfig.json`)

```jsonc
// This is a JSONC file — comments are allowed
{
    "setting": "value", // inline comment
    "list": [
        "item1",
        "item2", // trailing comma is OK in JSONC
    ]
}
```

## File Conventions

### Encoding

- Use **UTF-8** encoding without BOM
- JSON specification requires UTF-8, UTF-16, or UTF-32; prefer UTF-8

### File Extension

- Use `.json` for standard JSON files
- Use `.jsonc` for files that require comments (VS Code supports this association)
- In VS Code, you can also set file associations to treat `.json` as JSONC:

```jsonc
"files.associations": {
    "*.json": "jsonc"
}
```

### Newline at End of File

- Always end JSON files with a single newline character
- Most formatters and linters enforce this

### Line Endings

- Prefer UNIX-style line endings (`\n`)
- Be consistent within a project

## Formatting

### Indentation

- Use **4 spaces** for indentation (aligns with PowerShell and VS Code defaults)
- **Never** use tabs
- Be consistent throughout the file

### Spacing

```json
{
    "key": "value",
    "number": 42,
    "nested": {
        "inner": true
    },
    "array": [
        "item1",
        "item2"
    ]
}
```

- Space after colon in key-value pairs: `"key": "value"` (not `"key":"value"`)
- No space before colon: `"key": "value"` (not `"key" : "value"`)
- Opening brace on the same line as the key
- Closing brace on its own line, aligned with the key's indentation level
- One key-value pair per line for objects with multiple keys
- One item per line for arrays with multiple items

### One-Line vs Multi-Line

```json
{
    "simple": { "key": "value" },
    "shortArray": [1, 2, 3],
    "longObject": {
        "firstName": "John",
        "lastName": "Doe",
        "email": "john@example.com"
    },
    "longArray": [
        "first item with some description",
        "second item with some description",
        "third item with some description"
    ]
}
```

- **One-line** objects and arrays: only for short, simple values (under 80 characters total)
- **Multi-line** for anything complex, nested, or longer than 80 characters

### Key Ordering

- **Alphabetical** ordering is preferred for configuration files
- **Logical grouping** is acceptable when alphabetical order would separate related keys
- Be consistent within a file — do not mix ordered and unordered sections

## Data Types

### Strings

```json
{
    "plain": "Hello, World!",
    "escaped": "Line 1\nLine 2",
    "unicode": "Emoji: \u2764",
    "path": "C:\\Users\\name\\file.txt",
    "url": "https://example.com/api?q=test&limit=10"
}
```

- Always use double quotes
- Escape special characters: `\"`, `\\`, `\/`, `\b`, `\f`, `\n`, `\r`, `\t`
- Use `\uXXXX` for Unicode characters
- Use forward slashes in paths when possible; escape backslashes when required

### Numbers

```json
{
    "integer": 42,
    "negative": -17,
    "float": 3.14,
    "scientific": 1.5e10,
    "zero": 0
}
```

- No leading zeros: `0.5` not `.5`
- No octal or hex notation (use decimal only)
- No `NaN`, `Infinity`, or `-Infinity`
- No trailing decimal point: `1.0` not `1.`

### Booleans and Null

```json
{
    "enabled": true,
    "disabled": false,
    "optional": null
}
```

- Use lowercase: `true`, `false`, `null`
- Prefer omitting a key over setting it to `null` unless the schema requires explicit null
- Do **not** use strings for booleans: `"true"` is not a boolean

## Common JSON File Patterns

### VS Code Settings (`settings.json`)

```jsonc
{
    // Editor settings
    "editor.fontSize": 14,
    "editor.tabSize": 4,
    "editor.formatOnSave": true,

    // File associations
    "files.associations": {
        "*.json": "jsonc"
    },

    // Extension settings
    "powershell.codeFormatting.preset": "OTBS"
}
```

### Package Manifests

```json
{
    "name": "my-package",
    "version": "1.0.0",
    "description": "A brief description",
    "main": "index.js",
    "scripts": {
        "build": "tsc",
        "test": "jest"
    },
    "dependencies": {},
    "devDependencies": {}
}
```

### Configuration Files

```json
{
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "properties": {
        "server": {
            "type": "object",
            "properties": {
                "host": { "type": "string", "default": "localhost" },
                "port": { "type": "integer", "minimum": 1, "maximum": 65535 }
            },
            "required": ["host", "port"]
        }
    }
}
```

## JSON Schema

### Always Declare Schema When Available

```json
{
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "title": "My Configuration",
    "type": "object"
}
```

- Use `$schema` to enable IntelliSense and validation in VS Code
- Reference published schemas when available (e.g., `https://schemastore.org`)
- Create custom schemas for project-specific configuration files

### VS Code Schema Association

```jsonc
// .vscode/settings.json
{
    "json.schemas": [
        {
            "fileMatch": ["config/*.json"],
            "url": "./schemas/config.schema.json"
        }
    ]
}
```

## PowerShell and JSON

### Reading JSON

```powershell
# Read and parse JSON
$config = Get-Content -Path 'config.json' -Raw | ConvertFrom-Json

# Access properties
$value = $config.server.host
```

### Writing JSON

```powershell
# Convert to JSON with proper depth
$config | ConvertTo-Json -Depth 10 | Set-Content -Path 'config.json' -Encoding UTF8

# Note: Default depth is 2 — ALWAYS specify -Depth for nested objects
```

**Critical**: `ConvertTo-Json` defaults to `-Depth 2`. Nested objects beyond depth 2 are converted to type name strings. Always specify a sufficient depth.

### Handling JSONC in PowerShell

PowerShell's `ConvertFrom-Json` does not support comments or trailing commas. Strip them before parsing:

```powershell
$jsonc = Get-Content -Path 'settings.json' -Raw

# Remove single-line comments
$jsonc = $jsonc -replace '(?m)^\s*//.*$', ''
$jsonc = $jsonc -replace '(?<=\S)\s*//.*$', ''

# Remove block comments
$jsonc = $jsonc -replace '/\*[\s\S]*?\*/', ''

# Remove trailing commas
$jsonc = $jsonc -replace ',\s*([\]}])', '$1'

$config = $jsonc | ConvertFrom-Json
```

## Validation

### Common Validation Rules

- **No duplicate keys**: JSON specification says behavior for duplicate keys is undefined. Avoid them.
- **Valid UTF-8**: Ensure all string values are valid UTF-8
- **Schema compliance**: Validate against the declared `$schema`
- **No BOM**: UTF-8 files should not include a byte order mark

### VS Code Validation

VS Code provides built-in JSON validation. Enable these settings:

```jsonc
{
    "json.validate.enable": true,
    "json.format.enable": true
}
```

## Security Considerations

### Sensitive Data

- **Never** store secrets, passwords, API keys, or tokens in JSON files checked into source control
- Use environment variables or secret management tools
- If a JSON file must contain sensitive placeholders, document them clearly:

```json
{
    "apiKey": "${API_KEY}",
    "connectionString": "${DB_CONNECTION}"
}
```

### Untrusted JSON

- Always validate and sanitize JSON from external sources
- Use schema validation before processing
- Be aware of JSON injection if constructing JSON from user input via string concatenation — always use proper serialization (e.g., `ConvertTo-Json`)

## Anti-Patterns

### String Concatenation for JSON Construction

```powershell
# BAD — fragile, vulnerable to injection
$json = '{"name": "' + $name + '", "value": ' + $value + '}'

# GOOD — use proper serialization
$json = @{ name = $name; value = $value } | ConvertTo-Json
```

### Insufficient Depth

```powershell
# BAD — nested objects truncated at depth 2
$config | ConvertTo-Json | Set-Content config.json

# GOOD — specify sufficient depth
$config | ConvertTo-Json -Depth 10 | Set-Content config.json
```

### Using Single Quotes

```json
// INVALID JSON
{'key': 'value'}

// VALID JSON
{"key": "value"}
```

### Trailing Commas in JSON

```json
// INVALID JSON (valid in JSONC only)
{
    "a": 1,
    "b": 2,
}

// VALID JSON
{
    "a": 1,
    "b": 2
}
```
