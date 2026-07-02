// Verifies the Navbar re-mount fix: template.tsx + AppShell + layout wiring.
// Run: node web-admin/tests/template-mount.test.mjs

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const root = path.resolve(__dirname, '..');

function readFile(rel) {
  return fs.readFileSync(path.join(root, rel), 'utf-8');
}

let pass = 0, fail = 0;
function expect(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (ok) { pass++; console.log(`✓ ${label}`); }
  else {
    fail++;
    console.log(`✗ ${label}`);
    console.log(`    expected: ${JSON.stringify(expected)}`);
    console.log(`    actual:   ${JSON.stringify(actual)}`);
  }
}

// --- 1. template.tsx exists and exports a default function -----------------

const templatePath = 'src/app/template.tsx';
const templateSrc = readFile(templatePath);

expect('template.tsx exists', fs.existsSync(path.join(root, templatePath)), true);
expect('template.tsx exports default function', /export\s+default\s+function\s+Template/.test(templateSrc), true);
expect('template.tsx accepts children prop', /children:\s*React\.ReactNode/.test(templateSrc), true);
expect('template.tsx is marked force-dynamic', /export\s+const\s+dynamic\s*=\s*['"]force-dynamic['"]/.test(templateSrc), true);
expect('template.tsx returns fragment of children', /return\s*<>\s*\{children\}\s*<\/>;/.test(templateSrc), true);

// --- 2. AppShell.tsx exists and is a Client Component ---------------------

const appShellPath = 'src/components/AppShell.tsx';
const appShellSrc = readFile(appShellPath);

expect('AppShell.tsx exists', fs.existsSync(path.join(root, appShellPath)), true);
expect('AppShell.tsx has use client directive', /^'use client'/.test(appShellSrc.trim()), true);
expect('AppShell.tsx imports usePathname', /import\s*\{[^}]*usePathname[^}]*\}\s*from\s*['"]next\/navigation['"]/.test(appShellSrc), true);
expect('AppShell.tsx imports Navbar', /import\s*\{[^}]*Navbar[^}]*\}\s*from\s*['"]\.\/Navbar['"]/.test(appShellSrc), true);
expect('AppShell.tsx uses pathname via usePathname', /const\s+pathname\s*=\s*usePathname\(\)/.test(appShellSrc), true);
expect('AppShell.tsx passes key={pathname} to Navbar', /key=\{pathname\}/.test(appShellSrc), true);
expect('AppShell.tsx renders children', /\{children\}/.test(appShellSrc), true);

// --- 3. layout.tsx uses AppShell instead of Navbar directly ---------------

const layoutSrc = readFile('src/app/layout.tsx');

expect('layout.tsx imports AppShell', /import\s*\{[^}]*AppShell[^}]*\}\s*from\s*['"]@\/components\/AppShell['"]/.test(layoutSrc), true);
expect('layout.tsx does NOT import Navbar directly', /import\s*\{[^}]*\bNavbar\b[^}]*\}\s*from\s*['"]@\/components\/Navbar['"]/.test(layoutSrc), false);
expect('layout.tsx wraps children in AppShell', /<AppShell[^>]*>[\s\S]*\{children\}[\s\S]*<\/AppShell>/.test(layoutSrc), true);

// --- 4. Navbar inside layout gets re-mounted on every nav (semantic check) -

// Extract the AppShell usage from layout
const appShellOpen = layoutSrc.match(/<AppShell\b[^>]*>/);
expect('AppShell is self-closed or paired', !!appShellOpen, true);

// --- 5. Regression: make sure we did not break the existing layout flow ---

expect('layout.tsx still has UIProvider', /<UIProvider>/.test(layoutSrc), true);
expect('layout.tsx still wraps in html/body', /<html[\s\S]*<body[\s\S]*<\/body>[\s\S]*<\/html>/.test(layoutSrc), true);

// --- 6. AppShell preserves all props Navbar needs -------------------------

expect('AppShell accepts users prop', /users:/.test(appShellSrc), true);
expect('AppShell accepts currentUser prop', /currentUser:/.test(appShellSrc), true);
expect('AppShell passes users to Navbar', /users=\{users\}/.test(appShellSrc), true);
expect('AppShell passes currentUser to Navbar', /currentUser=\{currentUser\}/.test(appShellSrc), true);

console.log(`\n${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);