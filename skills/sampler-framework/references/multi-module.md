# Multi-Module Repositories

Extracted from `Skills/sampler-framework/SKILL.md` to keep the main skill body under Anthropic's 500-line budget.

## Contents

- Correct Structure
- Incorrect Structure (Nested Modules)
- GitVersion Tag Prefix for Multi-Module

When a single repository contains multiple modules, each module must have its own folder with a distinct, non-overlapping structure.

### Correct Structure

```text
GitRootFolder/
├── Module1/
│   ├── source/
│   ├── tests/
│   ├── build.yaml
│   └── ...
├── Module2/
│   ├── source/
│   ├── tests/
│   ├── build.yaml
│   └── ...
└── SomeModuleGroup/          # Not a module — just a grouping folder
    ├── GroupModule1/
    │   ├── source/
    │   └── ...
    └── GroupModule2/
        ├── source/
        └── ...
```

### Incorrect Structure (Nested Modules)

```text
GitRootFolder/
├── Module3/
│   ├── SubModule1/           # WRONG: modules nested inside modules
│   └── SubModule2/
└── Module3                   # WRONG: duplicate folder names
```

### GitVersion Tag Prefix for Multi-Module

Use the `tag-prefix` configuration in `GitVersion.yml` to differentiate versions per module:

```yaml
# Module1/GitVersion.yml
tag-prefix: 'Module1-v'
```

---

