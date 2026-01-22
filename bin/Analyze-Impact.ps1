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
    [switch]$ShowVersion,
    [Alias("h")]
    [switch]$Help,
    [Alias("g")]
    [string]$GitRoot = "",
    [switch]$IncludeInlineTests
)

$SCRIPT_VERSION = "1.1.0"

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
        AiEfficiencyFactor = 1.0  # Accounts for review/debug overhead (0.0-1.0)
        SessionGapHours = 2
        SessionBufferMinutes = 30  # Configurable buffer per session
        SpeckitEnabled = $true
        # Classification patterns (regex) - can be overridden in config
        PatternBoilerplate = 'extension\.(ts|js)|types[/\\]|config[/\\]|\.d\.ts|config\.(ts|js)|layouts[/\\]|interfaces[/\\]'
        PatternGlue = 'commands[/\\]|utils[/\\]|webview[/\\]|handlers[/\\]|components[/\\]|pages[/\\]|hooks[/\\]|services[/\\]'
        PatternLogic = ''  # Empty means "everything else"
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
        [string[]]$ExcludeDirs,
        [bool]$ExcludeInlineTests = $false
    )
    
    Write-Header "📊 Collecting Code Metrics"
    
    if (-not (Test-Path $SourcePath)) {
        Write-Warn "Source directory not found: $SourcePath"
        return @{ TotalLoc = 0; TotalFiles = 0; TotalComments = 0; TotalBlank = 0; Files = @() }
    }
    
    $files = Get-CodeFiles -Path $SourcePath -ExcludeDirs $ExcludeDirs
    
    # Filter out inline test files if requested
    if ($ExcludeInlineTests) {
        $files = $files | Where-Object { 
            $_.Name -notmatch '\.(test|spec)\.(ts|js|tsx|jsx)$' -and 
            $_.Name -notmatch '_test\.(go|py)$'
        }
    }
    
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
        [int]$TotalLoc,
        [bool]$IncludeInlineTests = $false,
        [string]$SourcePath = ""
    )
    
    Write-Header "🧪 Collecting Test Metrics"
    
    $testExcludes = $ExcludeDirs + @("coverage", "__snapshots__")
    $testFiles = @()
    $testLoc = 0
    $testComments = 0
    
    # Get tests from dedicated test directory
    if (Test-Path $TestPath) {
        $testFiles += Get-CodeFiles -Path $TestPath -ExcludeDirs $testExcludes
    } else {
        Write-Info "Test directory not found: $TestPath"
    }
    
    # Also look for inline test files (*.test.ts, *.spec.ts, etc.) in source directory
    if ($IncludeInlineTests -and $SourcePath -and (Test-Path $SourcePath)) {
        $inlineTestPatterns = @("*.test.ts", "*.test.js", "*.test.tsx", "*.test.jsx", "*.spec.ts", "*.spec.js", "*.spec.tsx", "*.spec.jsx", "_test.go", "*_test.py")
        # Build exclusion pattern for directories only (not filenames)
        $excludeDirPattern = ($testExcludes + @("\\test\\", "\\tests\\", "\\__tests__\\", "/test/", "/tests/", "/__tests__/")) -join '|'
        
        $inlineTests = Get-ChildItem -Path $SourcePath -Recurse -Include $inlineTestPatterns -File |
            Where-Object { $_.DirectoryName -notmatch $excludeDirPattern }
        
        if ($inlineTests) {
            Write-Info "Found $($inlineTests.Count) inline test files in source directory"
            $testFiles += $inlineTests
        }
    }
    
    if ($testFiles.Count -eq 0) {
        Write-Warn "No test files found"
        return @{ TestLoc = 0; TestFiles = 0; TestComments = 0; TestRatio = 0 }
    }
    
    foreach ($file in $testFiles) {
        $metrics = Measure-FileMetrics -FilePath $file.FullName
        $testLoc += $metrics.Code
        $testComments += $metrics.Comments
    }
    
    $testRatio = if ($TotalLoc -gt 0) { [math]::Round(($testLoc * 100) / $TotalLoc, 2) } else { 0 }
    
    Write-Success "Found $($testFiles.Count) test files with $testLoc lines of test code ($testRatio% of source)"
    
    return @{
        TestLoc = $testLoc
        TestFiles = $testFiles.Count
        TestComments = $testComments
        TestRatio = $testRatio
    }
}

function Get-FileClassification {
    param(
        [string]$RelativePath,
        [string]$PatternBoilerplate = 'extension\.(ts|js)|types[/\\]|config[/\\]|\.d\.ts|config\.(ts|js)|layouts[/\\]|interfaces[/\\]',
        [string]$PatternGlue = 'commands[/\\]|utils[/\\]|webview[/\\]|handlers[/\\]|components[/\\]|pages[/\\]|hooks[/\\]|services[/\\]'
    )
    
    # Boilerplate patterns (from config or default)
    if ($PatternBoilerplate -and $RelativePath -match $PatternBoilerplate) {
        return "Boilerplate"
    }
    
    # Glue code patterns (from config or default)
    if ($PatternGlue -and $RelativePath -match $PatternGlue) {
        return "Glue"
    }
    
    # Default to core logic
    return "Logic"
}

function Get-ClassifiedMetrics {
    param(
        [array]$FileMetrics,
        [string]$PatternBoilerplate = '',
        [string]$PatternGlue = ''
    )
    
    Write-Header "🏷️  Classifying Files"
    
    $boilerplateLoc = 0; $boilerplateFiles = 0
    $glueLoc = 0; $glueFiles = 0
    $logicLoc = 0; $logicFiles = 0
    
    foreach ($file in $FileMetrics) {
        $classification = Get-FileClassification -RelativePath $file.RelativePath -PatternBoilerplate $PatternBoilerplate -PatternGlue $PatternGlue
        
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
    param(
        [int]$SessionGapHours = 2,
        [int]$SessionBufferMinutes = 30,
        [string]$GitRootPath = "",
        [string]$SubfolderFilter = ""
    )
    
    Write-Header "⏱️  Analyzing Git Timeline"
    
    # Determine git directory location
    $gitSearchPath = if ($GitRootPath -and (Test-Path $GitRootPath)) { $GitRootPath } else { $ProjectPath }
    $gitDir = Join-Path $gitSearchPath ".git"
    
    if (-not (Test-Path $gitDir)) {
        # Try to find .git in parent directories
        $searchPath = $ProjectPath
        while ($searchPath -and -not (Test-Path (Join-Path $searchPath ".git"))) {
            $parent = Split-Path $searchPath -Parent
            if ($parent -eq $searchPath) { break }
            $searchPath = $parent
        }
        if ($searchPath -and (Test-Path (Join-Path $searchPath ".git"))) {
            $gitSearchPath = $searchPath
            $gitDir = Join-Path $searchPath ".git"
            Write-Info "Found git repository at: $gitSearchPath"
        } else {
            Write-Warn "Not a git repository"
            return @{
                FirstCommit = ""
                LastCommit = ""
                TotalCommits = 0
                EstimatedHours = 0
                SessionCount = 0
            }
        }
    }
    
    # Calculate the subfolder path relative to git root (if not explicitly provided)
    # Use case-insensitive replacement for Windows paths
    if (-not $SubfolderFilter -and $gitSearchPath -ne $ProjectPath) {
        $normalizedProjectPath = $ProjectPath.Replace('\', '/')
        $normalizedGitRoot = $gitSearchPath.Replace('\', '/')
        if ($normalizedProjectPath.ToLower().StartsWith($normalizedGitRoot.ToLower())) {
            $SubfolderFilter = $normalizedProjectPath.Substring($normalizedGitRoot.Length).TrimStart('/')
        }
    }
    
    Push-Location $gitSearchPath
    try {
        # Get the correct case for the path from git (important for case-sensitive git on Windows)
        if ($SubfolderFilter) {
            # Use icase pathspec magic to find files regardless of case
            $gitLsFiles = & git ls-files --full-name -- ":(icase)$SubfolderFilter/*" 2>$null | Select-Object -First 1
            if ($gitLsFiles) {
                # Extract the folder path with correct case from a tracked file
                $parts = $gitLsFiles -split '/'
                $filterParts = $SubfolderFilter -split '/'
                if ($parts.Count -ge $filterParts.Count) {
                    $correctCasePath = @()
                    for ($i = 0; $i -lt $filterParts.Count; $i++) {
                        $correctCasePath += $parts[$i]
                    }
                    $SubfolderFilter = $correctCasePath -join '/'
                    Write-Info "Corrected path case from git: $SubfolderFilter"
                }
            }
        }
        
        # Filter commits by subfolder if specified
        $gitLogArgs = @("log", "--format=%ai")
        if ($SubfolderFilter) {
            $gitLogArgs += "--"
            $gitLogArgs += $SubfolderFilter
            Write-Info "Filtering commits for subfolder: $SubfolderFilter"
        }
        $commits = & git @gitLogArgs 2>$null
        if (-not $commits) {
            return @{ FirstCommit = ""; LastCommit = ""; TotalCommits = 0; EstimatedHours = 0; SessionCount = 0 }
        }
        
        $commitList = @($commits)
        $totalCommits = $commitList.Count
        $lastCommit = $commitList[0]
        $firstCommit = $commitList[-1]
        
        # Calculate sessions
        $gapSeconds = $SessionGapHours * 3600
        $bufferSeconds = $SessionBufferMinutes * 60
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
                    $totalSessionTime += ($prevTimestamp - $sessionStart).TotalSeconds + $bufferSeconds
                    $sessionStart = $current
                    $sessionCount++
                }
                $prevTimestamp = $current
            }
            catch { }
        }
        
        # Add final session with configurable buffer
        if ($null -ne $prevTimestamp -and $null -ne $sessionStart) {
            $totalSessionTime += ($prevTimestamp - $sessionStart).TotalSeconds + $bufferSeconds
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
        [hashtable]$TestMetrics,
        [hashtable]$GitMetrics
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
    
    # Time saved (adjusted by efficiency factor to account for review/debug overhead)
    $efficiencyFactor = $Config.AiEfficiencyFactor
    $savedBoilerplate = [math]::Round($estTimeBoilerplate * $Config.AiBoilerplate / 100 * $efficiencyFactor, 1)
    $savedGlue = [math]::Round($estTimeGlue * $Config.AiGlue / 100 * $efficiencyFactor, 1)
    $savedLogic = [math]::Round($estTimeLogic * $Config.AiLogic / 100 * $efficiencyFactor, 1)
    $savedTotal = $savedBoilerplate + $savedGlue + $savedLogic
    
    # Test calculations
    $estTimeTests = [math]::Round($TestMetrics.TestLoc * $Config.MultTest / 100, 1)
    $aiLocTests = [math]::Floor($TestMetrics.TestLoc * $Config.AiTest / 100)
    $savedTests = [math]::Round($estTimeTests * $Config.AiTest / 100 * $efficiencyFactor, 1)
    
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
    
    # Calculate ACTUAL saved: (estimated - actual) / estimated * 100
    # This compares what it WOULD have taken vs what it ACTUALLY took
    $actualSavedHours = 0
    $actualSavedPercent = 0
    if ($grandEstTime -gt 0 -and $GitMetrics.EstimatedHours -gt 0) {
        $actualSavedHours = [math]::Round($grandEstTime - $GitMetrics.EstimatedHours, 1)
        $actualSavedPercent = [math]::Floor(($grandEstTime - $GitMetrics.EstimatedHours) * 100 / $grandEstTime)
    }
    
    Write-Success "Analysis complete: ${aiPercentTotal}% AI-assisted, ${actualSavedPercent}% time saved"
    
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
        ActualSavedHours = $actualSavedHours
        ActualSavedPercent = $actualSavedPercent
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
        [math]::Round($Impact.GrandEstTime / $GitMetrics.EstimatedHours, 1)
    } else { "N/A" }

    $report = @"
# 📊 AI-Assisted Development Impact Report

**Project**: $($Config.ProjectName)  
**Type**: $($Config.ProjectType)  
**Generated**: $dateGenerated  
**Analyzer Version**: $SCRIPT_VERSION

---

## Executive Summary

| Metric | Value |
|--------|-------|
| **Total Source LoC** | $($CodeMetrics.TotalLoc) |
| **AI-Assisted LoC** | $($Impact.AiLocTotal) ($($Impact.AiPercentTotal)%) |
| **Estimated Manual Time** | $($Impact.GrandEstTime)h (source + tests) |
| **Actual Dev Time** | ~$($GitMetrics.EstimatedHours)h ($($GitMetrics.SessionCount) sessions) |
| **Time Saved** | $($Impact.ActualSavedHours)h ($($Impact.ActualSavedPercent)%) |

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
Traditional Development:  $($Impact.GrandEstTime)h estimated (source + tests)
AI-Assisted Development:  $($GitMetrics.EstimatedHours)h actual
Productivity Gain:        ~${productivityGain}x faster
``````

### Value of Spec-Kit Methodology
- **Structured Planning**: $($SpeckitMetrics.TasksTotal) discrete tasks defined upfront
- **Clear Specifications**: $($SpeckitMetrics.SpecLines) lines of requirements/design docs
- **Execution Tracking**: $($SpeckitMetrics.TasksComplete)/$($SpeckitMetrics.TasksTotal) tasks completed

---

## 📖 Addendum: Metrics Glossary

This section provides detailed explanations for each metric used in this report.

### Executive Summary Metrics

| Metric | Description |
|--------|-------------|
| **Total Source LoC** | Total lines of code in the source directory, excluding blank lines and comments. Counted using built-in line counting. |
| **AI-Assisted LoC** | Estimated lines of code where AI tools (e.g., GitHub Copilot) significantly contributed to writing or suggesting the code. |
| **Estimated Manual Time** | Projected hours required to write this codebase without any AI assistance, based on industry-standard productivity multipliers. |
| **Estimated Time Saved** | Hours saved by using AI-assisted development, calculated as a percentage of the estimated manual time. |
| **Actual Dev Time** | Real development time estimated from git commit history, grouping commits into sessions separated by $($Config.SessionGapHours)-hour gaps. |

### Code Category Metrics

| Metric | Description |
|--------|-------------|
| **Boilerplate** | Repetitive, structural code like entry points, type definitions, configuration schemas. High AI assistance potential (~$($Config.AiBoilerplate)%). Multiplier: $($Config.MultBoilerplate)h/100 LoC. |
| **Glue Code** | Integration code connecting components: command handlers, event listeners, utility functions, UI bindings. Medium AI assistance (~$($Config.AiGlue)%). Multiplier: $($Config.MultGlue)h/100 LoC. |
| **Core Logic** | Unique algorithms, business rules, and core functionality requiring human insight. Lower AI assistance (~$($Config.AiLogic)%). Multiplier: $($Config.MultLogic)h/100 LoC. |
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
| **Est. Manual Test Time** | Hours to write tests manually, using multiplier: $($Config.MultTest)h/100 LoC. |
| **Test Time Saved** | Hours saved on test writing through AI assistance. |

### Development Timeline Metrics

| Metric | Description |
|--------|-------------|
| **First Commit** | Timestamp of the earliest commit in the repository. |
| **Last Commit** | Timestamp of the most recent commit. |
| **Total Commits** | Total number of commits in the repository history. |
| **Dev Sessions** | Number of development sessions, where a session is a group of commits separated by ≤$($Config.SessionGapHours) hours. |
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
| **Session Gap** | $($Config.SessionGapHours)h | Time gap used to separate git commits into distinct development sessions. |
| **Boilerplate Multiplier** | $($Config.MultBoilerplate)h/100 LoC | Estimated manual coding time for boilerplate code. |
| **Glue Code Multiplier** | $($Config.MultGlue)h/100 LoC | Estimated manual coding time for integration code. |
| **Core Logic Multiplier** | $($Config.MultLogic)h/100 LoC | Estimated manual coding time for complex logic. |
| **Test Multiplier** | $($Config.MultTest)h/100 LoC | Estimated manual coding time for test code. |
| **AI % Boilerplate** | $($Config.AiBoilerplate)% | Estimated AI contribution to boilerplate code. |
| **AI % Glue Code** | $($Config.AiGlue)% | Estimated AI contribution to glue code. |
| **AI % Core Logic** | $($Config.AiLogic)% | Estimated AI contribution to core logic. |
| **AI % Tests** | $($Config.AiTest)% | Estimated AI contribution to test code. |

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
        version = $SCRIPT_VERSION
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
            estimated_manual_hours = $Impact.GrandEstTime
            actual_hours = $GitMetrics.EstimatedHours
            saved_hours = $Impact.ActualSavedHours
            saved_percent = $Impact.ActualSavedPercent
        }
        grand_total = @{
            loc = $Impact.GrandTotalLoc
            ai_loc = $Impact.GrandAiLoc
            ai_percent = $Impact.GrandAiPercent
            est_manual_hours = $Impact.GrandEstTime
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

if ($ShowVersion) {
    Write-Host "Spec-Kit Impact Analyzer v$SCRIPT_VERSION"
    exit 0
}

# Resolve paths
$ProjectPath = Resolve-Path $ProjectPath -ErrorAction Stop

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  📊 Spec-Kit Impact Analyzer v$SCRIPT_VERSION (PowerShell Edition)" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Project: $ProjectPath"
if ($GitRoot) { Write-Host "  Git Root: $GitRoot" }
if ($IncludeInlineTests) { Write-Host "  Include Inline Tests: Yes" }
Write-Host ""

# Load configuration
$configPath = Join-Path $ProjectPath $ConfigFile
$config = Read-YamlConfig -Path $configPath

# Collect metrics
$sourcePath = Join-Path $ProjectPath $config.SourceDir
$codeMetrics = Get-CodeMetrics -SourcePath $sourcePath -ExcludeDirs $config.ExcludeDirs -ExcludeInlineTests $IncludeInlineTests

$testPath = Join-Path $ProjectPath $config.TestDir
$testMetrics = Get-TestMetrics -TestPath $testPath -ExcludeDirs $config.ExcludeDirs -TotalLoc $codeMetrics.TotalLoc -IncludeInlineTests $IncludeInlineTests -SourcePath $sourcePath

$classification = Get-ClassifiedMetrics -FileMetrics $codeMetrics.Files -PatternBoilerplate $config.PatternBoilerplate -PatternGlue $config.PatternGlue

$gitMetrics = Get-GitTimeline -SessionGapHours $config.SessionGapHours -SessionBufferMinutes $config.SessionBufferMinutes -GitRootPath $GitRoot

$specsPath = Join-Path $ProjectPath $config.SpecsDir
$speckitMetrics = Get-SpeckitMetrics -SpecsPath $specsPath -Enabled $config.SpeckitEnabled

# Calculate impact
$impact = Get-ImpactCalculations -Classification $classification -Config $config -TestMetrics $testMetrics -GitMetrics $gitMetrics

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
Write-Host "    • $($gitMetrics.EstimatedHours)h actual dev time"
Write-Host "    • $($impact.ActualSavedHours)h saved ($($impact.ActualSavedPercent)%)"
Write-Host ""
Write-Host "  Output:"
Write-Host "    • $OutputFile"
if ($Json) {
    Write-Host "    • impact-metrics.json"
}
Write-Host ""
#endregion
