#!/usr/bin/env node
// Headless smoke for render.js. No Xcode or Simulator required.
// Run: node scripts/render-smoke.js

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const renderPath = path.join(__dirname, '..', 'FlatNote', 'Resources', 'render.js');
const src = fs.readFileSync(renderPath, 'utf8');
const ctx = {};
vm.createContext(ctx);
vm.runInContext(src, ctx);
const render = ctx.renderMarkdown;
if (typeof render !== 'function') {
    fail('renderMarkdown is not defined');
}

let failed = 0;
function fail(msg) {
    failed += 1;
    console.error('FAIL  ' + msg);
}
function ok(msg) {
    console.log('ok    ' + msg);
}
function expect(cond, msg) {
    if (cond) ok(msg);
    else fail(msg);
}

function textContent(html) {
    return html
        .replace(/<[^>]+>/g, '')
        .replace(/&lt;/g, '<')
        .replace(/&gt;/g, '>')
        .replace(/&amp;/g, '&')
        .replace(/&quot;/g, '"');
}

function lineText(html, n) {
    const re = new RegExp(
        '<(?:div|tr)\\b[^>]*\\bdata-line="' + n + '"[^>]*>([\\s\\S]*?)</(?:div|tr)>'
    );
    const m = html.match(re);
    return m ? textContent(m[1]) : null;
}

// Kate's Boaz disposition matrix (the bug-report screenshot).
const kate = [
    '5. Boaz disposition matrix',
    '',
    'This is a responsibility-level matrix.',
    '',
    '|Existing pattern or capability|Proposed disposition|Acceptance condition|',
    '|---|---|---|',
    '|Source ingestion and artifact storage|Retain if compliant|Preserves originals, identity, acquisition context, and addressable evidence.|',
    '|Provenance ledger|Retain and strengthen|Tracks transformations and dependencies, not merely citations.|',
    '|Phenomenological intake|Retain or rebuild|Preserves original accounts and separates experience from interpretation.|',
].join('\n');

const kateHtml = render(kate);
expect(kateHtml.includes('<table class="md-table">'), 'Kate fixture emits a real <table>');
expect(kateHtml.includes('<thead>'), 'Kate fixture has <thead>');
expect(kateHtml.includes('<th>'), 'Kate fixture has <th> header cells');
expect(kateHtml.includes('<td>'), 'Kate fixture has <td> body cells');
expect(kateHtml.includes('Existing pattern or capability'), 'header cell 1 present');
expect(kateHtml.includes('Proposed disposition'), 'header cell 2 present');
expect(kateHtml.includes('Acceptance condition'), 'header cell 3 present');
expect(kateHtml.includes('Source ingestion and artifact storage'), 'body cell present');
expect(kateHtml.includes('class="mk">|</span>'), 'pipes remain in the DOM as .mk markers');
expect(!kateHtml.includes('|---|---|---|') || kateHtml.includes('line-table-sep'),
    'delimiter row is a table line, not raw preview text only');

// Per-row source invariant (editor cursor mapping).
const tableLines = kate.split('\n');
for (let i = 0; i < tableLines.length; i++) {
    const got = lineText(kateHtml, i);
    expect(got === tableLines[i], 'textContent === source for line ' + i +
        (got === tableLines[i] ? '' : ' (got ' + JSON.stringify(got) + ')'));
}

// Spaced GFM + alignment colons.
const aligned = render('| left | center | right |\n|:-----|:------:|------:|\n| a | b | c |');
expect(aligned.includes('align-left'), 'left alignment class');
expect(aligned.includes('align-center'), 'center alignment class');
expect(aligned.includes('align-right'), 'right alignment class');
expect(lineText(aligned, 0) === '| left | center | right |', 'aligned header source intact');
expect(lineText(aligned, 1) === '|:-----|:------:|------:|', 'aligned delimiter source intact');

// A lone pipe line is not a table.
const lone = render('| not a table | just pipes |');
expect(!lone.includes('<table'), 'no separator → no table');
expect(textContent(lone) === '| not a table | just pipes |', 'lone pipe line source intact');

// Fenced source stays code, not a table.
const fenced = render('```\n| a | b |\n|---|---|\n| c | d |\n```');
expect(!fenced.includes('<table'), 'fenced table source is not rendered as a table');
expect(fenced.includes('line-code-block'), 'fenced rows stay code lines');

// A thematic break is still an HR, not a one-column table.
const hr = render('---');
expect(hr.includes('line-hr'), '--- remains a horizontal rule');
expect(!hr.includes('<table'), '--- is not a table');

// A heading after a table is its own block, not another row.
const interrupted = render('| a | b |\n|---|---|\n| c | d |\n## Next');
expect(interrupted.includes('<table class="md-table">'), 'interrupted fixture still has a table');
expect(interrupted.includes('line-h2'), 'heading after table stays a heading');
expect(lineText(interrupted, 3) === '## Next', 'heading line source intact');

if (failed) {
    console.error('\n' + failed + ' check(s) failed');
    process.exit(1);
}
console.log('\nAll render-smoke checks passed.');
