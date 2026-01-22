<#
.SYNOPSIS
    Spec-Kit Portfolio Aggregator - PowerShell Edition
    Combine multiple impact-metrics.json files into an executive dashboard

.DESCRIPTION
    Aggregates metrics from multiple analyzed projects into a single
    portfolio dashboard showing combined AI development impact.

.PARAMETER JsonFiles
    Paths to impact-metrics.json files from analyzed projects

.PARAMETER OutputFile
    Output report path (default: PORTFOLIO_DASHBOARD.md)

.PARAMETER Title
    Dashboard title (default: "AI-Assisted Development Portfolio")

.EXAMPLE
    .\Aggregate-Portfolio.ps1 project1\impact-metrics.json project2\impact-metrics.json
    
.EXAMPLE
    .\Aggregate-Portfolio.ps1 -OutputFile portfolio.md -Title "My Projects" (Get-ChildItem *\impact-metrics.json)
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true, Position = 0)]
    [string[]]$JsonFiles,
    
    [Alias("o", "Output")]
    [string]$OutputFile = "PORTFOLIO_DASHBOARD.md",
    
    [Alias("t")]
    [string]$Title = "AI-Assisted Development Portfolio",
    
    [Alias("v")]
    [switch]$Version,
    
    [Alias("h")]
    [switch]$Help
)

$SCRIPT_VERSION = "1.0.0"

#region Utility Functions
function Write-Info { param([string]$Message) Write-Host "i " -ForegroundColor Blue -NoNewline; Write-Host $Message }
function Write-Success { param([string]$Message) Write-Host "√ " -ForegroundColor Green -NoNewline; Write-Host $Message }
function Write-Warn { param([string]$Message) Write-Host "! " -ForegroundColor Yellow -NoNewline; Write-Host $Message }
function Write-Err { param([string]$Message) Write-Host "X " -ForegroundColor Red -NoNewline; Write-Host $Message -ForegroundColor Red }
#endregion

if ($Help) {
    Get-Help $MyInvocation.MyCommand.Path -Full
    exit 0
}

if ($Version) {
    Write-Host "Spec-Kit Portfolio Aggregator v$SCRIPT_VERSION"
    exit 0
}

# Filter out any switches that might have leaked into JsonFiles
$JsonFiles = $JsonFiles | Where-Object { $_ -and $_ -notmatch '^-' }

if (-not $JsonFiles -or $JsonFiles.Count -eq 0) {
    Write-Err "At least one impact-metrics.json file is required"
    Write-Host ""
    Write-Host "Usage: .\Aggregate-Portfolio.ps1 [OPTIONS] <json_file1> <json_file2> [json_file3...]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -o, -OutputFile FILE    Output report path (default: PORTFOLIO_DASHBOARD.md)"
    Write-Host "  -t, -Title TEXT         Dashboard title"
    Write-Host "  -v, -Version            Show version"
    Write-Host "  -h, -Help               Show this help"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\Aggregate-Portfolio.ps1 project1\impact-metrics.json project2\impact-metrics.json"
    Write-Host "  .\Aggregate-Portfolio.ps1 -OutputFile portfolio.md *\impact-metrics.json"
    exit 1
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  📊 Spec-Kit Portfolio Aggregator v$SCRIPT_VERSION (PowerShell Edition)" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Validate all files exist
foreach ($file in $JsonFiles) {
    if (-not (Test-Path $file)) {
        Write-Err "File not found: $file"
        exit 1
    }
    Write-Info "Found: $file"
}

# Initialize totals
$totalLoc = 0
$totalAiLoc = 0
$totalEstManual = 0
$totalSaved = 0
$totalActual = 0
$totalCommits = 0
$totalSpecLines = 0
$totalTasks = 0
$totalTasksComplete = 0
$totalTestLoc = 0
$totalTestFiles = 0
$totalTestSaved = 0
$projectCount = $JsonFiles.Count

# Track unique specs paths to deduplicate (projects sharing same specs root)
$seenSpecsPaths = @{}

$projectRows = @()
$chartData = @()  # For mermaid charts

foreach ($file in $JsonFiles) {
    try {
        $data = Get-Content $file -Raw | ConvertFrom-Json
        
        $name = if ($data.project.name) { $data.project.name } else { "Unknown" }
        $type = if ($data.project.type) { $data.project.type } else { "unknown" }
        $loc = if ($data.code.total_loc) { $data.code.total_loc } else { 0 }
        $aiLoc = if ($data.ai_assisted.total_loc) { $data.ai_assisted.total_loc } else { 0 }
        $aiPct = if ($data.ai_assisted.percent) { $data.ai_assisted.percent } else { 0 }
        $estManual = if ($data.time.estimated_manual_hours) { $data.time.estimated_manual_hours } else { 0 }
        $saved = if ($data.time.saved_hours) { $data.time.saved_hours } else { 0 }
        $savedPct = if ($data.time.saved_percent) { $data.time.saved_percent } else { 0 }
        $actual = if ($data.time.actual_hours) { $data.time.actual_hours } else { 0 }
        $commits = if ($data.git.total_commits) { $data.git.total_commits } else { 0 }
        $specLines = if ($data.speckit.spec_lines) { $data.speckit.spec_lines } else { 0 }
        $tasks = if ($data.speckit.tasks_total) { $data.speckit.tasks_total } else { 0 }
        $tasksComplete = if ($data.speckit.tasks_complete) { $data.speckit.tasks_complete } else { 0 }
        $specsPath = if ($data.speckit.specs_path) { $data.speckit.specs_path } else { "" }
        
        # Test metrics
        $testLoc = if ($data.tests.loc) { $data.tests.loc } else { 0 }
        $testFiles = if ($data.tests.files) { $data.tests.files } else { 0 }
        $testSaved = if ($data.tests.saved_hours) { $data.tests.saved_hours } else { 0 }
        
        # Calculate productivity
        $productivity = "N/A"
        $productivityNum = 0
        if ($actual -gt 0) {
            $grandEst = if ($data.grand_total.est_manual_hours) { $data.grand_total.est_manual_hours } else { $estManual }
            $productivityNum = [math]::Round($grandEst / $actual, 1)
            $productivity = "${productivityNum}x"
        }
        
        # Store chart data
        $chartData += @{
            Name = $name
            ShortName = if ($name.Length -gt 15) { $name.Substring(0, 12) + "..." } else { $name }
            Loc = $loc
            Saved = $saved
            Productivity = $productivityNum
            AiPct = $aiPct
        }
        
        # Add to totals
        $totalLoc += $loc
        $totalAiLoc += $aiLoc
        $totalEstManual += $estManual
        $totalSaved += $saved
        $totalActual += $actual
        $totalCommits += $commits
        
        # Deduplicate speckit metrics: only count each specs_path once
        if ($specsPath -and -not $seenSpecsPaths.ContainsKey($specsPath)) {
            $seenSpecsPaths[$specsPath] = $true
            $totalSpecLines += $specLines
            $totalTasks += $tasks
            $totalTasksComplete += $tasksComplete
        } elseif (-not $specsPath -and $specLines -gt 0) {
            # Legacy: no specs_path but has spec data (pre-update JSON)
            $totalSpecLines += $specLines
            $totalTasks += $tasks
            $totalTasksComplete += $tasksComplete
        }
        # Note: if specsPath already seen, skip to avoid double-counting
        $totalTestLoc += $testLoc
        $totalTestFiles += $testFiles
        $totalTestSaved += $testSaved
        
        # Build row
        $testInfo = if ($testLoc -gt 0) { " (+$testLoc test)" } else { "" }
        $projectRows += "| **$name** | $loc$testInfo | $aiPct% | ${estManual}h | ${actual}h | ${saved}h ($savedPct%) | $productivity |"
        
        Write-Success "Processed: $name"
    }
    catch {
        Write-Err "Error processing $file : $_"
    }
}

# Calculate totals
$totalAiPct = if ($totalLoc -gt 0) { [math]::Floor($totalAiLoc * 100 / $totalLoc) } else { 0 }
$totalSavedPct = if ($totalEstManual -gt 0) { [math]::Floor($totalSaved * 100 / $totalEstManual) } else { 0 }
$grandTotalLoc = $totalLoc + $totalTestLoc
$grandTotalSaved = [math]::Round($totalSaved + $totalTestSaved, 1)
$totalProductivity = if ($totalActual -gt 0) { "$([math]::Round($totalEstManual / $totalActual, 1))x" } else { "N/A" }
$tasksPct = if ($totalTasks -gt 0) { [math]::Floor($totalTasksComplete * 100 / $totalTasks) } else { 0 }
$testToSourceRatio = if ($totalLoc -gt 0) { [math]::Floor($totalTestLoc * 100 / $totalLoc) } else { 0 }
$specToCodeRatio = if ($totalLoc -gt 0) { [math]::Round($totalSpecLines / $totalLoc, 2) } else { 0 }

$dateGenerated = Get-Date -Format "yyyy-MM-dd"

$projectRowsText = $projectRows -join "`n"

# Generate mermaid chart data
$pieChartLoc = ($chartData | ForEach-Object { "    `"$($_.ShortName)`" : $($_.Loc)" }) -join "`n"
$xAxisLabels = ($chartData | ForEach-Object { "`"$($_.ShortName)`"" }) -join ", "
$barChartSaved = ($chartData | ForEach-Object { $_.Saved }) -join ", "
$barChartProductivity = ($chartData | ForEach-Object { $_.Productivity }) -join ", "

# Format values with padding for aligned box
$boxWidth = 76
$labelColWidth = 28

function Format-BoxLine {
    param([string]$Label, [string]$Value)
    $paddedLabel = $Label.PadRight($labelColWidth)
    $content = "  ${paddedLabel}${Value}"
    $padding = $boxWidth - 2 - $content.Length
    if ($padding -lt 0) { $padding = 0 }
    return "║${content}$(' ' * $padding)║"
}

$topBorder    = "╔$('═' * ($boxWidth - 2))╗"
$midBorder    = "╠$('═' * ($boxWidth - 2))╣"
$botBorder    = "╚$('═' * ($boxWidth - 2))╝"
$dividerLine  = "║  $('─' * ($boxWidth - 6))  ║"

$titleText = "AI-ASSISTED DEVELOPMENT IMPACT"
$titlePadLeft = [math]::Floor(($boxWidth - 2 - $titleText.Length) / 2)
$titlePadRight = $boxWidth - 2 - $titleText.Length - $titlePadLeft
$titleLine = "║$(' ' * $titlePadLeft)${titleText}$(' ' * $titlePadRight)║"

$boxLine1 = Format-BoxLine "Total Projects:" "$projectCount"
$boxLine2 = Format-BoxLine "Source Lines of Code:" "$totalLoc"
$boxLine3 = Format-BoxLine "Test Lines of Code:" "$totalTestLoc"
$boxLine4 = Format-BoxLine "Combined LoC:" "$grandTotalLoc"
$boxLine5 = Format-BoxLine "AI-Assisted Code:" "$totalAiLoc ($totalAiPct%)"
$boxLine6 = Format-BoxLine "Estimated Manual Time:" "${totalEstManual}h (source only)"
$boxLine7 = Format-BoxLine "Actual Development Time:" "${totalActual}h"
$boxLine8 = Format-BoxLine "Time Saved (source):" "${totalSaved}h ($totalSavedPct%)"
$boxLine9 = Format-BoxLine "Time Saved (tests):" "${totalTestSaved}h"
$boxLine10 = Format-BoxLine "Total Time Saved:" "${grandTotalSaved}h"
$boxLine11 = Format-BoxLine "Average Productivity Gain:" "$totalProductivity"

$report = @"
# 📊 $Title

**Generated**: $dateGenerated  
**Projects Analyzed**: $projectCount  
**Analyzer Version**: $SCRIPT_VERSION

---

## 🎯 Executive Summary

``````
$topBorder
$titleLine
$midBorder
$boxLine1
$boxLine2
$boxLine3
$boxLine4
$boxLine5
$dividerLine
$boxLine6
$boxLine7
$boxLine8
$boxLine9
$boxLine10
$dividerLine
$boxLine11
$botBorder
``````

---

## 📈 Project Breakdown

| Project | LoC | AI-Assisted | Est. Manual | Actual | Time Saved | Productivity |
|---------|-----|-------------|-------------|--------|------------|--------------|
$projectRowsText
| **TOTAL** | **$totalLoc** (+$totalTestLoc test) | **$totalAiPct%** | **${totalEstManual}h** | **${totalActual}h** | **${totalSaved}h ($totalSavedPct%)** | **$totalProductivity** |

---

## 📊 Visual Breakdown

### Lines of Code by Project

``````mermaid
pie showData
    title Lines of Code Distribution
$pieChartLoc
``````

### Time Saved by Project (hours)

``````mermaid
xychart-beta
    title "Time Saved per Project (hours)"
    x-axis [$xAxisLabels]
    y-axis "Hours" 0 --> 200
    bar [$barChartSaved]
``````

### Productivity Multiplier by Project

``````mermaid
xychart-beta
    title "Productivity Gain (x faster than manual)"
    x-axis [$xAxisLabels]
    y-axis "Multiplier" 0 --> 35
    bar [$barChartProductivity]
``````

---

## 🧪 Test Code Summary

| Metric | Value |
|--------|-------|
| **Total Test Files** | $totalTestFiles |
| **Total Test LoC** | $totalTestLoc |
| **Test-to-Source Ratio** | $testToSourceRatio% |
| **Test Time Saved** | ${totalTestSaved}h |

> Tests are highly AI-friendly (75% AI-assisted by default) due to their predictable arrange-act-assert patterns.

---

## 📋 Spec-Kit Methodology Impact

| Metric | Value |
|--------|-------|
| **Total Specification Lines** | $totalSpecLines |
| **Total Tasks Defined** | $totalTasks |
| **Tasks Completed** | $totalTasksComplete ($tasksPct%) |
| **Total Commits** | $totalCommits |
| **Spec-to-Code Ratio** | ${specToCodeRatio}:1 |

---

## 🔍 Key Insights

### Time Efficiency
- **${grandTotalSaved}h saved** across $projectCount projects (${totalSaved}h source + ${totalTestSaved}h tests)
- Average productivity gain of **$totalProductivity** compared to traditional development
- AI assistance particularly effective for boilerplate, glue code, and tests (70-90% AI-assisted)

### Methodology Benefits
- Structured specifications enable focused AI prompts
- Task-based development provides clear checkpoints
- Spec-Kit templates accelerate project scaffolding
- Test generation highly AI-friendly due to predictable patterns

### Code Quality Maintained
- Complex core logic still requires human design (30-40% AI-assisted)
- AI excels at pattern application and repetitive code
- Human oversight essential for architecture decisions

---

## � Addendum: Metrics Glossary

This section provides detailed explanations for each metric used in this report.

### Executive Summary Metrics

| Metric | Description |
|--------|-------------|
| **Total Source LoC** | Total lines of code in the source directory, excluding blank lines and comments. Counted using built-in line counting. |
| **AI-Assisted LoC** | Estimated lines of code where AI tools (e.g., GitHub Copilot) significantly contributed to writing or suggesting the code. |
| **Estimated Manual Time** | Projected hours required to write this codebase without any AI assistance, based on industry-standard productivity multipliers. |
| **Estimated Time Saved** | Hours saved by using AI-assisted development, calculated as a percentage of the estimated manual time. |
| **Actual Dev Time** | Real development time estimated from git commit history, grouping commits into sessions separated by 2-hour gaps. |

### Code Category Metrics

| Metric | Description |
|--------|-------------|
| **Boilerplate** | Repetitive, structural code like entry points, type definitions, configuration schemas. High AI assistance potential (~90%). Multiplier: 0.5h/100 LoC. |
| **Glue Code** | Integration code connecting components: command handlers, event listeners, utility functions, UI bindings. Medium AI assistance (~70%). Multiplier: 1.5h/100 LoC. |
| **Core Logic** | Unique algorithms, business rules, and core functionality requiring human insight. Lower AI assistance (~30%). Multiplier: 4h/100 LoC. |
| **Files** | Count of source files in each category. |
| **LoC** | Lines of code (excluding blanks/comments) in each category. |
| **AI-Assisted** | Estimated lines where AI contributed, based on category-specific AI assistance percentages. |
| **Est. Manual** | Estimated hours to write code manually without AI, calculated as: ``LoC × Multiplier / 100``. |
| **Time Saved** | Hours saved by AI assistance, calculated as: ``Est. Manual × AI%``. |

### Test Code Metrics

| Metric | Description |
|--------|-------------|
| **Test Files** | Number of files in the test directory. |
| **Test LoC** | Lines of test code (excluding blanks/comments). |
| **Test-to-Code Ratio** | Percentage of test code relative to source code: ``(Test LoC / Source LoC) × 100``. |
| **AI-Assisted Test LoC** | Estimated test lines where AI contributed. Tests are highly amenable to AI generation due to predictable patterns. |
| **Est. Manual Test Time** | Hours to write tests manually, using multiplier: 1.5h/100 LoC. |
| **Test Time Saved** | Hours saved on test writing through AI assistance. |

### Development Timeline Metrics

| Metric | Description |
|--------|-------------|
| **First Commit** | Timestamp of the earliest commit in the repository. |
| **Last Commit** | Timestamp of the most recent commit. |
| **Total Commits** | Total number of commits in the repository history. |
| **Dev Sessions** | Number of development sessions, where a session is a group of commits separated by ≤2 hours. |
| **Estimated Active Hours** | Total estimated coding time, summing session durations with a 30-minute buffer per session. |

### Spec-Kit Metrics

| Metric | Description |
|--------|-------------|
| **Specification Lines** | Total lines in specification/design documents (Markdown files in specs directory). |
| **Specification Files** | Number of specification documents. |
| **Tasks Defined** | Count of tasks defined in specs using pattern ``- [ ] T###`` or ``- [x] T###``. |
| **Tasks Completed** | Count of completed tasks (marked with ``[x]``). |
| **Spec-to-Code Ratio** | Ratio of specification lines to source code lines, indicating planning thoroughness. |

### Grand Total Metrics

| Metric | Description |
|--------|-------------|
| **Lines of Code** | Combined source + test LoC. |
| **AI-Assisted** | Combined AI-assisted LoC from source and tests. |
| **Est. Manual Time** | Total estimated hours for source + test code without AI. |
| **Time Saved** | Total hours saved across source and test development. |

### Productivity Metrics

| Metric | Description |
|--------|-------------|
| **Productivity Multiplier** | Ratio of estimated manual time to actual development time: ``Est. Manual / Actual``. Higher values indicate greater productivity gains from AI assistance. |

### Configuration Parameters Used

| Parameter | Value | Description |
|-----------|-------|-------------|
| **Session Gap** | 2h | Time gap used to separate git commits into distinct development sessions. |
| **Boilerplate Multiplier** | 0.5h/100 LoC | Estimated manual coding time for boilerplate code. |
| **Glue Code Multiplier** | 1.5h/100 LoC | Estimated manual coding time for integration code. |
| **Core Logic Multiplier** | 4h/100 LoC | Estimated manual coding time for complex logic. |
| **Test Multiplier** | 1.5h/100 LoC | Estimated manual coding time for test code. |
| **AI % Boilerplate** | 90% | Estimated AI contribution to boilerplate code. |
| **AI % Glue Code** | 70% | Estimated AI contribution to glue code. |
| **AI % Core Logic** | 30% | Estimated AI contribution to core logic. |
| **AI % Tests** | 75% | Estimated AI contribution to test code. |

---

## 📚 References & Citations

The metrics and assumptions in this report are based on the following industry research and standards:

### AI-Assisted Development Productivity

1. **Peng, S., Kalliamvakou, E., Cihon, P., & Demirer, M. (2023)**. "The Impact of AI on Developer Productivity: Evidence from GitHub Copilot." *arXiv:2302.06590*. 
   - Key finding: Developers using GitHub Copilot completed tasks **55.8% faster** than the control group in a controlled experiment (P=.0017, 95% CI [21%, 89%]).
   - URL: https://arxiv.org/abs/2302.06590

2. **GitHub (2022)**. "Research: Quantifying GitHub Copilot's Impact on Developer Productivity and Happiness."
   - Key findings: 87% of developers reported AI preserves mental effort during repetitive tasks; 73% reported staying in flow.
   - URL: https://github.blog/news-insights/research/research-quantifying-github-copilots-impact-on-developer-productivity-and-happiness/

### Software Development Productivity Baselines

3. **McConnell, S. (2004)**. *Code Complete: A Practical Handbook of Software Construction*, 2nd Edition. Microsoft Press.
   - Industry reference for software construction best practices and productivity estimates.
   - Typical productivity ranges: 10-50 LoC/hour depending on complexity (Chapter 28: Managing Construction).

4. **Jones, C. (2007)**. *Estimating Software Costs: Bringing Realism to Estimating*, 2nd Edition. McGraw-Hill.
   - Provides industry benchmarks for software development productivity across different project types.

5. **COCOMO II Model (Boehm et al., 2000)**. *Software Cost Estimation with COCOMO II*. Prentice Hall.
   - The Constructive Cost Model provides effort estimation formulas based on project size and complexity factors.

### Methodology Notes

| Assumption | Basis | Citation |
|------------|-------|----------|
| **Time Multipliers** | Based on industry averages for TypeScript/JavaScript development, adjusted for VS Code extension complexity. | McConnell (2004), Jones (2007) |
| **AI Assistance % (Boilerplate: 90%)** | Repetitive code patterns show highest AI suggestion acceptance rates. | GitHub (2022), Peng et al. (2023) |
| **AI Assistance % (Glue: 70%)** | Integration code benefits significantly but requires more human judgment. | GitHub (2022) |
| **AI Assistance % (Core Logic: 30%)** | Complex algorithms require substantial human insight; AI assists with syntax/patterns. | Peng et al. (2023) |
| **AI Assistance % (Tests: 75%)** | Test code follows predictable patterns (arrange-act-assert); AI excels at generating edge cases. | GitHub (2022) |
| **55% Task Completion Speed Increase** | Controlled experiment with 95 professional developers. | Peng et al. (2023) |
| **Session Detection (2h gap)** | Standard assumption for development session boundaries in git analytics. | Industry practice |

> **Disclaimer**: Time estimates are approximations based on published research and industry benchmarks. Actual productivity varies significantly based on developer experience, problem domain, codebase familiarity, and tooling proficiency. AI assistance percentages are conservative estimates based on the types of code typically generated with AI pair programming tools.

---

*Generated by [Spec-Kit Impact Analyzer](https://github.com/ormasoftchile/speckit-impact-analyzer) v$SCRIPT_VERSION*
"@

$report | Out-File -FilePath $OutputFile -Encoding utf8
Write-Success "Portfolio dashboard saved: $OutputFile"

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  √ Portfolio Aggregation Complete" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "  Summary:"
Write-Host "    • $projectCount projects analyzed"
Write-Host "    • $totalLoc total lines of code"
Write-Host "    • ${totalSaved}h estimated time saved"
Write-Host "    • $totalProductivity average productivity gain"
Write-Host ""
Write-Host "  Output: $OutputFile"
Write-Host ""
