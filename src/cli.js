#!/usr/bin/env node
/**
 * Spec-Kit Impact Analyzer - Cross-platform CLI wrapper
 * Provides Node.js fallback for Windows while using bash on Unix
 */

const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

const isWindows = process.platform === 'win32';
const binDir = path.join(__dirname, '..', 'bin');
const bashScript = path.join(binDir, 'analyze-impact');

// Check if bash script exists
if (!fs.existsSync(bashScript)) {
  console.error('Error: analyze-impact script not found at', bashScript);
  process.exit(1);
}

if (isWindows) {
  // Try WSL first, then Git Bash
  const wslCheck = spawn('wsl', ['--version'], { shell: true, stdio: 'pipe' });
  
  wslCheck.on('error', () => {
    // WSL not available, try Git Bash
    const gitBashPaths = [
      'C:\\Program Files\\Git\\bin\\bash.exe',
      'C:\\Program Files (x86)\\Git\\bin\\bash.exe'
    ];
    
    let bashPath = gitBashPaths.find(p => fs.existsSync(p));
    
    if (!bashPath) {
      console.error('Error: Windows requires either WSL or Git Bash');
      console.error('Install one of:');
      console.error('  - WSL: wsl --install');
      console.error('  - Git for Windows: https://git-scm.com/download/win');
      process.exit(1);
    }
    
    // Run with Git Bash
    const child = spawn(bashPath, [bashScript, ...process.argv.slice(2)], {
      stdio: 'inherit',
      cwd: process.cwd()
    });
    child.on('exit', code => process.exit(code));
  });

  wslCheck.on('exit', (code) => {
    if (code === 0) {
      // WSL available, use it
      const wslPath = bashScript.replace(/\\/g, '/').replace(/^([A-Z]):/, (_, drive) => `/mnt/${drive.toLowerCase()}`);
      const child = spawn('wsl', ['bash', wslPath, ...process.argv.slice(2)], {
        stdio: 'inherit',
        cwd: process.cwd()
      });
      child.on('exit', code => process.exit(code));
    }
  });
} else {
  // Unix - run directly
  const child = spawn('bash', [bashScript, ...process.argv.slice(2)], {
    stdio: 'inherit',
    cwd: process.cwd()
  });
  child.on('exit', code => process.exit(code || 0));
}
