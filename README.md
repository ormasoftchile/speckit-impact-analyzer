# 📊 Spec-Kit Impact Analyzer

**Measure and showcase AI-assisted development impact using Spec-Kit + GitHub Copilot**

A scriptable toolkit to generate quantitative evidence of productivity gains from AI-assisted development workflows.

---

## 🎯 What This Does

Analyzes any Spec-Kit project to produce:

- **Time savings estimates** based on code classification
- **AI-assistance percentages** per code category
- **Development velocity metrics** from git history
- **Spec-Kit leverage metrics** (specs → code ratio)
- **Executive dashboard** for portfolio showcasing

## 📦 Installation

### Option 1: Clone as submodule (recommended)
```bash
cd your-project
git submodule add https://github.com/ormasoftchile/speckit-impact-analyzer .impact-analyzer
```

### Option 2: Copy scripts directly
```bash
cp -r speckit-impact-analyzer/bin your-project/scripts/impact
cp speckit-impact-analyzer/templates/impact-config.example.yaml your-project/impact-config.yaml
```

### Option 3: Run from anywhere
```bash
# Add to PATH
export PATH="$PATH:/path/to/speckit-impact-analyzer/bin"

# Run against any project
analyze-impact /path/to/your-project
```

## 🚀 Quick Start

```bash
# 1. Create config for your project
cp templates/impact-config.example.yaml /path/to/project/impact-config.yaml

# 2. Edit config to match your project structure
vim /path/to/project/impact-config.yaml

# 3. Run analysis
./bin/analyze-impact /path/to/project

# 4. View report
cat /path/to/project/IMPACT_REPORT.md
```

## 📋 Configuration

Create `impact-config.yaml` in your project root:

```yaml
project:
  name: "My VS Code Extension"
  type: "vscode-extension"

# File classification (glob patterns → category)
classification:
  boilerplate:
    - "src/extension.ts"
    - "src/types/**"
  glue_code:
    - "src/commands/**"
    - "src/utils/**"
  core_logic:
    - "src/core/**"

# Time multipliers (hours per 100 LoC without AI)
multipliers:
  boilerplate: 0.5
  glue_code: 1.5
  core_logic: 4.0

# AI assistance estimates
ai_percent:
  boilerplate: 90
  glue_code: 70
  core_logic: 30
```

## 📈 Output Example

```
═══════════════════════════════════════════════════════════════════════
📊 AI-ASSISTED DEVELOPMENT IMPACT REPORT
Project: DOCX to Markdown Converter
Generated: 2025-12-16
═══════════════════════════════════════════════════════════════════════

📈 CODE METRICS
────────────────────────────────────────────────────────────────────────
Category        │ Files │ LoC   │ AI-Assisted │ Est. Manual │ Saved
────────────────────────────────────────────────────────────────────────
Boilerplate     │   3   │  119  │   107 (90%) │    0.6h     │  0.5h
Glue Code       │   7   │  564  │   395 (70%) │    8.5h     │  5.9h
Core Logic      │   4   │  700  │   210 (30%) │   28.0h     │  8.4h
────────────────────────────────────────────────────────────────────────
TOTAL           │  14   │ 1383  │   712 (51%) │   37.1h     │ 14.8h

⏱️ TIME ANALYSIS
────────────────────────────────────────────────────────────────────────
Actual Development Time:     ~10 hours
Estimated Traditional Time:  37+ hours
Time Saved (Conservative):   27+ hours (73%)

📋 SPEC-KIT LEVERAGE
────────────────────────────────────────────────────────────────────────
Specification Lines:         2,392
Source Code Lines:           1,383
Spec-to-Code Ratio:          1.7:1
Tasks Defined:               130+
Test Coverage:               175 tests
═══════════════════════════════════════════════════════════════════════
```

## 🔧 Requirements

- `bash` 4.0+
- `cloc` — Line counting (`brew install cloc`)
- `jq` — JSON processing (`brew install jq`)
- `git` — Version control
- `yq` — YAML processing (`brew install yq`)

## 📁 Project Structure

```
speckit-impact-analyzer/
├── bin/
│   ├── analyze-impact          # Main entry point
│   └── aggregate-portfolio     # Portfolio aggregator
├── templates/
│   ├── impact-config.example.yaml
│   └── report-template.md
└── README.md
```

## 📊 Portfolio Aggregation

Combine multiple project reports into an executive dashboard:

```bash
./bin/aggregate-portfolio \
  -t "My VS Code Extensions" \
  -o PORTFOLIO_DASHBOARD.md \
  project1/impact-metrics.json \
  project2/impact-metrics.json \
  project3/impact-metrics.json
```

## 📖 Methodology

### Code Classification

| Category | Description | AI-Assisted % | Time Multiplier |
|----------|-------------|---------------|-----------------|
| **Boilerplate** | Manifests, configs, type definitions | 90% | 0.5h/100 LoC |
| **Glue Code** | Event handlers, UI bindings, utilities | 70% | 1.5h/100 LoC |
| **Core Logic** | Unique algorithms, business rules | 30% | 4.0h/100 LoC |

### Time Calculation

```
Estimated_Manual_Time = Σ (LoC_category × multiplier_category / 100)
AI_Assisted_LoC = Σ (LoC_category × ai_percent_category / 100)
Time_Saved = Estimated_Manual_Time × (AI_Assisted_LoC / Total_LoC)
```

### Git Session Detection

Development time estimated from commits:
- Commits within 2 hours = same session
- Gap > 2 hours = new session
- Session time = last_commit - first_commit + 30min buffer

## 🤝 Contributing

PRs welcome! Areas for improvement:
- [ ] Complexity analysis integration (ts-complex, plato)
- [ ] Multi-language support
- [ ] Portfolio aggregation across repos
- [ ] GitHub Actions integration

## 📄 License

MIT
