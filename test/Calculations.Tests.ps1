#Requires -Version 5.1
<#
.SYNOPSIS
    Unit Tests for Spec-Kit Impact Analyzer Calculations (PowerShell)
    
.DESCRIPTION
    Tests the core calculation logic using Pester framework.
    
.EXAMPLE
    Invoke-Pester -Path test/Calculations.Tests.ps1
    
.NOTES
    Install Pester: Install-Module -Name Pester -Force -SkipPublisherCheck
#>

BeforeAll {
    # Helper functions that mirror the script's calculations
    function Get-ActualSavedPercent {
        param([double]$GrandEstTime, [double]$GitEstimatedHours)
        if ($GrandEstTime -gt 0 -and $GitEstimatedHours -ge 0) {
            return [math]::Floor(($GrandEstTime - $GitEstimatedHours) * 100 / $GrandEstTime)
        }
        return 0
    }
    
    function Get-ActualSavedHours {
        param([double]$GrandEstTime, [double]$GitEstimatedHours)
        return [math]::Round($GrandEstTime - $GitEstimatedHours, 1)
    }
    
    function Get-ProductivityMultiplier {
        param([double]$GrandEstTime, [double]$GitEstimatedHours)
        if ($GitEstimatedHours -gt 0) {
            return [math]::Round($GrandEstTime / $GitEstimatedHours, 1)
        }
        return 0
    }
    
    function Get-EstimatedManualTime {
        param([int]$Loc, [double]$Multiplier)
        return [math]::Round($Loc * $Multiplier / 100, 1)
    }
    
    function Get-AiAssistedLoc {
        param([int]$Loc, [int]$AiPercent)
        return [math]::Floor($Loc * $AiPercent / 100)
    }
    
    function Get-TimeSavedWithEfficiency {
        param([double]$EstTime, [int]$AiPercent, [double]$EfficiencyFactor)
        return [math]::Round($EstTime * $AiPercent / 100 * $EfficiencyFactor, 1)
    }
    
    function Get-FileClassification {
        param(
            [string]$RelativePath,
            [string]$PatternBoilerplate = 'extension\.(ts|js)|types[/\\]|config[/\\]|\.d\.ts',
            [string]$PatternGlue = 'commands[/\\]|utils[/\\]|webview[/\\]|handlers[/\\]'
        )
        
        if ($PatternBoilerplate -and $RelativePath -match $PatternBoilerplate) {
            return "Boilerplate"
        }
        if ($PatternGlue -and $RelativePath -match $PatternGlue) {
            return "Glue"
        }
        return "Logic"
    }
}

Describe "Actual Saved Percent Calculations" {
    Context "Formula: (GRAND_EST_TIME - GIT_ESTIMATED_HOURS) / GRAND_EST_TIME * 100" {
        
        It "100h estimated, 25h actual = 75% saved" {
            Get-ActualSavedPercent -GrandEstTime 100 -GitEstimatedHours 25 | Should -Be 75
        }
        
        It "50h estimated, 10h actual = 80% saved" {
            Get-ActualSavedPercent -GrandEstTime 50 -GitEstimatedHours 10 | Should -Be 80
        }
        
        It "100h estimated, 100h actual = 0% saved" {
            Get-ActualSavedPercent -GrandEstTime 100 -GitEstimatedHours 100 | Should -Be 0
        }
        
        It "Negative when actual > estimated (took longer)" {
            Get-ActualSavedPercent -GrandEstTime 50 -GitEstimatedHours 75 | Should -Be -50
        }
        
        It "Handles very high savings (95%)" {
            Get-ActualSavedPercent -GrandEstTime 100 -GitEstimatedHours 5 | Should -Be 95
        }
    }
}

Describe "Actual Saved Hours Calculations" {
    Context "Formula: GRAND_EST_TIME - GIT_ESTIMATED_HOURS" {
        
        It "100h estimated, 25h actual = 75h saved" {
            Get-ActualSavedHours -GrandEstTime 100 -GitEstimatedHours 25 | Should -Be 75.0
        }
        
        It "50h estimated, 10h actual = 40h saved" {
            Get-ActualSavedHours -GrandEstTime 50 -GitEstimatedHours 10 | Should -Be 40.0
        }
        
        It "Negative when actual > estimated" {
            Get-ActualSavedHours -GrandEstTime 50 -GitEstimatedHours 75 | Should -Be -25.0
        }
    }
}

Describe "Productivity Multiplier Calculations" {
    Context "Formula: GRAND_EST_TIME / GIT_ESTIMATED_HOURS" {
        
        It "100h estimated / 25h actual = 4x" {
            Get-ProductivityMultiplier -GrandEstTime 100 -GitEstimatedHours 25 | Should -Be 4.0
        }
        
        It "50h estimated / 10h actual = 5x" {
            Get-ProductivityMultiplier -GrandEstTime 50 -GitEstimatedHours 10 | Should -Be 5.0
        }
        
        It "100h estimated / 100h actual = 1x (no gain)" {
            Get-ProductivityMultiplier -GrandEstTime 100 -GitEstimatedHours 100 | Should -Be 1.0
        }
        
        It "Handles fractional results" {
            Get-ProductivityMultiplier -GrandEstTime 100 -GitEstimatedHours 33 | Should -BeApproximately 3.0 0.1
        }
        
        It "Returns 0 when actual hours is 0" {
            Get-ProductivityMultiplier -GrandEstTime 100 -GitEstimatedHours 0 | Should -Be 0
        }
    }
}

Describe "AI Efficiency Factor Calculations" {
    Context "Formula: SAVED = EST_TIME * AI_PERCENT / 100 * EFFICIENCY_FACTOR" {
        
        It "1.0 efficiency = full savings" {
            Get-TimeSavedWithEfficiency -EstTime 100 -AiPercent 90 -EfficiencyFactor 1.0 | Should -Be 90.0
        }
        
        It "0.7 efficiency reduces savings by 30%" {
            Get-TimeSavedWithEfficiency -EstTime 100 -AiPercent 90 -EfficiencyFactor 0.7 | Should -Be 63.0
        }
        
        It "0.85 efficiency reduces savings by 15%" {
            Get-TimeSavedWithEfficiency -EstTime 100 -AiPercent 80 -EfficiencyFactor 0.85 | Should -Be 68.0
        }
        
        It "0.0 efficiency = no savings" {
            Get-TimeSavedWithEfficiency -EstTime 100 -AiPercent 90 -EfficiencyFactor 0.0 | Should -Be 0
        }
    }
}

Describe "Estimated Manual Time Calculations" {
    Context "Formula: LOC * MULTIPLIER / 100" {
        
        It "1000 LoC at 0.5h/100 = 5h (boilerplate)" {
            Get-EstimatedManualTime -Loc 1000 -Multiplier 0.5 | Should -Be 5.0
        }
        
        It "1000 LoC at 1.5h/100 = 15h (glue)" {
            Get-EstimatedManualTime -Loc 1000 -Multiplier 1.5 | Should -Be 15.0
        }
        
        It "1000 LoC at 4.0h/100 = 40h (logic)" {
            Get-EstimatedManualTime -Loc 1000 -Multiplier 4.0 | Should -Be 40.0
        }
        
        It "Handles small LoC counts" {
            Get-EstimatedManualTime -Loc 50 -Multiplier 4.0 | Should -Be 2.0
        }
    }
    
    Context "Grand total combines all categories" {
        It "Sums boilerplate + glue + logic correctly" {
            $estBoilerplate = Get-EstimatedManualTime -Loc 500 -Multiplier 0.5   # 2.5
            $estGlue = Get-EstimatedManualTime -Loc 300 -Multiplier 1.5          # 4.5
            $estLogic = Get-EstimatedManualTime -Loc 200 -Multiplier 4.0         # 8.0
            
            $total = $estBoilerplate + $estGlue + $estLogic
            $total | Should -Be 15.0
        }
    }
}

Describe "AI-Assisted LoC Calculations" {
    Context "Formula: LOC * AI_PERCENT / 100" {
        
        It "1000 LoC at 90% AI = 900 AI-assisted" {
            Get-AiAssistedLoc -Loc 1000 -AiPercent 90 | Should -Be 900
        }
        
        It "500 LoC at 30% AI = 150 AI-assisted" {
            Get-AiAssistedLoc -Loc 500 -AiPercent 30 | Should -Be 150
        }
        
        It "1000 LoC at 0% AI = 0 AI-assisted" {
            Get-AiAssistedLoc -Loc 1000 -AiPercent 0 | Should -Be 0
        }
        
        It "1000 LoC at 100% AI = 1000 AI-assisted" {
            Get-AiAssistedLoc -Loc 1000 -AiPercent 100 | Should -Be 1000
        }
    }
    
    Context "Weighted AI percent across categories" {
        It "Calculates weighted average correctly" {
            $locBoilerplate = 500; $aiBoilerplate = 90
            $locGlue = 300; $aiGlue = 70
            $locLogic = 200; $aiLogic = 30
            
            $aiLocBoilerplate = Get-AiAssistedLoc -Loc $locBoilerplate -AiPercent $aiBoilerplate
            $aiLocGlue = Get-AiAssistedLoc -Loc $locGlue -AiPercent $aiGlue
            $aiLocLogic = Get-AiAssistedLoc -Loc $locLogic -AiPercent $aiLogic
            
            $totalLoc = $locBoilerplate + $locGlue + $locLogic
            $totalAiLoc = $aiLocBoilerplate + $aiLocGlue + $aiLocLogic
            
            $aiPercent = [math]::Floor($totalAiLoc * 100 / $totalLoc)
            
            # (450 + 210 + 60) / 1000 * 100 = 72%
            $aiPercent | Should -Be 72
        }
    }
}

Describe "Session Buffer Calculations" {
    Context "Buffer time per session" {
        
        It "30 min buffer = 1800 seconds" {
            $bufferMinutes = 30
            $bufferSeconds = $bufferMinutes * 60
            $bufferSeconds | Should -Be 1800
        }
        
        It "15 min buffer = 900 seconds" {
            $bufferMinutes = 15
            $bufferSeconds = $bufferMinutes * 60
            $bufferSeconds | Should -Be 900
        }
    }
    
    Context "Total session time with buffer" {
        It "3 sessions at 30min buffer adds 1.5h" {
            $sessionCount = 3
            $bufferMinutes = 30
            $rawSessionSeconds = 7200  # 2 hours of actual coding
            
            $bufferSeconds = $bufferMinutes * 60
            $totalBuffer = $bufferSeconds * $sessionCount
            $totalSeconds = $rawSessionSeconds + $totalBuffer
            
            # 7200 + 5400 = 12600 seconds = 3.5 hours
            $totalSeconds | Should -Be 12600
            $totalHours = [math]::Round($totalSeconds / 3600, 1)
            $totalHours | Should -Be 3.5
        }
    }
}

Describe "Grand Total Calculations" {
    Context "Source + Tests combined" {
        
        It "Grand total LoC = source + tests" {
            $totalLoc = 5000
            $testLoc = 2000
            
            $grandTotalLoc = $totalLoc + $testLoc
            $grandTotalLoc | Should -Be 7000
        }
        
        It "Grand est time = source time + test time" {
            $estTimeTotal = 50.0
            $estTimeTests = 15.0
            
            $grandEstTime = $estTimeTotal + $estTimeTests
            $grandEstTime | Should -Be 65.0
        }
    }
}

Describe "File Classification Pattern Matching" {
    Context "Boilerplate patterns" {
        
        It "extension.ts is boilerplate" {
            Get-FileClassification -RelativePath "src/extension.ts" | Should -Be "Boilerplate"
        }
        
        It "types/index.ts is boilerplate" {
            Get-FileClassification -RelativePath "src/types/index.ts" | Should -Be "Boilerplate"
        }
        
        It "config/settings.ts is boilerplate" {
            Get-FileClassification -RelativePath "src/config/settings.ts" | Should -Be "Boilerplate"
        }
        
        It "interfaces.d.ts is boilerplate" {
            Get-FileClassification -RelativePath "src/interfaces.d.ts" | Should -Be "Boilerplate"
        }
    }
    
    Context "Glue code patterns" {
        
        It "utils/helper.ts is glue" {
            Get-FileClassification -RelativePath "src/utils/helper.ts" | Should -Be "Glue"
        }
        
        It "commands/run.ts is glue" {
            Get-FileClassification -RelativePath "src/commands/run.ts" | Should -Be "Glue"
        }
        
        It "handlers/events.ts is glue" {
            Get-FileClassification -RelativePath "src/handlers/events.ts" | Should -Be "Glue"
        }
        
        It "webview/panel.ts is glue" {
            Get-FileClassification -RelativePath "src/webview/panel.ts" | Should -Be "Glue"
        }
    }
    
    Context "Core logic (default)" {
        
        It "core/engine.ts is logic" {
            Get-FileClassification -RelativePath "src/core/engine.ts" | Should -Be "Logic"
        }
        
        It "parser/ast.ts is logic" {
            Get-FileClassification -RelativePath "src/parser/ast.ts" | Should -Be "Logic"
        }
        
        It "index.ts is logic (no matching pattern)" {
            Get-FileClassification -RelativePath "src/index.ts" | Should -Be "Logic"
        }
    }
    
    Context "Custom patterns" {
        
        It "Respects custom boilerplate pattern" {
            Get-FileClassification -RelativePath "src/custom/file.ts" `
                -PatternBoilerplate "custom[/\\]" | Should -Be "Boilerplate"
        }
        
        It "Respects custom glue pattern" {
            Get-FileClassification -RelativePath "src/services/api.ts" `
                -PatternGlue "services[/\\]" | Should -Be "Glue"
        }
    }
}

Describe "Edge Cases" {
    Context "Zero and boundary values" {
        
        It "Zero estimated time returns 0% saved" {
            Get-ActualSavedPercent -GrandEstTime 0 -GitEstimatedHours 10 | Should -Be 0
        }
        
        It "Zero LoC returns 0 AI-assisted" {
            Get-AiAssistedLoc -Loc 0 -AiPercent 90 | Should -Be 0
        }
        
        It "Zero multiplier returns 0 hours" {
            Get-EstimatedManualTime -Loc 1000 -Multiplier 0 | Should -Be 0
        }
    }
    
    Context "Very large values" {
        
        It "Handles large LoC counts" {
            Get-EstimatedManualTime -Loc 1000000 -Multiplier 4.0 | Should -Be 40000.0
        }
        
        It "Handles large time savings" {
            Get-ActualSavedPercent -GrandEstTime 10000 -GitEstimatedHours 100 | Should -Be 99
        }
    }
}

Describe "Integration: Full Impact Calculation" {
    It "Calculates complete impact metrics correctly" {
        # Setup: A typical project
        $config = @{
            MultBoilerplate = 0.5
            MultGlue = 1.5
            MultLogic = 4.0
            MultTest = 1.5
            AiBoilerplate = 90
            AiGlue = 70
            AiLogic = 30
            AiTest = 75
            AiEfficiencyFactor = 0.85
        }
        
        $classification = @{
            Boilerplate = @{ Loc = 1000 }
            Glue = @{ Loc = 2000 }
            Logic = @{ Loc = 1000 }
        }
        
        $testLoc = 1500
        $gitEstimatedHours = 25
        
        # Calculate estimated times
        $estBoilerplate = Get-EstimatedManualTime -Loc $classification.Boilerplate.Loc -Multiplier $config.MultBoilerplate  # 5.0
        $estGlue = Get-EstimatedManualTime -Loc $classification.Glue.Loc -Multiplier $config.MultGlue                        # 30.0
        $estLogic = Get-EstimatedManualTime -Loc $classification.Logic.Loc -Multiplier $config.MultLogic                     # 40.0
        $estTests = Get-EstimatedManualTime -Loc $testLoc -Multiplier $config.MultTest                                       # 22.5
        
        $grandEstTime = $estBoilerplate + $estGlue + $estLogic + $estTests  # 97.5
        
        # Calculate actual saved
        $actualSavedHours = Get-ActualSavedHours -GrandEstTime $grandEstTime -GitEstimatedHours $gitEstimatedHours  # 72.5
        $actualSavedPercent = Get-ActualSavedPercent -GrandEstTime $grandEstTime -GitEstimatedHours $gitEstimatedHours  # 74
        
        # Calculate productivity multiplier
        $productivityMultiplier = Get-ProductivityMultiplier -GrandEstTime $grandEstTime -GitEstimatedHours $gitEstimatedHours  # 3.9
        
        # Assertions
        $grandEstTime | Should -Be 97.5
        $actualSavedHours | Should -Be 72.5
        $actualSavedPercent | Should -Be 74
        $productivityMultiplier | Should -Be 3.9
    }
}
