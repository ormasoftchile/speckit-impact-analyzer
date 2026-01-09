<#
.SYNOPSIS
    Spec-Kit Impact Analyzer - PowerShell Edition
    Measure and showcase AI-assisted development impact

.DESCRIPTION
    Analyzes a project directory to calculate AI-assisted development metrics
    including code classification, time savings, and development timeline.

.PARAMETER ProjectPath
    Path to the project directory (default: current directory)

.PARAMETER ConfigFile
    Path to config file (default: impact-config.yaml)

.PARAMETER OutputFile
    Output report path (default: IMPACT_REPORT.md)

.PARAMETER Json
    Also output JSON metrics

.PARAMETER Quiet
    Suppress progress output

.EXAMPLE
    .\Analyze-Impact.ps1
    
.EXAMPLE
    .\Analyze-Impact.ps1 -ProjectPath C:\MyProject -Json
#>

[CmdletBinding()]
param(
    [string]$ProjectPath = (Get-Location).Path,
    [Alias("c", "Config")]
    [string]$ConfigFile = "impact-config.yaml",
    [Alias("o", "Output")]
    [string]$OutputFile = "IMPACT_REPORT.md",
    [Alias("j")]
    [switch]$Json,
    [Alias("q")]
    [switch]$Quiet,
    [Alias("v")]
    [switch]$Version,
    [Alias("h")]
    [switch]$Help
)

$VERSION = "1.0.0"

#region Utility Functions
function Write-Info { param([string]$Message) if (-not $Quiet) { Write-Host "i " -ForegroundColor Blue -NoNewline; Write-Host $Message } }
function Write-Success { param([string]$Message) if (-not $Quiet) { Write-Host "√ " -ForegroundColor Green -NoNewline; Write-Host $Message } }
function Write-Warn { param([string]$Message) if (-not $Quiet) { Write-Host "! " -ForegroundColor Yellow -NoNewline; Write-Host $Message } }
function Write-Err { param([string]$Message) Write-Host "X " -ForegroundColor Red -NoNewline; Write-Host $Message -ForegroundColor Red }
function Write-Header { param([string]$Message) if (-not $Quiet) { Write-Host "`n$Message" -ForegroundColor Cyan } }
#endregion

#region Configuration
function Get-DefaultConfig {
    return @{
        ProjectName = (Split-Path $ProjectPath -Leaf)
        ProjectType = "unknown"
        SourceDir = "src"
        TestDir = "test"
        SpecsDir = "specs"
        ExcludeDirs = @("node_modules", "out", "dist", ".vscode-test", "coverage", "__pycache__", "bin", "obj")
        MultBoilerplate = 0.5
        MultGlue = 1.5
        MultLogic = 4.0
        MultTest = 1.5
        AiBoilerplate = 90
        AiGlue = 70
        AiLogic = 30
        AiTest = 75
        SessionGapHours = 2
        SpeckitEnabled = $true
    }
}

function Read-YamlConfig {
    param([string]$Path)
    
    $config = Get-DefaultConfig
    
    if (-not (Test-Path $Path)) {
        Write-Warn "Config file not found: $Path - using defaults"
        return $config
    }
    
    Write-Info "Loading config: $Path"
    
    try {
        $content = Get-Content $Path -Raw
        
        # Simple YAML parsing for our known structure
        $lines = $content -split "`n" | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*#' }
        
        $currentSection = ""
        foreach ($line in $lines) {
            if ($line -match '^(\w+):') {
                $currentSection = $Matches[1]
            }
            elseif ($line -match '^\s+(\w+):\s*(.+)$') {
                $key = $Matches[1]
                $value = $Matches[2].Trim().Trim('"').Trim("'")
                
                switch ($currentSection) {
                    "project" {
                        if ($key -eq "name") { $config.ProjectName = $value }
                        if ($key -eq "type") { $config.ProjectType = $value }
                    }
                    "paths" {
                        if ($key -eq "source") { $config.SourceDir = $value.TrimEnd('/\') }
                        if ($key -eq "tests") { $config.TestDir = $value.TrimEnd('/\') }
                        if ($key -eq "specs") { $config.SpecsDir = $value.TrimEnd('/\') }
                    }
                    "multipliers" {
                        if ($key -eq "boilerplate") { $config.MultBoilerplate = [double]$value }
                        if ($key -eq "glue_code") { $config.MultGlue = [double]$value }
                        if ($key -eq "core_logic") { $config.MultLogic = [double]$value }
                        if ($key -eq "tests") { $config.MultTest = [double]$value }
                    }
                    "ai_percent" {
                        if ($key -eq "boilerplate") { $config.AiBoilerplate = [int]$value }
                        if ($key -eq "glue_code") { $config.AiGlue = [int]$value }
                        if ($key -eq "core_logic") { $config.AiLogic = [int]$value }
                        if ($key -eq "tests") { $config.AiTest = [int]$value }
                    }
                    "git" {
                        if ($key -eq "session_gap_hours") { $config.SessionGapHours = [int]$value }
                    }
                    "speckit" {
                        if ($key -eq "enabled") { $config.SpeckitEnabled = $value -eq "true" }
                    }
                }
            }
        }
    }
    catch {
        Write-Warn "Error parsing config: $_"
    }
    
    return $config
}
#endregion

#region Code Metrics
function Get-CodeFiles {
    param(
        [string]$Path,
        [string[]]$ExcludeDirs,
        [string[]]$Extensions = @("*.ts", "*.js", "*.tsx", "*.jsx", "*.py", "*.cs", "*.go", "*.rs", "*.java", "*.vue", "*.svelte", "*.astro")
    )
    
    if (-not (Test-Path $Path)) { return @() }
    
    $excludePattern = $ExcludeDirs -join '|'
    
    Get-ChildItem -Path $Path -Recurse -Include $Extensions -File |
        Where-Object { $_.FullName -notmatch $excludePattern }
}

function Measure-FileMetrics {
    param([string]$FilePath)
    
    $content = Get-Content $FilePath -ErrorAction SilentlyContinue
    if (-not $content) { return @{ Code = 0; Comments = 0; Blank = 0 } }
    
    $blank = 0
    $comments = 0
    $code = 0
    $inBlockComment = $false
    
    foreach ($line in $content) {
        $trimmed = $line.Trim()
        
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            $blank++
        }
        elseif ($inBlockComment) {
            $comments++
            if ($trimmed -match '\*/') { $inBlockComment = $false }
        }
        elseif ($trimmed -match '^/\*') {
            $comments++
            if ($trimmed -notmatch '\*/') { $inBlockComment = $true }
        }
        elseif ($trimmed -match '^(//|#|--|\*)') {
            $comments++
        }
        else {
            $code++
        }
    }
    
    return @{ Code = $code; Comments = $comments; Blank = $blank }
}

function Get-CodeMetrics {
    param(
        [string]$SourcePath,
        [string[]]$ExcludeDirs
    )
    
    Write-Header "📊 Collecting Code Metrics"
    
    if (-not (Test-Path $SourcePath)) {
        Write-Warn "Source directory not found: $SourcePath"
        return @{ TotalLoc = 0; TotalFiles = 0; TotalComments = 0; TotalBlank = 0; Files = @() }
    }
    
    $files = Get-CodeFiles -Path $SourcePath -ExcludeDirs $ExcludeDirs
    $totalLoc = 0
    $totalComments = 0
    $totalBlank = 0
    $fileMetrics = @()
    
    foreach ($file in $files) {
        $metrics = Measure-FileMetrics -FilePath $file.FullName
        $totalLoc += $metrics.Code
        $totalComments += $metrics.Comments
        $totalBlank += $metrics.Blank
        
        $fileMetrics += @{
            Path = $file.FullName
            RelativePath = $file.FullName.Replace($ProjectPath, "").TrimStart('\', '/')
            Code = $metrics.Code
            Comments = $metrics.Comments
            Blank = $metrics.Blank
        }
    }
    
    Write-Success "Found $($files.Count) files with $totalLoc lines of code"
    
    return @{
        TotalLoc = $totalLoc
        TotalFiles = $files.Count
        TotalComments = $totalComments
        TotalBlank = $totalBlank
        Files = $fileMetrics
    }
}

function Get-TestMetrics {
    param(
        [string]$TestPath,
        [string[]]$ExcludeDirs,
        [int]$TotalLoc
    )
    
    Write-Header "🧪 Collecting Test Metrics"
    
    if (-not (Test-Path $TestPath)) {
        Write-Warn "Test directory not found: $TestPath"
        return @{ TestLoc = 0; TestFiles = 0; TestComments = 0; TestRatio = 0 }
    }
    
    $testExcludes = $ExcludeDirs + @("coverage", "__snapshots__")
    $files = Get-CodeFiles -Path $TestPath -ExcludeDirs $testExcludes
    $testLoc = 0
    $testComments = 0
    
    foreach ($file in $files) {
        $metrics = Measure-FileMetrics -FilePath $file.FullName
        $testLoc += $metrics.Code
        $testComments += $metrics.Comments
    }
    
    $testRatio = if ($TotalLoc -gt 0) { [math]::Round(($testLoc * 100) / $TotalLoc, 2) } else { 0 }
    
    Write-Success "Found $($files.Count) test files with $testLoc lines of test code ($testRatio% of source)"
    
    return @{
        TestLoc = $testLoc
        TestFiles = $files.Count
        TestComments = $testComments
        TestRatio = $testRatio
    }
}

function Get-FileClassification {
    param([string]$RelativePath)
    
    # Boilerplate patterns
    if ($RelativePath -match '(extension\.(ts|js)|types[/\\]|config[/\\]|\.d\.ts|config\.(ts|js)|layouts[/\\]|interfaces[/\\])') {
        return "Boilerplate"
    }
    
    # Glue code patterns
    if ($RelativePath -match '(commands[/\\]|utils[/\\]|webview[/\\]|handlers[/\\]|components[/\\]|pages[/\\]|hooks[/\\]|services[/\\])') {
        return "Glue"
    }
    
    # Default to core logic
    return "Logic"
}

function Get-ClassifiedMetrics {
    param([array]$FileMetrics)
    
    Write-Header "🏷️  Classifying Files"
    
    $boilerplateLoc = 0; $boilerplateFiles = 0
    $glueLoc = 0; $glueFiles = 0
    $logicLoc = 0; $logicFiles = 0
    
    foreach ($file in $FileMetrics) {
        $classification = Get-FileClassification -RelativePath $file.RelativePath
        
        switch ($classification) {
            "Boilerplate" { $boilerplateLoc += $file.Code; $boilerplateFiles++ }
            "Glue" { $glueLoc += $file.Code; $glueFiles++ }
            "Logic" { $logicLoc += $file.Code; $logicFiles++ }
        }
    }
    
    Write-Success "Classified: Boilerplate=$boilerplateFiles, Glue=$glueFiles, Logic=$logicFiles files"
    
    return @{
        Boilerplate = @{ Loc = $boilerplateLoc; Files = $boilerplateFiles }
        Glue = @{ Loc = $glueLoc; Files = $glueFiles }
        Logic = @{ Loc = $logicLoc; Files = $logicFiles }
    }
}
#endregion

#region Git Analysis
function Get-GitTimeline {
    param([int]$SessionGapHours = 2)
    
    Write-Header "⏱️  Analyzing Git Timeline"
    
    $gitDir = Join-Path $ProjectPath ".git"
    if (-not (Test-Path $gitDir)) {
        Write-Warn "Not a git repository"
        return @{
            FirstCommit = ""
            LastCommit = ""
            TotalCommits = 0
            EstimatedHours = 0
            SessionCount = 0
        }
    }
    
    Push-Location $ProjectPath
    try {
        $commits = git log --format="%ai" 2>$null
        if (-not $commits) {
            return @{ FirstCommit = ""; LastCommit = ""; TotalCommits = 0; EstimatedHours = 0; SessionCount = 0 }
        }
        
        $commitList = @($commits)
        $totalCommits = $commitList.Count
        $lastCommit = $commitList[0]
        $firstCommit = $commitList[-1]
        
        # Calculate sessions
        $gapSeconds = $SessionGapHours * 3600
        $sessionCount = 1
        $totalSessionTime = 0
        $prevTimestamp = $null
        $sessionStart = $null
        
        # Reverse to process chronologically
        [array]::Reverse($commitList)
        
        foreach ($timestamp in $commitList) {
            try {
                $current = [DateTime]::Parse($timestamp.Substring(0, 19))
                
                if ($null -eq $prevTimestamp) {
                    $sessionStart = $current
                }
                elseif (($current - $prevTimestamp).TotalSeconds -gt $gapSeconds) {
                    $totalSessionTime += ($prevTimestamp - $sessionStart).TotalSeconds + 1800
                    $sessionStart = $current
                    $sessionCount++
                }
                $prevTimestamp = $current
            }
            catch { }
        }
        
        # Add final session
        if ($null -ne $prevTimestamp -and $null -ne $sessionStart) {
            $totalSessionTime += ($prevTimestamp - $sessionStart).TotalSeconds + 1800
        }
        
        $estimatedHours = [math]::Round($totalSessionTime / 3600, 1)
        
        Write-Success "Found $totalCommits commits in ~$sessionCount sessions (~${estimatedHours}h estimated)"
        
        return @{
            FirstCommit = $firstCommit
            LastCommit = $lastCommit
            TotalCommits = $totalCommits
            EstimatedHours = $estimatedHours
            SessionCount = $sessionCount
        }
    }
    finally {
        Pop-Location
    }
}
#endregion

#region Spec-Kit Analysis
function Get-SpeckitMetrics {
    param(
        [string]$SpecsPath,
        [bool]$Enabled
    )
    
    Write-Header "📋 Analyzing Spec-Kit Usage"
    
    if (-not $Enabled) {
        Write-Info "Spec-Kit analysis disabled in config"
        return @{ SpecLines = 0; TasksTotal = 0; TasksComplete = 0; SpecFiles = 0 }
    }
    
    if (-not (Test-Path $SpecsPath)) {
        Write-Warn "Specs directory not found: $SpecsPath"
        return @{ SpecLines = 0; TasksTotal = 0; TasksComplete = 0; SpecFiles = 0 }
    }
    
    $specFiles = Get-ChildItem -Path $SpecsPath -Filter "*.md" -Recurse -File
    $specLines = 0
    $tasksTotal = 0
    $tasksComplete = 0
    
    foreach ($file in $specFiles) {
        $content = Get-Content $file.FullName -ErrorAction SilentlyContinue
        $specLines += $content.Count
        
        foreach ($line in $content) {
            if ($line -match '^\s*-\s*\[.\]\s*(\*\*)?T\d+') {
                $tasksTotal++
                if ($line -match '^\s*-\s*\[x\]\s*(\*\*)?T\d+') {
                    $tasksComplete++
                }
            }
        }
    }
    
    Write-Success "Found $specLines lines in $($specFiles.Count) spec files, $tasksComplete/$tasksTotal tasks complete"
    
    return @{
        SpecLines = $specLines
        TasksTotal = $tasksTotal
        TasksComplete = $tasksComplete
        SpecFiles = $specFiles.Count
    }
}
#endregion

#region Impact Calculations
function Get-ImpactCalculations {
    param(
        [hashtable]$Classification,
        [hashtable]$Config,
        [hashtable]$TestMetrics
    )
    
    Write-Header "🧮 Calculating Impact"
    
    $locBoilerplate = $Classification.Boilerplate.Loc
    $locGlue = $Classification.Glue.Loc
    $locLogic = $Classification.Logic.Loc
    
    # AI-assisted lines
    $aiLocBoilerplate = [math]::Floor($locBoilerplate * $Config.AiBoilerplate / 100)
    $aiLocGlue = [math]::Floor($locGlue * $Config.AiGlue / 100)
    $aiLocLogic = [math]::Floor($locLogic * $Config.AiLogic / 100)
    $aiLocTotal = $aiLocBoilerplate + $aiLocGlue + $aiLocLogic
    
    # Estimated manual time
    $estTimeBoilerplate = [math]::Round($locBoilerplate * $Config.MultBoilerplate / 100, 1)
    $estTimeGlue = [math]::Round($locGlue * $Config.MultGlue / 100, 1)
    $estTimeLogic = [math]::Round($locLogic * $Config.MultLogic / 100, 1)
    $estTimeTotal = $estTimeBoilerplate + $estTimeGlue + $estTimeLogic
    
    # Time saved
    $savedBoilerplate = [math]::Round($estTimeBoilerplate * $Config.AiBoilerplate / 100, 1)
    $savedGlue = [math]::Round($estTimeGlue * $Config.AiGlue / 100, 1)
    $savedLogic = [math]::Round($estTimeLogic * $Config.AiLogic / 100, 1)
    $savedTotal = $savedBoilerplate + $savedGlue + $savedLogic
    
    # Test calculations
    $estTimeTests = [math]::Round($TestMetrics.TestLoc * $Config.MultTest / 100, 1)
    $aiLocTests = [math]::Floor($TestMetrics.TestLoc * $Config.AiTest / 100)
    $savedTests = [math]::Round($estTimeTests * $Config.AiTest / 100, 1)
    
    # Totals
    $totalLoc = $locBoilerplate + $locGlue + $locLogic
    $aiPercentTotal = if ($totalLoc -gt 0) { [math]::Floor($aiLocTotal * 100 / $totalLoc) } else { 0 }
    $savedPercent = if ($estTimeTotal -gt 0) { [math]::Floor($savedTotal * 100 / $estTimeTotal) } else { 0 }
    
    # Grand totals
    $grandTotalLoc = $totalLoc + $TestMetrics.TestLoc
    $grandEstTime = $estTimeTotal + $estTimeTests
    $grandSaved = $savedTotal + $savedTests
    $grandAiLoc = $aiLocTotal + $aiLocTests
    $grandAiPercent = if ($grandTotalLoc -gt 0) { [math]::Floor($grandAiLoc * 100 / $grandTotalLoc) } else { 0 }
    
    Write-Success "Analysis complete: ${aiPercentTotal}% AI-assisted, ${savedPercent}% time saved"
    
    return @{
        TotalLoc = $totalLoc
        AiLocBoilerplate = $aiLocBoilerplate
        AiLocGlue = $aiLocGlue
        AiLocLogic = $aiLocLogic
        AiLocTotal = $aiLocTotal
        AiPercentTotal = $aiPercentTotal
        EstTimeBoilerplate = $estTimeBoilerplate
        EstTimeGlue = $estTimeGlue
        EstTimeLogic = $estTimeLogic
        EstTimeTotal = $estTimeTotal
        SavedBoilerplate = $savedBoilerplate
        SavedGlue = $savedGlue
        SavedLogic = $savedLogic
        SavedTotal = $savedTotal
        SavedPercent = $savedPercent
        EstTimeTests = $estTimeTests
        AiLocTests = $aiLocTests
        SavedTests = $savedTests
        GrandTotalLoc = $grandTotalLoc
        GrandEstTime = $grandEstTime
        GrandSaved = $grandSaved
        GrandAiLoc = $grandAiLoc
        GrandAiPercent = $grandAiPercent
    }
}
#endregion

#region Report Generation
function Write-MarkdownReport {
    param(
        [hashtable]$Config,
        [hashtable]$CodeMetrics,
        [hashtable]$TestMetrics,
        [hashtable]$Classification,
        [hashtable]$GitMetrics,
        [hashtable]$SpeckitMetrics,
        [hashtable]$Impact,
        [string]$OutputPath
    )
    
    Write-Header "📝 Generating Report"
    
    $dateGenerated = Get-Date -Format "yyyy-MM-dd"
    
    $taskPercent = if ($SpeckitMetrics.TasksTotal -gt 0) { 
        [math]::Floor($SpeckitMetrics.TasksComplete * 100 / $SpeckitMetrics.TasksTotal) 
    } else { 0 }
    
    $specToCode = if ($CodeMetrics.TotalLoc -gt 0) {
        [math]::Round($SpeckitMetrics.SpecLines / ($CodeMetrics.TotalLoc + 1), 1)
    } else { 0 }
    
    $productivityGain = if ($GitMetrics.EstimatedHours -gt 0) {
        [math]::Round($Impact.EstTimeTotal / $GitMetrics.EstimatedHours, 1)
    } else { "N/A" }

    $report = @"
# 📊 AI-Assisted Development Impact Report

**Project**: $($Config.ProjectName)  
**Type**: $($Config.ProjectType)  
**Generated**: $dateGenerated  
**Analyzer Version**: $VERSION

---

## Executive Summary

| Metric | Value |
|--------|-------|
| **Total Source LoC** | $($CodeMetrics.TotalLoc) |
| **AI-Assisted LoC** | $($Impact.AiLocTotal) ($($Impact.AiPercentTotal)%) |
| **Estimated Manual Time** | $($Impact.EstTimeTotal)h |
| **Estimated Time Saved** | $($Impact.SavedTotal)h ($($Impact.SavedPercent)%) |
| **Actual Dev Time** | ~$($GitMetrics.EstimatedHours)h ($($GitMetrics.SessionCount) sessions) |

---

## 📈 Code Metrics Breakdown

| Category | Files | LoC | AI-Assisted | Est. Manual | Time Saved |
|----------|-------|-----|-------------|-------------|------------|
| **Boilerplate** | $($Classification.Boilerplate.Files) | $($Classification.Boilerplate.Loc) | $($Impact.AiLocBoilerplate) ($($Config.AiBoilerplate)%) | $($Impact.EstTimeBoilerplate)h | $($Impact.SavedBoilerplate)h |
| **Glue Code** | $($Classification.Glue.Files) | $($Classification.Glue.Loc) | $($Impact.AiLocGlue) ($($Config.AiGlue)%) | $($Impact.EstTimeGlue)h | $($Impact.SavedGlue)h |
| **Core Logic** | $($Classification.Logic.Files) | $($Classification.Logic.Loc) | $($Impact.AiLocLogic) ($($Config.AiLogic)%) | $($Impact.EstTimeLogic)h | $($Impact.SavedLogic)h |
| **TOTAL** | $($CodeMetrics.TotalFiles) | $($CodeMetrics.TotalLoc) | $($Impact.AiLocTotal) ($($Impact.AiPercentTotal)%) | $($Impact.EstTimeTotal)h | $($Impact.SavedTotal)h |

### Category Definitions

- **Boilerplate**: Extension entry points, type definitions, configuration schemas
- **Glue Code**: Command handlers, event listeners, utility functions, UI bindings
- **Core Logic**: Unique algorithms, business rules, core functionality

---

## 🧪 Test Code Impact

| Metric | Value |
|--------|-------|
| **Test Files** | $($TestMetrics.TestFiles) |
| **Test LoC** | $($TestMetrics.TestLoc) |
| **Test-to-Code Ratio** | $($TestMetrics.TestRatio)% |
| **AI-Assisted Test LoC** | $($Impact.AiLocTests) ($($Config.AiTest)%) |
| **Est. Manual Test Time** | $($Impact.EstTimeTests)h |
| **Test Time Saved** | $($Impact.SavedTests)h |

---

## 📊 Grand Total (Source + Tests)

| Metric | Source | Tests | Combined |
|--------|--------|-------|----------|
| **Lines of Code** | $($CodeMetrics.TotalLoc) | $($TestMetrics.TestLoc) | $($Impact.GrandTotalLoc) |
| **AI-Assisted** | $($Impact.AiLocTotal) | $($Impact.AiLocTests) | $($Impact.GrandAiLoc) ($($Impact.GrandAiPercent)%) |
| **Est. Manual Time** | $($Impact.EstTimeTotal)h | $($Impact.EstTimeTests)h | $($Impact.GrandEstTime)h |
| **Time Saved** | $($Impact.SavedTotal)h | $($Impact.SavedTests)h | $($Impact.GrandSaved)h |

---

## ⏱️ Development Timeline

| Metric | Value |
|--------|-------|
| **First Commit** | $($GitMetrics.FirstCommit) |
| **Last Commit** | $($GitMetrics.LastCommit) |
| **Total Commits** | $($GitMetrics.TotalCommits) |
| **Dev Sessions** | $($GitMetrics.SessionCount) |
| **Estimated Active Hours** | $($GitMetrics.EstimatedHours)h |

---

## 📋 Spec-Kit Leverage

| Metric | Value |
|--------|-------|
| **Specification Lines** | $($SpeckitMetrics.SpecLines) |
| **Specification Files** | $($SpeckitMetrics.SpecFiles) |
| **Tasks Defined** | $($SpeckitMetrics.TasksTotal) |
| **Tasks Completed** | $($SpeckitMetrics.TasksComplete) ($taskPercent%) |
| **Spec-to-Code Ratio** | ${specToCode}:1 |

---

## 🎯 Key Insights

### Productivity Multiplier
``````
Traditional Development:  $($Impact.EstTimeTotal)h estimated
AI-Assisted Development:  $($GitMetrics.EstimatedHours)h actual
Productivity Gain:        ~${productivityGain}x faster
``````

### Value of Spec-Kit Methodology
- **Structured Planning**: $($SpeckitMetrics.TasksTotal) discrete tasks defined upfront
- **Clear Specifications**: $($SpeckitMetrics.SpecLines) lines of requirements/design docs
- **Execution Tracking**: $($SpeckitMetrics.TasksComplete)/$($SpeckitMetrics.TasksTotal) tasks completed

---

*Generated by [Spec-Kit Impact Analyzer](https://github.com/ormasoftchile/speckit-impact-analyzer) v$VERSION*
"@

    $report | Out-File -FilePath $OutputPath -Encoding utf8
    Write-Success "Report saved: $OutputPath"
}

function Write-JsonReport {
    param(
        [hashtable]$Config,
        [hashtable]$CodeMetrics,
        [hashtable]$TestMetrics,
        [hashtable]$Classification,
        [hashtable]$GitMetrics,
        [hashtable]$SpeckitMetrics,
        [hashtable]$Impact,
        [string]$OutputPath
    )
    
    $jsonData = @{
        version = $VERSION
        generated = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        project = @{
            name = $Config.ProjectName
            type = $Config.ProjectType
        }
        code = @{
            total_loc = $CodeMetrics.TotalLoc
            total_files = $CodeMetrics.TotalFiles
            comments = $CodeMetrics.TotalComments
            blank = $CodeMetrics.TotalBlank
        }
        tests = @{
            loc = $TestMetrics.TestLoc
            files = $TestMetrics.TestFiles
            ratio_percent = $TestMetrics.TestRatio
            ai_loc = $Impact.AiLocTests
            ai_percent = $Config.AiTest
            est_manual_hours = $Impact.EstTimeTests
            saved_hours = $Impact.SavedTests
        }
        classification = @{
            boilerplate = @{ files = $Classification.Boilerplate.Files; loc = $Classification.Boilerplate.Loc }
            glue_code = @{ files = $Classification.Glue.Files; loc = $Classification.Glue.Loc }
            core_logic = @{ files = $Classification.Logic.Files; loc = $Classification.Logic.Loc }
        }
        ai_assisted = @{
            total_loc = $Impact.AiLocTotal
            percent = $Impact.AiPercentTotal
            by_category = @{
                boilerplate = $Impact.AiLocBoilerplate
                glue_code = $Impact.AiLocGlue
                core_logic = $Impact.AiLocLogic
            }
        }
        time = @{
            estimated_manual_hours = $Impact.EstTimeTotal
            estimated_saved_hours = $Impact.SavedTotal
            saved_percent = $Impact.SavedPercent
            actual_hours = $GitMetrics.EstimatedHours
        }
        grand_total = @{
            loc = $Impact.GrandTotalLoc
            ai_loc = $Impact.GrandAiLoc
            ai_percent = $Impact.GrandAiPercent
            est_manual_hours = $Impact.GrandEstTime
            saved_hours = $Impact.GrandSaved
        }
        git = @{
            first_commit = $GitMetrics.FirstCommit
            last_commit = $GitMetrics.LastCommit
            total_commits = $GitMetrics.TotalCommits
            sessions = $GitMetrics.SessionCount
        }
        speckit = @{
            spec_lines = $SpeckitMetrics.SpecLines
            tasks_total = $SpeckitMetrics.TasksTotal
            tasks_complete = $SpeckitMetrics.TasksComplete
        }
    }
    
    $jsonData | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding utf8
    Write-Success "JSON metrics saved: $OutputPath"
}
#endregion

#region Main
if ($Help) {
    Get-Help $MyInvocation.MyCommand.Path -Full
    exit 0
}

if ($Version) {
    Write-Host "Spec-Kit Impact Analyzer v$VERSION"
    exit 0
}

# Resolve paths
$ProjectPath = Resolve-Path $ProjectPath -ErrorAction Stop

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  📊 Spec-Kit Impact Analyzer v$VERSION (PowerShell Edition)" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Project: $ProjectPath"
Write-Host ""

# Load configuration
$configPath = Join-Path $ProjectPath $ConfigFile
$config = Read-YamlConfig -Path $configPath

# Collect metrics
$sourcePath = Join-Path $ProjectPath $config.SourceDir
$codeMetrics = Get-CodeMetrics -SourcePath $sourcePath -ExcludeDirs $config.ExcludeDirs

$testPath = Join-Path $ProjectPath $config.TestDir
$testMetrics = Get-TestMetrics -TestPath $testPath -ExcludeDirs $config.ExcludeDirs -TotalLoc $codeMetrics.TotalLoc

$classification = Get-ClassifiedMetrics -FileMetrics $codeMetrics.Files

$gitMetrics = Get-GitTimeline -SessionGapHours $config.SessionGapHours

$specsPath = Join-Path $ProjectPath $config.SpecsDir
$speckitMetrics = Get-SpeckitMetrics -SpecsPath $specsPath -Enabled $config.SpeckitEnabled

# Calculate impact
$impact = Get-ImpactCalculations -Classification $classification -Config $config -TestMetrics $testMetrics

# Generate reports
$reportPath = Join-Path $ProjectPath $OutputFile
Write-MarkdownReport -Config $config -CodeMetrics $codeMetrics -TestMetrics $testMetrics `
    -Classification $classification -GitMetrics $gitMetrics -SpeckitMetrics $speckitMetrics `
    -Impact $impact -OutputPath $reportPath

if ($Json) {
    $jsonPath = Join-Path $ProjectPath "impact-metrics.json"
    Write-JsonReport -Config $config -CodeMetrics $codeMetrics -TestMetrics $testMetrics `
        -Classification $classification -GitMetrics $gitMetrics -SpeckitMetrics $speckitMetrics `
        -Impact $impact -OutputPath $jsonPath
}

# Summary
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  √ Analysis Complete" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "  Results:"
Write-Host "    • $($codeMetrics.TotalLoc) lines of source code ($($impact.AiPercentTotal)% AI-assisted)"
if ($testMetrics.TestLoc -gt 0) {
    Write-Host "    • $($testMetrics.TestLoc) lines of test code ($($config.AiTest)% AI-assisted)"
}
Write-Host "    • $($impact.GrandEstTime)h estimated manual time (source + tests)"
Write-Host "    • $($impact.GrandSaved)h saved ($($impact.SavedPercent)%)"
Write-Host ""
Write-Host "  Output:"
Write-Host "    • $OutputFile"
if ($Json) {
    Write-Host "    • impact-metrics.json"
}
Write-Host ""
#endregion
