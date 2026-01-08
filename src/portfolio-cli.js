#!/usr/bin/env node
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

const isWindows = process.platform === 'win32';
const bashScript = path.join(__dirname, '..', 'bin', 'aggregate-portfolio');

if (isWindows) {
  const gitBashPaths = [
    'C:\\Program Files\\Git\\bin\\bash.exe',
    'C:\\Program Files (x86)\\Git\\bin\\bash.exe'
  ];
  let bashPath = gitBashPaths.find(p => fs.existsSync(p)) || 'bash';
  const child = spawn(bashPath, [bashScript, ...process.argv.slice(2)], { stdio: 'inherit' });
  child.on('exit', code => process.exit(code));
} else {
  const child = spawn('bash', [bashScript, ...process.argv.slice(2)], { stdio: 'inherit' });
  child.on('exit', code => process.exit(code || 0));
}
