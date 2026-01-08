#!/usr/bin/env node
/**
 * Spec-Kit Impact Analyzer - Config Initializer
 * Auto-generates impact-config.yaml based on project structure
 */

const fs = require('fs');
const path = require('path');
const { program } = require('commander');

// ANSI colors (works on Windows too)
const colors = {
  reset: '\x1b[0m',
  bold: '\x1b[1m',
  red: '\x1b[31m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  cyan: '\x1b[36m'
};

const log = {
  info: (msg) => console.log(`${colors.blue}ℹ${colors.reset} ${msg}`),
  success: (msg) => console.log(`${colors.green}✓${colors.reset} ${msg}`),
  warn: (msg) => console.log(`${colors.yellow}⚠${colors.reset} ${msg}`),
  error: (msg) => console.error(`${colors.red}✗${colors.reset} ${msg}`)
};

// Project type detection based on files present
function detectProjectType(projectPath) {
  const checks = {
    'vscode-extension': ['package.json', () => {
      try {
        const pkg = JSON.parse(fs.readFileSync(path.join(projectPath, 'package.json'), 'utf8'));
        return pkg.engines?.vscode || pkg.contributes;
      } catch { return false; }
    }],
    'astro': ['astro.config.mjs', 'astro.config.ts'],
    'nextjs': ['next.config.js', 'next.config.mjs', 'next.config.ts'],
    'react': ['package.json', () => {
      try {
        const pkg = JSON.parse(fs.readFileSync(path.join(projectPath, 'package.json'), 'utf8'));
        return pkg.dependencies?.react || pkg.devDependencies?.react;
      } catch { return false; }
    }],
    'vue': ['vue.config.js', 'vite.config.ts'],
    'python': ['setup.py', 'pyproject.toml', 'requirements.txt'],
    'rust': ['Cargo.toml'],
    'go': ['go.mod'],
    'node': ['package.json']
  };

  for (const [type, indicators] of Object.entries(checks)) {
    for (const indicator of indicators) {
      if (typeof indicator === 'function') {
        if (indicator()) return type;
      } else if (fs.existsSync(path.join(projectPath, indicator))) {
        return type;
      }
    }
  }
  return 'generic';
}

// Detect project name from package.json or directory
function detectProjectName(projectPath) {
  try {
    const pkgPath = path.join(projectPath, 'package.json');
    if (fs.existsSync(pkgPath)) {
      const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
      if (pkg.displayName) return pkg.displayName;
      if (pkg.name) return pkg.name.split('/').pop().replace(/-/g, ' ').replace(/\b\w/g, l => l.toUpperCase());
    }
  } catch {}
  return path.basename(projectPath).replace(/-/g, ' ').replace(/\b\w/g, l => l.toUpperCase());
}

// Find specs directory
function findSpecsDir(projectPath) {
  const candidates = ['specs', 'spec', 'docs/specs', '.specs', 'documentation'];
  for (const dir of candidates) {
    if (fs.existsSync(path.join(projectPath, dir))) return dir;
  }
  return 'specs';
}

// Find source directory
function findSourceDir(projectPath) {
  const candidates = ['src', 'lib', 'app', 'source'];
  for (const dir of candidates) {
    if (fs.existsSync(path.join(projectPath, dir))) return dir;
  }
  return 'src';
}

// Find test directory
function findTestDir(projectPath) {
  const candidates = ['test', 'tests', '__tests__', 'spec'];
  for (const dir of candidates) {
    if (fs.existsSync(path.join(projectPath, dir))) return dir;
  }
  return 'test';
}

// Get project-specific config templates
function getProjectTemplate(type) {
  const templates = {
    'vscode-extension': {
      classification: {
        boilerplate: ['extension.ts', 'types/**/*', '*.d.ts', 'config/**/*'],
        glue_code: ['commands/**/*', 'utils/**/*', 'webview/**/*', 'handlers/**/*'],
        core_logic: ['conversion/**/*', 'parsers/**/*', 'core/**/*']
      },
      multipliers: { boilerplate: 0.5, glue_code: 1.5, core_logic: 4.0 },
      ai_percent: { boilerplate: 90, glue_code: 70, core_logic: 35 }
    },
    'astro': {
      classification: {
        boilerplate: ['content/config.ts', 'layouts/**/*', '*.config.*'],
        glue_code: ['components/**/*', 'pages/**/*'],
        core_logic: ['content/**/*.md', 'content/**/*.json', 'lib/**/*']
      },
      multipliers: { boilerplate: 0.8, glue_code: 3.0, core_logic: 2.0 },
      ai_percent: { boilerplate: 90, glue_code: 75, core_logic: 60 }
    },
    'nextjs': {
      classification: {
        boilerplate: ['next.config.*', 'types/**/*', 'lib/config.*'],
        glue_code: ['components/**/*', 'pages/**/*', 'app/**/*'],
        core_logic: ['lib/**/*', 'services/**/*', 'api/**/*']
      },
      multipliers: { boilerplate: 0.5, glue_code: 2.0, core_logic: 3.5 },
      ai_percent: { boilerplate: 90, glue_code: 70, core_logic: 40 }
    },
    'react': {
      classification: {
        boilerplate: ['types/**/*', 'config/**/*', '*.config.*'],
        glue_code: ['components/**/*', 'hooks/**/*', 'pages/**/*'],
        core_logic: ['services/**/*', 'utils/**/*', 'lib/**/*']
      },
      multipliers: { boilerplate: 0.5, glue_code: 2.0, core_logic: 3.0 },
      ai_percent: { boilerplate: 90, glue_code: 70, core_logic: 40 }
    },
    'python': {
      classification: {
        boilerplate: ['__init__.py', 'setup.py', 'config/**/*'],
        glue_code: ['cli/**/*', 'utils/**/*', 'handlers/**/*'],
        core_logic: ['core/**/*', 'lib/**/*', 'engine/**/*']
      },
      multipliers: { boilerplate: 0.5, glue_code: 1.5, core_logic: 4.0 },
      ai_percent: { boilerplate: 90, glue_code: 65, core_logic: 35 }
    },
    'rust': {
      classification: {
        boilerplate: ['build.rs', 'lib.rs', 'config/**/*'],
        glue_code: ['cli/**/*', 'utils/**/*', 'handlers/**/*'],
        core_logic: ['core/**/*', 'parser/**/*', 'engine/**/*']
      },
      multipliers: { boilerplate: 0.8, glue_code: 2.0, core_logic: 5.0 },
      ai_percent: { boilerplate: 85, glue_code: 50, core_logic: 25 }
    },
    'generic': {
      classification: {
        boilerplate: ['config/**/*', 'types/**/*'],
        glue_code: ['utils/**/*', 'helpers/**/*'],
        core_logic: ['core/**/*', 'lib/**/*', 'src/**/*']
      },
      multipliers: { boilerplate: 0.5, glue_code: 1.5, core_logic: 4.0 },
      ai_percent: { boilerplate: 90, glue_code: 70, core_logic: 35 }
    }
  };
  return templates[type] || templates.generic;
}

function generateConfig(projectPath, options) {
  const absPath = path.resolve(projectPath);
  
  if (!fs.existsSync(absPath)) {
    log.error(`Directory not found: ${absPath}`);
    process.exit(1);
  }

  const projectType = options.type || detectProjectType(absPath);
  const projectName = options.name || detectProjectName(absPath);
  const template = getProjectTemplate(projectType);
  
  log.info(`Detected project type: ${projectType}`);
  log.info(`Project name: ${projectName}`);

  const config = `# Spec-Kit Impact Analyzer Configuration
# Generated automatically - adjust as needed for your project

project:
  name: "${projectName}"
  type: "${projectType}"
  description: ""

paths:
  source: "${findSourceDir(absPath)}/"
  tests: "${findTestDir(absPath)}/"
  specs: "${findSpecsDir(absPath)}/"
  exclude:
    - "node_modules"
    - "dist"
    - "build"
    - ".git"
    - "coverage"

# File classification patterns
# Adjust these based on your actual project structure
classification:
  boilerplate:
${template.classification.boilerplate.map(p => `    - "${p}"`).join('\n')}
    
  glue_code:
${template.classification.glue_code.map(p => `    - "${p}"`).join('\n')}
    
  core_logic:
${template.classification.core_logic.map(p => `    - "${p}"`).join('\n')}

# Time multipliers (hours per 100 LoC without AI assistance)
# Adjust based on project complexity
multipliers:
  boilerplate: ${template.multipliers.boilerplate}
  glue_code: ${template.multipliers.glue_code}
  core_logic: ${template.multipliers.core_logic}

# AI assistance percentage estimates
# Lower for complex/unique code, higher for standard patterns
ai_percent:
  boilerplate: ${template.ai_percent.boilerplate}
  glue_code: ${template.ai_percent.glue_code}
  core_logic: ${template.ai_percent.core_logic}

# Git analysis settings
git:
  session_gap_hours: 2
  session_buffer_minutes: 30
  exclude_authors:
    - "dependabot[bot]"
    - "semantic-release-bot"

# Spec-Kit settings
speckit:
  enabled: true
  task_pattern: "(\\\\*\\\\*)?T[0-9]+"
`;

  const configPath = path.join(absPath, 'impact-config.yaml');
  
  if (fs.existsSync(configPath) && !options.force) {
    log.warn(`Config already exists: ${configPath}`);
    log.info('Use --force to overwrite');
    return;
  }

  fs.writeFileSync(configPath, config);
  log.success(`Created: ${configPath}`);
  log.info('');
  log.info('Next steps:');
  log.info('  1. Review and adjust the config file');
  log.info('  2. Run: speckit-analyze ' + absPath);
}

program
  .name('speckit-init')
  .description('Initialize impact-config.yaml for a project')
  .version('1.0.0')
  .argument('[path]', 'Project path', '.')
  .option('-t, --type <type>', 'Force project type (vscode-extension, astro, nextjs, react, python, rust, go, node)')
  .option('-n, --name <name>', 'Override project name')
  .option('-f, --force', 'Overwrite existing config')
  .action(generateConfig);

program.parse();
