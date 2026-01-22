#!/usr/bin/env bats
# ═══════════════════════════════════════════════════════════════════════
# Integration Tests: Verify Report Output Consistency
# These tests run the actual script and verify numbers are internally consistent
# Run with: bats test/output-consistency.bats
# ═══════════════════════════════════════════════════════════════════════

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(dirname "$TEST_DIR")"
    SCRIPT="$PROJECT_ROOT/bin/analyze-impact"
    
    # Create a temporary test project
    TEST_PROJECT=$(mktemp -d)
    mkdir -p "$TEST_PROJECT/src/types"
    mkdir -p "$TEST_PROJECT/src/commands"
    mkdir -p "$TEST_PROJECT/src/core"
    mkdir -p "$TEST_PROJECT/test"
    mkdir -p "$TEST_PROJECT/specs"
    
    # Create sample source files with known LoC
    # Boilerplate: 10 lines
    cat > "$TEST_PROJECT/src/types/index.ts" << 'EOF'
export interface Config {
    name: string;
    value: number;
}

export type Result = {
    success: boolean;
    data: any;
};

export const VERSION = "1.0.0";
EOF
    
    # Glue code: 15 lines
    cat > "$TEST_PROJECT/src/commands/run.ts" << 'EOF'
import { Config } from '../types';

export function runCommand(config: Config): void {
    console.log('Running:', config.name);
    
    if (config.value > 0) {
        process.exit(0);
    }
}

export function stopCommand(): void {
    console.log('Stopping');
    process.exit(1);
}

export default { runCommand, stopCommand };
EOF
    
    # Core logic: 20 lines
    cat > "$TEST_PROJECT/src/core/engine.ts" << 'EOF'
export class Engine {
    private state: Map<string, any>;
    
    constructor() {
        this.state = new Map();
    }
    
    process(input: string): string {
        const tokens = input.split(' ');
        let result = '';
        
        for (const token of tokens) {
            result += this.transform(token);
        }
        
        return result;
    }
    
    private transform(token: string): string {
        return token.toUpperCase();
    }
}
EOF
    
    # Test file: 12 lines
    cat > "$TEST_PROJECT/test/engine.test.ts" << 'EOF'
import { Engine } from '../src/core/engine';

describe('Engine', () => {
    it('should process input', () => {
        const engine = new Engine();
        const result = engine.process('hello world');
        expect(result).toBe('HELLOWORLD');
    });
    
    it('should handle empty input', () => {
        const engine = new Engine();
        expect(engine.process('')).toBe('');
    });
});
EOF
    
    # Create minimal config
    cat > "$TEST_PROJECT/impact-config.yaml" << 'EOF'
project:
  name: "Test Project"
  type: "test"

paths:
  source: "src/"
  tests: "test/"
  specs: "specs/"
  exclude:
    - "node_modules"

classification:
  boilerplate:
    - "types/"
  glue_code:
    - "commands/"
  core_logic:
    - "core/"

multipliers:
  boilerplate: 0.5
  glue_code: 1.5
  core_logic: 4.0
  tests: 1.5

ai_percent:
  boilerplate: 90
  glue_code: 70
  core_logic: 30
  tests: 75
  efficiency_factor: 1.0

git:
  session_gap_hours: 2
  session_buffer_minutes: 30

speckit:
  enabled: false
EOF
    
    # Initialize git repo with commits
    cd "$TEST_PROJECT"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    git add -A
    git commit -q -m "Initial commit"
    sleep 1
    echo "// update" >> src/core/engine.ts
    git add -A
    git commit -q -m "Update"
}

teardown() {
    rm -rf "$TEST_PROJECT"
}

# ═══════════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════

extract_metric() {
    local report="$1"
    local pattern="$2"
    echo "$report" | grep -E "$pattern" | head -1 | sed -E 's/.*\| ([0-9.-]+).*/\1/' | tr -d ' h%'
}

extract_table_value() {
    local report="$1"
    local row_pattern="$2"
    local col_num="$3"
    echo "$report" | grep -E "$row_pattern" | head -1 | awk -F'|' "{print \$$col_num}" | tr -d ' h%()' | sed 's/[^0-9.-].*//g'
}

# ═══════════════════════════════════════════════════════════════════════
# CONSISTENCY TESTS
# ═══════════════════════════════════════════════════════════════════════

@test "output: script runs successfully on test project" {
    cd "$TEST_PROJECT"
    run "$SCRIPT" -q
    [ "$status" -eq 0 ]
    [ -f "IMPACT_REPORT.md" ]
}

@test "consistency: Source LoC and Test LoC are both reported" {
    cd "$TEST_PROJECT"
    "$SCRIPT" -q
    
    local report=$(cat IMPACT_REPORT.md)
    
    # Extract from Executive Summary and Test Code Impact sections
    local source_loc=$(echo "$report" | grep -E "\*\*Total Source LoC\*\*" | awk -F'|' '{print $3}' | tr -d ' ')
    local test_loc=$(echo "$report" | grep -E "\*\*Test LoC\*\*" | awk -F'|' '{print $3}' | tr -d ' ')
    
    # Verify both values are valid positive integers
    [ -n "$source_loc" ] && [ "$source_loc" -gt 0 ]
    [ -n "$test_loc" ] && [ "$test_loc" -ge 0 ]
}

@test "consistency: Category LoC sums to Total LoC" {
    cd "$TEST_PROJECT"
    "$SCRIPT" -q
    
    local report=$(cat IMPACT_REPORT.md)
    
    # Extract from Code Metrics Breakdown table
    local boilerplate_loc=$(echo "$report" | grep -E "^\| \*\*Boilerplate\*\*" | awk -F'|' '{print $4}' | tr -d ' ')
    local glue_loc=$(echo "$report" | grep -E "^\| \*\*Glue Code\*\*" | awk -F'|' '{print $4}' | tr -d ' ')
    local logic_loc=$(echo "$report" | grep -E "^\| \*\*Core Logic\*\*" | awk -F'|' '{print $4}' | tr -d ' ')
    local total_loc=$(echo "$report" | grep -E "^\| \*\*TOTAL\*\*" | head -1 | awk -F'|' '{print $4}' | tr -d ' ')
    
    local sum=$((boilerplate_loc + glue_loc + logic_loc))
    
    [ "$total_loc" -eq "$sum" ]
}

@test "consistency: AI-Assisted LoC <= Total LoC" {
    cd "$TEST_PROJECT"
    "$SCRIPT" -q
    
    local report=$(cat IMPACT_REPORT.md)
    
    # Extract from Executive Summary
    local total_loc=$(echo "$report" | grep -E "\*\*Total Source LoC\*\*" | awk -F'|' '{print $3}' | tr -d ' ')
    local ai_loc=$(echo "$report" | grep -E "\*\*AI-Assisted LoC\*\*" | awk -F'|' '{print $3}' | sed 's/ (.*//' | tr -d ' ')
    
    [ "$ai_loc" -le "$total_loc" ]
}

@test "consistency: Time Saved <= Estimated Manual Time" {
    cd "$TEST_PROJECT"
    "$SCRIPT" -q
    
    local report=$(cat IMPACT_REPORT.md)
    
    # Extract hours (strip 'h' suffix)
    local est_time=$(echo "$report" | grep -E "\*\*Estimated Manual Time\*\*" | awk -F'|' '{print $3}' | sed 's/h.*//' | tr -d ' ')
    local saved_hours=$(echo "$report" | grep -E "\*\*Time Saved\*\*" | awk -F'|' '{print $3}' | sed 's/h.*//' | tr -d ' ')
    
    # Convert to integers for comparison (multiply by 10 to handle decimals)
    local est_int=$(echo "$est_time * 10" | bc | cut -d'.' -f1)
    local saved_int=$(echo "$saved_hours * 10" | bc | cut -d'.' -f1)
    
    [ "$saved_int" -le "$est_int" ]
}

@test "consistency: Saved Percent matches (Est - Actual) / Est" {
    cd "$TEST_PROJECT"
    "$SCRIPT" -q
    
    local report=$(cat IMPACT_REPORT.md)
    
    # Extract values
    local est_time=$(echo "$report" | grep -E "\*\*Estimated Manual Time\*\*" | awk -F'|' '{print $3}' | sed 's/h.*//' | tr -d ' ')
    local actual_time=$(echo "$report" | grep -E "\*\*Actual Dev Time\*\*" | awk -F'|' '{print $3}' | sed 's/[^0-9.]//g')
    local saved_percent=$(echo "$report" | grep -E "\*\*Time Saved\*\*" | awk -F'|' '{print $3}' | grep -oE '[0-9]+%' | tr -d '%')
    
    # Calculate expected percent
    if [ -n "$est_time" ] && [ -n "$actual_time" ] && [ "$(echo "$est_time > 0" | bc)" -eq 1 ]; then
        local expected=$(echo "scale=0; ($est_time - $actual_time) * 100 / $est_time" | bc)
        
        # Allow 1% tolerance for rounding
        local diff=$((saved_percent - expected))
        [ "$diff" -ge -1 ] && [ "$diff" -le 1 ]
    fi
}

@test "consistency: Productivity Multiplier = Est Time / Actual Time" {
    cd "$TEST_PROJECT"
    "$SCRIPT" -q
    
    local report=$(cat IMPACT_REPORT.md)
    
    # Extract from Key Insights
    local est_traditional=$(echo "$report" | grep "Traditional Development:" | sed 's/.*: *//' | sed 's/h.*//')
    local actual=$(echo "$report" | grep "AI-Assisted Development:" | sed 's/.*: *//' | sed 's/h.*//')
    local multiplier=$(echo "$report" | grep "Productivity Gain:" | sed 's/.*~//;s/x.*//')
    
    if [ -n "$est_traditional" ] && [ -n "$actual" ] && [ "$(echo "$actual > 0" | bc)" -eq 1 ]; then
        local expected=$(echo "scale=1; $est_traditional / $actual" | bc)
        
        # Compare (allow 0.2 tolerance)
        local diff=$(echo "scale=1; $multiplier - $expected" | bc)
        local abs_diff=$(echo "$diff" | tr -d '-')
        [ "$(echo "$abs_diff <= 0.2" | bc)" -eq 1 ]
    fi
}

@test "consistency: Category percentages are valid (0-100)" {
    cd "$TEST_PROJECT"
    "$SCRIPT" -q
    
    local report=$(cat IMPACT_REPORT.md)
    
    # Check each AI% in the breakdown table
    for row in "Boilerplate" "Glue Code" "Core Logic"; do
        local percent=$(echo "$report" | grep -E "^\| \*\*$row\*\*" | grep -oE '[0-9]+%' | head -1 | tr -d '%')
        if [ -n "$percent" ]; then
            [ "$percent" -ge 0 ] && [ "$percent" -le 100 ]
        fi
    done
}

@test "consistency: JSON output matches markdown report" {
    cd "$TEST_PROJECT"
    "$SCRIPT" -q -j
    
    [ -f "impact-metrics.json" ]
    
    local json=$(cat impact-metrics.json)
    local report=$(cat IMPACT_REPORT.md)
    
    # Extract from JSON
    local json_total_loc=$(echo "$json" | jq '.code.total_loc')
    local json_saved_percent=$(echo "$json" | jq '.time.saved_percent')
    
    # Extract from markdown
    local md_total_loc=$(echo "$report" | grep -E "\*\*Total Source LoC\*\*" | awk -F'|' '{print $3}' | tr -d ' ')
    local md_saved_percent=$(echo "$report" | grep -E "\*\*Time Saved\*\*" | grep -oE '[0-9]+%' | tr -d '%')
    
    [ "$json_total_loc" -eq "$md_total_loc" ]
    [ "$json_saved_percent" -eq "$md_saved_percent" ]
}

@test "consistency: Grand Total AI LoC = Source AI LoC + Test AI LoC" {
    cd "$TEST_PROJECT"
    "$SCRIPT" -q -j
    
    local json=$(cat impact-metrics.json)
    
    local source_ai=$(echo "$json" | jq '.ai_assisted.total_loc')
    local test_ai=$(echo "$json" | jq '.tests.ai_loc')
    local grand_ai=$(echo "$json" | jq '.grand_total.ai_loc')
    
    local expected=$((source_ai + test_ai))
    
    [ "$grand_ai" -eq "$expected" ]
}

@test "consistency: Est Manual Hours breakdown sums correctly" {
    cd "$TEST_PROJECT"
    "$SCRIPT" -q
    
    local report=$(cat IMPACT_REPORT.md)
    
    # Extract from breakdown table - Est. Manual column
    local bp_time=$(echo "$report" | grep -E "^\| \*\*Boilerplate\*\*" | awk -F'|' '{print $6}' | sed 's/h//' | tr -d ' ')
    local glue_time=$(echo "$report" | grep -E "^\| \*\*Glue Code\*\*" | awk -F'|' '{print $6}' | sed 's/h//' | tr -d ' ')
    local logic_time=$(echo "$report" | grep -E "^\| \*\*Core Logic\*\*" | awk -F'|' '{print $6}' | sed 's/h//' | tr -d ' ')
    local total_time=$(echo "$report" | grep -E "^\| \*\*TOTAL\*\*" | head -1 | awk -F'|' '{print $6}' | sed 's/h//' | tr -d ' ')
    
    # Sum with bc
    local sum=$(echo "scale=1; $bp_time + $glue_time + $logic_time" | bc)
    
    # Compare (allow 0.1 tolerance for rounding)
    local diff=$(echo "scale=1; $total_time - $sum" | bc)
    local abs_diff=$(echo "$diff" | tr -d '-')
    [ "$(echo "$abs_diff <= 0.1" | bc)" -eq 1 ]
}

@test "consistency: No negative values in positive metrics" {
    cd "$TEST_PROJECT"
    "$SCRIPT" -q -j
    
    local json=$(cat impact-metrics.json)
    
    # These should never be negative
    local total_loc=$(echo "$json" | jq '.code.total_loc')
    local total_files=$(echo "$json" | jq '.code.total_files')
    local ai_loc=$(echo "$json" | jq '.ai_assisted.total_loc')
    local est_hours=$(echo "$json" | jq '.time.estimated_manual_hours')
    
    [ "$total_loc" -ge 0 ]
    [ "$total_files" -ge 0 ]
    [ "$ai_loc" -ge 0 ]
    [ "$(echo "$est_hours >= 0" | bc)" -eq 1 ]
}

# ═══════════════════════════════════════════════════════════════════════
# DIFF MODE INTEGRATION TESTS
# These tests use the git repo already set up in setup()
# ═══════════════════════════════════════════════════════════════════════

@test "diff mode: --since triggers diff mode" {
    cd "$TEST_PROJECT"
    
    # Get baseline before adding new file
    local baseline=$(git rev-parse HEAD)
    
    # Add a new file after initial setup
    echo "const newFeature = true;" > "$TEST_PROJECT/src/feature.ts"
    git add .
    git commit -q -m "add feature"
    
    # Run in diff mode (since a week ago should catch our commits)
    "$SCRIPT" -q -j --since "1 week ago"
    
    local json=$(cat impact-metrics.json)
    
    # Verify diff mode was used
    local mode=$(echo "$json" | jq -r '.analysis_mode')
    [ "$mode" = "diff" ]
    
    local diff_enabled=$(echo "$json" | jq '.diff.enabled')
    [ "$diff_enabled" = "true" ]
}

@test "diff mode: --baseline triggers diff mode" {
    cd "$TEST_PROJECT"
    
    # Get current HEAD as baseline
    local baseline=$(git rev-parse HEAD)
    
    # Add more files
    echo "const update = 1;" > "$TEST_PROJECT/src/update.ts"
    git add .
    git commit -q -m "update"
    
    # Run with baseline comparison
    "$SCRIPT" -q -j --baseline "$baseline"
    
    local json=$(cat impact-metrics.json)
    
    local mode=$(echo "$json" | jq -r '.analysis_mode')
    [ "$mode" = "diff" ]
    
    local commits=$(echo "$json" | jq '.diff.commits')
    [ "$commits" -ge 1 ]
}

@test "diff mode: reports lines added/removed correctly" {
    cd "$TEST_PROJECT"
    
    local baseline=$(git rev-parse HEAD)
    
    # Add new file with known lines (5 lines)
    cat > "$TEST_PROJECT/src/newfile.ts" << 'EOF'
line1
line2
line3
line4
line5
EOF
    git add .
    git commit -q -m "add 5 lines"
    
    "$SCRIPT" -q -j --baseline "$baseline"
    
    local json=$(cat impact-metrics.json)
    
    local lines_added=$(echo "$json" | jq '.diff.lines_added')
    local files_created=$(echo "$json" | jq '.diff.files_created')
    
    # Should have exactly 5 lines added and 1 file created
    [ "$lines_added" -eq 5 ]
    [ "$files_created" -eq 1 ]
}

@test "diff mode: net_lines = lines_added - lines_removed" {
    cd "$TEST_PROJECT"
    
    local baseline=$(git rev-parse HEAD)
    
    # Modify a file (replace 20+ lines with 1 line)
    echo "new content" > "$TEST_PROJECT/src/core/engine.ts"
    git add .
    git commit -q -m "modify file"
    
    "$SCRIPT" -q -j --baseline "$baseline"
    
    local json=$(cat impact-metrics.json)
    
    local added=$(echo "$json" | jq '.diff.lines_added')
    local removed=$(echo "$json" | jq '.diff.lines_removed')
    local net=$(echo "$json" | jq '.diff.net_lines')
    
    # Verify net = added - removed
    local expected=$((added - removed))
    [ "$net" -eq "$expected" ]
}

@test "diff mode: snapshot mode when no diff options provided" {
    cd "$TEST_PROJECT"
    
    # Run without diff options
    "$SCRIPT" -q -j
    
    local json=$(cat impact-metrics.json)
    
    local mode=$(echo "$json" | jq -r '.analysis_mode')
    [ "$mode" = "snapshot" ]
    
    local diff_enabled=$(echo "$json" | jq '.diff.enabled')
    [ "$diff_enabled" = "false" ]
}

@test "diff mode: report shows Change Scope section" {
    cd "$TEST_PROJECT"
    
    local baseline=$(git rev-parse HEAD)
    
    echo "feature" > "$TEST_PROJECT/src/feat.ts"
    git add .
    git commit -q -m "feature"
    
    "$SCRIPT" -q --baseline "$baseline"
    
    local report=$(cat IMPACT_REPORT.md)
    
    # Should have diff-specific sections
    echo "$report" | grep -q "Change Scope"
    echo "$report" | grep -q "Diff Mode"
    echo "$report" | grep -q "Lines Added"
}

@test "diff mode: classifies test changes correctly" {
    cd "$TEST_PROJECT"
    
    local baseline=$(git rev-parse HEAD)
    
    # Add test file (should be classified as test)
    cat > "$TEST_PROJECT/test/newtest.ts" << 'EOF'
describe('test', () => {
    it('works', () => {
        expect(true).toBe(true);
    });
});
EOF
    git add .
    git commit -q -m "add test"
    
    "$SCRIPT" -q -j --baseline "$baseline"
    
    local json=$(cat impact-metrics.json)
    
    local test_loc=$(echo "$json" | jq '.tests.loc')
    
    # Test file has 5 lines
    [ "$test_loc" -eq 5 ]
}

@test "diff mode: excludes node_modules from diff" {
    cd "$TEST_PROJECT"
    
    local baseline=$(git rev-parse HEAD)
    
    # Add node_modules file (should be excluded)
    mkdir -p "$TEST_PROJECT/node_modules/pkg"
    echo "module.exports = {}" > "$TEST_PROJECT/node_modules/pkg/index.js"
    
    # Add source file (1 line)
    echo "const x = 1;" > "$TEST_PROJECT/src/x.ts"
    
    git add -f .
    git commit -q -m "add files"
    
    "$SCRIPT" -q -j --baseline "$baseline"
    
    local json=$(cat impact-metrics.json)
    
    # lines_added should only include src/x.ts (1 line), not node_modules
    local lines_added=$(echo "$json" | jq '.diff.lines_added')
    [ "$lines_added" -eq 1 ]
}
