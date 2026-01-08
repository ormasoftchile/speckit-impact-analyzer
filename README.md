# 📊 Spec-Kit Impact Analyzer

Measure the productivity impact of AI-assisted development using the Spec-Kit methodology.

## Features

- **Auto-detect project type** (VS Code extension, Astro, Next.js, React, Python, Rust, etc.)
- **Analyze git history** to estimate actual development time
- **Classify code** into Boilerplate / Glue / Core Logic
- **Calculate AI-assisted code percentage** and time savings
- **Generate portfolio dashboards** for multiple projects
- **Cross-platform** - works on macOS, Linux, and Windows (via WSL/Git Bash)

## Installation

### Option 1: npm (Recommended)

```bash
# Install globally
npm install -g speckit-impact-analyzer

# Or use npx without installing
npx speckit-impact-analyzer <project-path>
```

### Option 2: Clone from GitHub

```bash
# Clone the repo
git clone https://github.com/ormasoftchile/speckit-impact-analyzer.git
cd speckit-impact-analyzer

# Install dependencies
npm install

# Link for global use
npm link
```

### Requirements

- **Node.js 16+**
- **cloc** - `brew install cloc` (macOS) / `apt install cloc` (Linux) / `choco install cloc` (Windows)
- **jq** - `brew install jq` (macOS) / `apt install jq` (Linux) / `choco install jq` (Windows)  
- **yq** - `brew install yq` (macOS) / `pip install yq` / [Download](https://github.com/mikefarah/yq/releases)
- **Windows**: Requires WSL or Git Bash

## Quick Start

```bash
# 1. Initialize config for your project (auto-detects project type)
speckit-init /path/to/project

# 2. Review and adjust the generated impact-config.yaml
code /path/to/project/impact-config.yaml

# 3. Run the analysis
speckit-analyze /path/to/project

# 4. View the report
cat /path/to/project/IMPACT_REPORT.md
```

## Commands

### `speckit-init` - Generate Config

Auto-generates `impact-config.yaml` based on project structure:

```bash
speckit-init /path/to/project           # Auto-detect project type
speckit-init . -t vscode-extension      # Force project type
speckit-init . -n "My Cool Project"     # Override name
speckit-init . -f                       # Overwrite existing
```

**Supported project types:**
- `vscode-extension` - VS Code extensions
- `astro` - Astro websites
- `nextjs` - Next.js apps
- `react` - React apps
- `vue` - Vue.js apps
- `python` - Python projects
- `rust` - Rust projects
- `go` - Go projects
- `node` - Generic Node.js
- `generic` - Fallback

### `speckit-analyze` - Run Analysis

```bash
speckit-analyze /path/to/project        # Basic analysis
speckit-analyze /path/to/project -j     # Also output JSON metrics
speckit-analyze /path/to/project -v     # Verbose output
```

**Output files:**
- `IMPACT_REPORT.md` - Human-readable report
- `impact-metrics.json` - Machine-readable metrics (with `-j`)

### `speckit-portfolio` - Aggregate Projects

Combine multiple projects into a portfolio dashboard:

```bash
speckit-portfolio \
  project1/impact-metrics.json \
  project2/impact-metrics.json \
  project3/impact-metrics.json \
  -o PORTFOLIO_DASHBOARD.md
```

## Configuration

The `impact-config.yaml` file controls how the analyzer works:

```yaml
project:
  name: "My Project"
  type: "vscode-extension"

paths:
  source: "src/"
  tests: "test/"
  specs: "specs/"
  exclude:
    - "node_modules"
    - "dist"

# File classification (adjust for your project structure)
classification:
  boilerplate:
    - "extension.ts"
    - "types/**/*"
  glue_code:
    - "commands/**/*"
    - "utils/**/*"
  core_logic:
    - "conversion/**/*"
    - "parsers/**/*"

# Time multipliers (hours per 100 LoC without AI)
multipliers:
  boilerplate: 0.5
  glue_code: 1.5
  core_logic: 4.0

# AI assistance percentage by code type
ai_percent:
  boilerplate: 90   # Config/types are easy for AI
  glue_code: 70     # Standard patterns
  core_logic: 35    # Unique logic needs human design

# Git settings
git:
  session_gap_hours: 2
  exclude_authors:
    - "dependabot[bot]"

# Spec-Kit settings
speckit:
  enabled: true
  task_pattern: "(\\*\\*)?T[0-9]+"
```

## How It Works

### Time Estimation Model

1. **Count lines of code** using `cloc`
2. **Classify files** into Boilerplate, Glue, Core Logic
3. **Apply multipliers** to estimate manual coding time
4. **Compare with git history** for actual development time
5. **Calculate savings** based on AI assistance percentages

### Code Classification

| Type | Description | AI% | Time/100 LoC |
|------|-------------|-----|--------------|
| **Boilerplate** | Configs, types, manifests | 90% | 0.5h |
| **Glue Code** | Handlers, utilities, wiring | 70% | 1.5h |
| **Core Logic** | Unique algorithms, business rules | 35% | 4.0h |

### Git Session Detection

- Commits within 2 hours = single coding session
- 30-minute buffer added per session
- Bot commits excluded

## Example Output

```
═══════════════════════════════════════════════════════════════════════
  📊 Spec-Kit Impact Analyzer v1.0.0
═══════════════════════════════════════════════════════════════════════
  
  Results:
    • 1383 lines of code (55% AI-assisted)
    • 33.2h estimated manual time
    • 14.4h saved (43%)
    • 3.3x productivity gain
```

## License

MIT
