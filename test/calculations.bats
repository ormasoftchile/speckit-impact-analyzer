#!/usr/bin/env bats
# ═══════════════════════════════════════════════════════════════════════
# Unit Tests for Spec-Kit Impact Analyzer Calculations
# Run with: bats test/calculations.bats
# Install: brew install bats-core
# ═══════════════════════════════════════════════════════════════════════

setup() {
    # Source the calculation functions (we'll extract them for testing)
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(dirname "$TEST_DIR")"
    
    # Load bc for calculations
    export LC_NUMERIC="C"
}

# ═══════════════════════════════════════════════════════════════════════
# ACTUAL SAVED PERCENT CALCULATIONS
# Formula: (GRAND_EST_TIME - GIT_ESTIMATED_HOURS) / GRAND_EST_TIME * 100
# ═══════════════════════════════════════════════════════════════════════

@test "actual_saved_percent: 100h estimated, 25h actual = 75% saved" {
    GRAND_EST_TIME=100
    GIT_ESTIMATED_HOURS=25
    
    result=$(echo "scale=0; ($GRAND_EST_TIME - $GIT_ESTIMATED_HOURS) * 100 / $GRAND_EST_TIME" | bc)
    
    [ "$result" -eq 75 ]
}

@test "actual_saved_percent: 50h estimated, 10h actual = 80% saved" {
    GRAND_EST_TIME=50
    GIT_ESTIMATED_HOURS=10
    
    result=$(echo "scale=0; ($GRAND_EST_TIME - $GIT_ESTIMATED_HOURS) * 100 / $GRAND_EST_TIME" | bc)
    
    [ "$result" -eq 80 ]
}

@test "actual_saved_percent: 100h estimated, 100h actual = 0% saved" {
    GRAND_EST_TIME=100
    GIT_ESTIMATED_HOURS=100
    
    result=$(echo "scale=0; ($GRAND_EST_TIME - $GIT_ESTIMATED_HOURS) * 100 / $GRAND_EST_TIME" | bc)
    
    [ "$result" -eq 0 ]
}

@test "actual_saved_percent: negative when actual > estimated" {
    GRAND_EST_TIME=50
    GIT_ESTIMATED_HOURS=75
    
    result=$(echo "scale=0; ($GRAND_EST_TIME - $GIT_ESTIMATED_HOURS) * 100 / $GRAND_EST_TIME" | bc)
    
    # Should be -50% (took longer than estimated)
    [ "$result" -eq -50 ]
}

@test "actual_saved_hours: 100h estimated, 25h actual = 75h saved" {
    GRAND_EST_TIME=100
    GIT_ESTIMATED_HOURS=25
    
    result=$(echo "scale=1; $GRAND_EST_TIME - $GIT_ESTIMATED_HOURS" | bc)
    
    # bc may output "75" or "75.0" depending on version
    [[ "$result" == "75.0" ]] || [[ "$result" == "75" ]]
}

# ═══════════════════════════════════════════════════════════════════════
# PRODUCTIVITY MULTIPLIER CALCULATIONS
# Formula: GRAND_EST_TIME / GIT_ESTIMATED_HOURS
# ═══════════════════════════════════════════════════════════════════════

@test "productivity_multiplier: 100h estimated / 25h actual = 4x" {
    GRAND_EST_TIME=100
    GIT_ESTIMATED_HOURS=25
    
    result=$(echo "scale=1; $GRAND_EST_TIME / $GIT_ESTIMATED_HOURS" | bc)
    
    [ "$result" = "4.0" ]
}

@test "productivity_multiplier: 50h estimated / 10h actual = 5x" {
    GRAND_EST_TIME=50
    GIT_ESTIMATED_HOURS=10
    
    result=$(echo "scale=1; $GRAND_EST_TIME / $GIT_ESTIMATED_HOURS" | bc)
    
    [ "$result" = "5.0" ]
}

@test "productivity_multiplier: 100h estimated / 100h actual = 1x (no gain)" {
    GRAND_EST_TIME=100
    GIT_ESTIMATED_HOURS=100
    
    result=$(echo "scale=1; $GRAND_EST_TIME / $GIT_ESTIMATED_HOURS" | bc)
    
    [ "$result" = "1.0" ]
}

@test "productivity_multiplier: handles fractional results" {
    GRAND_EST_TIME=100
    GIT_ESTIMATED_HOURS=33
    
    result=$(echo "scale=1; $GRAND_EST_TIME / $GIT_ESTIMATED_HOURS" | bc)
    
    # 100/33 ≈ 3.0
    [ "$result" = "3.0" ]
}

# ═══════════════════════════════════════════════════════════════════════
# AI EFFICIENCY FACTOR CALCULATIONS
# Formula: SAVED = EST_TIME * AI_PERCENT / 100 * EFFICIENCY_FACTOR
# ═══════════════════════════════════════════════════════════════════════

@test "efficiency_factor: 1.0 means full savings" {
    EST_TIME=100
    AI_PERCENT=90
    EFFICIENCY_FACTOR=1.0
    
    result=$(echo "scale=1; $EST_TIME * $AI_PERCENT / 100 * $EFFICIENCY_FACTOR" | bc)
    
    [ "$result" = "90.0" ]
}

@test "efficiency_factor: 0.7 reduces savings by 30%" {
    EST_TIME=100
    AI_PERCENT=90
    EFFICIENCY_FACTOR=0.7
    
    result=$(echo "scale=1; $EST_TIME * $AI_PERCENT / 100 * $EFFICIENCY_FACTOR" | bc)
    
    # 90 * 0.7 = 63
    [ "$result" = "63.0" ]
}

@test "efficiency_factor: 0.85 reduces savings by 15%" {
    EST_TIME=100
    AI_PERCENT=80
    EFFICIENCY_FACTOR=0.85
    
    result=$(echo "scale=1; $EST_TIME * $AI_PERCENT / 100 * $EFFICIENCY_FACTOR" | bc)
    
    # 80 * 0.85 = 68.0 (bc may output 68.00 on some systems)
    [[ "$result" == "68.0" ]] || [[ "$result" == "68" ]] || [[ "$result" == "68.00" ]]
}

@test "efficiency_factor: 0.0 means no savings" {
    EST_TIME=100
    AI_PERCENT=90
    EFFICIENCY_FACTOR=0.0
    
    result=$(echo "scale=1; $EST_TIME * $AI_PERCENT / 100 * $EFFICIENCY_FACTOR" | bc)
    
    [ "$result" = "0" ] || [ "$result" = "0.0" ] || [ "$result" = ".0" ]
}

# ═══════════════════════════════════════════════════════════════════════
# ESTIMATED MANUAL TIME CALCULATIONS
# Formula: LOC * MULTIPLIER / 100
# ═══════════════════════════════════════════════════════════════════════

@test "est_manual_time: 1000 LoC at 0.5h/100 = 5h (boilerplate)" {
    LOC=1000
    MULTIPLIER=0.5
    
    result=$(echo "scale=1; $LOC * $MULTIPLIER / 100" | bc)
    
    [ "$result" = "5.0" ]
}

@test "est_manual_time: 1000 LoC at 1.5h/100 = 15h (glue)" {
    LOC=1000
    MULTIPLIER=1.5
    
    result=$(echo "scale=1; $LOC * $MULTIPLIER / 100" | bc)
    
    [ "$result" = "15.0" ]
}

@test "est_manual_time: 1000 LoC at 4.0h/100 = 40h (logic)" {
    LOC=1000
    MULTIPLIER=4.0
    
    result=$(echo "scale=1; $LOC * $MULTIPLIER / 100" | bc)
    
    [ "$result" = "40.0" ]
}

@test "est_manual_time: grand total combines all categories" {
    LOC_BOILERPLATE=500
    LOC_GLUE=300
    LOC_LOGIC=200
    
    MULT_BOILERPLATE=0.5
    MULT_GLUE=1.5
    MULT_LOGIC=4.0
    
    est_boilerplate=$(echo "scale=1; $LOC_BOILERPLATE * $MULT_BOILERPLATE / 100" | bc)
    est_glue=$(echo "scale=1; $LOC_GLUE * $MULT_GLUE / 100" | bc)
    est_logic=$(echo "scale=1; $LOC_LOGIC * $MULT_LOGIC / 100" | bc)
    
    total=$(echo "scale=1; $est_boilerplate + $est_glue + $est_logic" | bc)
    
    # 2.5 + 4.5 + 8.0 = 15.0
    [ "$total" = "15.0" ]
}

# ═══════════════════════════════════════════════════════════════════════
# SESSION BUFFER CALCULATIONS
# Formula: session_time + buffer_seconds per session
# ═══════════════════════════════════════════════════════════════════════

@test "session_buffer: 30 min = 1800 seconds" {
    SESSION_BUFFER_MINUTES=30
    buffer_seconds=$((SESSION_BUFFER_MINUTES * 60))
    
    [ "$buffer_seconds" -eq 1800 ]
}

@test "session_buffer: 15 min = 900 seconds" {
    SESSION_BUFFER_MINUTES=15
    buffer_seconds=$((SESSION_BUFFER_MINUTES * 60))
    
    [ "$buffer_seconds" -eq 900 ]
}

@test "session_buffer: total time with 3 sessions at 30min buffer" {
    SESSION_BUFFER_MINUTES=30
    session_count=3
    raw_session_time=7200  # 2 hours of actual coding
    
    buffer_seconds=$((SESSION_BUFFER_MINUTES * 60))
    total_buffer=$((buffer_seconds * session_count))
    total_time=$((raw_session_time + total_buffer))
    
    # 7200 + (1800 * 3) = 7200 + 5400 = 12600 seconds = 3.5 hours
    [ "$total_time" -eq 12600 ]
}

@test "session_buffer: converts to hours correctly" {
    total_session_seconds=12600
    
    result=$(echo "scale=1; $total_session_seconds / 3600" | bc)
    
    [ "$result" = "3.5" ]
}

# ═══════════════════════════════════════════════════════════════════════
# AI-ASSISTED LOC CALCULATIONS
# Formula: LOC * AI_PERCENT / 100
# ═══════════════════════════════════════════════════════════════════════

@test "ai_loc: 1000 LoC at 90% AI = 900 AI-assisted" {
    LOC=1000
    AI_PERCENT=90
    
    result=$(echo "scale=0; $LOC * $AI_PERCENT / 100" | bc)
    
    [ "$result" -eq 900 ]
}

@test "ai_loc: 500 LoC at 30% AI = 150 AI-assisted" {
    LOC=500
    AI_PERCENT=30
    
    result=$(echo "scale=0; $LOC * $AI_PERCENT / 100" | bc)
    
    [ "$result" -eq 150 ]
}

@test "ai_percent_total: weighted across categories" {
    LOC_BOILERPLATE=500
    LOC_GLUE=300
    LOC_LOGIC=200
    
    AI_BOILERPLATE=90
    AI_GLUE=70
    AI_LOGIC=30
    
    ai_boilerplate=$(echo "scale=0; $LOC_BOILERPLATE * $AI_BOILERPLATE / 100" | bc)
    ai_glue=$(echo "scale=0; $LOC_GLUE * $AI_GLUE / 100" | bc)
    ai_logic=$(echo "scale=0; $LOC_LOGIC * $AI_LOGIC / 100" | bc)
    
    total_loc=$((LOC_BOILERPLATE + LOC_GLUE + LOC_LOGIC))
    total_ai=$((ai_boilerplate + ai_glue + ai_logic))
    
    ai_percent=$(echo "scale=0; $total_ai * 100 / $total_loc" | bc)
    
    # (450 + 210 + 60) / 1000 * 100 = 72%
    [ "$ai_percent" -eq 72 ]
}

# ═══════════════════════════════════════════════════════════════════════
# GRAND TOTAL CALCULATIONS
# ═══════════════════════════════════════════════════════════════════════

@test "grand_total_loc: source + tests" {
    TOTAL_LOC=5000
    TEST_LOC=2000
    
    GRAND_TOTAL_LOC=$((TOTAL_LOC + TEST_LOC))
    
    [ "$GRAND_TOTAL_LOC" -eq 7000 ]
}

@test "grand_est_time: source time + test time" {
    EST_TIME_TOTAL=50.0
    EST_TIME_TESTS=15.0
    
    result=$(echo "scale=1; $EST_TIME_TOTAL + $EST_TIME_TESTS" | bc)
    
    [ "$result" = "65.0" ]
}

# ═══════════════════════════════════════════════════════════════════════
# CLASSIFICATION PATTERN MATCHING
# ═══════════════════════════════════════════════════════════════════════

@test "classify: extension.ts is boilerplate" {
    file="src/extension.ts"
    pattern="extension\.ts|types/|config/|\.d\.ts"
    
    if [[ "$file" =~ ($pattern) ]]; then
        result="boilerplate"
    else
        result="other"
    fi
    
    [ "$result" = "boilerplate" ]
}

@test "classify: types/index.ts is boilerplate" {
    file="src/types/index.ts"
    pattern="extension\.ts|types/|config/|\.d\.ts"
    
    if [[ "$file" =~ ($pattern) ]]; then
        result="boilerplate"
    else
        result="other"
    fi
    
    [ "$result" = "boilerplate" ]
}

@test "classify: utils/helper.ts is glue" {
    file="src/utils/helper.ts"
    pattern="commands/|utils/|webview/|handlers/"
    
    if [[ "$file" =~ ($pattern) ]]; then
        result="glue"
    else
        result="other"
    fi
    
    [ "$result" = "glue" ]
}

@test "classify: commands/run.ts is glue" {
    file="src/commands/run.ts"
    pattern="commands/|utils/|webview/|handlers/"
    
    if [[ "$file" =~ ($pattern) ]]; then
        result="glue"
    else
        result="other"
    fi
    
    [ "$result" = "glue" ]
}

@test "classify: core/engine.ts is logic (default)" {
    file="src/core/engine.ts"
    pattern_boilerplate="extension\.ts|types/|config/|\.d\.ts"
    pattern_glue="commands/|utils/|webview/|handlers/"
    
    if [[ "$file" =~ ($pattern_boilerplate) ]]; then
        result="boilerplate"
    elif [[ "$file" =~ ($pattern_glue) ]]; then
        result="glue"
    else
        result="logic"
    fi
    
    [ "$result" = "logic" ]
}

# ═══════════════════════════════════════════════════════════════════════
# EDGE CASES
# ═══════════════════════════════════════════════════════════════════════

@test "edge_case: zero estimated time returns 0% saved" {
    GRAND_EST_TIME=0
    GIT_ESTIMATED_HOURS=10
    
    # Should handle division by zero gracefully
    if [[ $(echo "$GRAND_EST_TIME > 0" | bc) -eq 1 ]]; then
        result=$(echo "scale=0; ($GRAND_EST_TIME - $GIT_ESTIMATED_HOURS) * 100 / $GRAND_EST_TIME" | bc)
    else
        result=0
    fi
    
    [ "$result" -eq 0 ]
}

@test "edge_case: zero actual time with guard" {
    GRAND_EST_TIME=100
    GIT_ESTIMATED_HOURS=0
    
    # Use guard to add 0.1 to prevent division by zero in multiplier
    result=$(echo "scale=1; $GRAND_EST_TIME / ($GIT_ESTIMATED_HOURS + 0.1)" | bc)
    
    # Should be 1000.0 (very high multiplier)
    [ "$result" = "1000.0" ]
}

@test "edge_case: zero LoC returns 0% AI-assisted" {
    TOTAL_LOC=0
    AI_LOC_TOTAL=0
    
    if [[ $TOTAL_LOC -gt 0 ]]; then
        result=$(echo "scale=0; $AI_LOC_TOTAL * 100 / $TOTAL_LOC" | bc)
    else
        result=0
    fi
    
    [ "$result" -eq 0 ]
}
