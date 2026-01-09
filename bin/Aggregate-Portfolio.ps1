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

$VERSION = "1.0.0"

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
    Write-Host "Spec-Kit Portfolio Aggregator v$VERSION"
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
Write-Host "  📊 Spec-Kit Portfolio Aggregator v$VERSION (PowerShell Edition)" -ForegroundColor Cyan
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

$projectRows = @()

foreach ($file in $JsonFiles) {
    try {
        $data = Get-Content $file -Raw | ConvertFrom-Json
        
        $name = if ($data.project.name) { $data.project.name } else { "Unknown" }
        $type = if ($data.project.type) { $data.project.type } else { "unknown" }
        $loc = if ($data.code.total_loc) { $data.code.total_loc } else { 0 }
        $aiLoc = if ($data.ai_assisted.total_loc) { $data.ai_assisted.total_loc } else { 0 }
        $aiPct = if ($data.ai_assisted.percent) { $data.ai_assisted.percent } else { 0 }
        $estManual = if ($data.time.estimated_manual_hours) { $data.time.estimated_manual_hours } else { 0 }
        $saved = if ($data.time.estimated_saved_hours) { $data.time.estimated_saved_hours } else { 0 }
        $savedPct = if ($data.time.saved_percent) { $data.time.saved_percent } else { 0 }
        $actual = if ($data.time.actual_hours) { $data.time.actual_hours } else { 0 }
        $commits = if ($data.git.total_commits) { $data.git.total_commits } else { 0 }
        $specLines = if ($data.speckit.spec_lines) { $data.speckit.spec_lines } else { 0 }
        $tasks = if ($data.speckit.tasks_total) { $data.speckit.tasks_total } else { 0 }
        $tasksComplete = if ($data.speckit.tasks_complete) { $data.speckit.tasks_complete } else { 0 }
        
        # Test metrics
        $testLoc = if ($data.tests.loc) { $data.tests.loc } else { 0 }
        $testFiles = if ($data.tests.files) { $data.tests.files } else { 0 }
        $testSaved = if ($data.tests.saved_hours) { $data.tests.saved_hours } else { 0 }
        
        # Calculate productivity
        $productivity = "N/A"
        if ($actual -gt 0) {
            $grandEst = if ($data.grand_total.est_manual_hours) { $data.grand_total.est_manual_hours } else { $estManual }
            $productivity = "$([math]::Round($grandEst / $actual, 1))x"
        }
        
        # Add to totals
        $totalLoc += $loc
        $totalAiLoc += $aiLoc
        $totalEstManual += $estManual
        $totalSaved += $saved
        $totalActual += $actual
        $totalCommits += $commits
        $totalSpecLines += $specLines
        $totalTasks += $tasks
        $totalTasksComplete += $tasksComplete
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

$report = @"
# 📊 $Title

**Generated**: $dateGenerated  
**Projects Analyzed**: $projectCount  
**Analyzer Version**: $VERSION

---

## 🎯 Executive Summary

``````
╔════════════════════════════════════════════════════════════════════════╗
║                    AI-ASSISTED DEVELOPMENT IMPACT                       ║
╠════════════════════════════════════════════════════════════════════════╣
║  Total Projects:              $projectCount                                         ║
║  Source Lines of Code:        $totalLoc                                         ║
║  Test Lines of Code:          $totalTestLoc                                         ║
║  Combined LoC:                $grandTotalLoc                                        ║
║  AI-Assisted Code:            $totalAiLoc ($totalAiPct%)                            ║
║  ──────────────────────────────────────────────────────────────────── ║
║  Estimated Manual Time:       ${totalEstManual}h (source only)                     ║
║  Actual Development Time:     ${totalActual}h                                     ║
║  Time Saved (source):         ${totalSaved}h ($totalSavedPct%)                      ║
║  Time Saved (tests):          ${totalTestSaved}h                                    ║
║  Total Time Saved:            ${grandTotalSaved}h                                   ║
║  ──────────────────────────────────────────────────────────────────── ║
║  Average Productivity Gain:   $totalProductivity                                   ║
╚════════════════════════════════════════════════════════════════════════╝
``````

---

## 📈 Project Breakdown

| Project | LoC | AI-Assisted | Est. Manual | Actual | Time Saved | Productivity |
|---------|-----|-------------|-------------|--------|------------|--------------|
$projectRowsText
| **TOTAL** | **$totalLoc** (+$totalTestLoc test) | **$totalAiPct%** | **${totalEstManual}h** | **${totalActual}h** | **${totalSaved}h ($totalSavedPct%)** | **$totalProductivity** |

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

## 📊 Methodology Notes

### Estimation Model
- **Boilerplate** (90% AI): Extension manifests, type definitions, configs
- **Glue Code** (70% AI): Event handlers, utility functions, UI bindings  
- **Core Logic** (30% AI): Unique algorithms, business rules, complex parsing
- **Tests** (75% AI): Arrange-act-assert patterns, edge cases, mocks

### Time Multipliers (hours per 100 LoC without AI)
- Boilerplate: 0.5h (quick, repetitive)
- Glue Code: 1.5h (moderate complexity)
- Core Logic: 4.0h (requires design thinking)
- Tests: 1.5h (pattern-based, but thorough)

### Git Session Detection
- Commits within 2 hours grouped as single session
- 30-minute buffer added per session
- Bot commits excluded from analysis

---

*Generated by [Spec-Kit Impact Analyzer](https://github.com/ormasoftchile/speckit-impact-analyzer) v$VERSION*
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
