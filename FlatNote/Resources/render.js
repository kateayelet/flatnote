// Pure markdown -> HTML line renderer for FlatNote's live editor.
//
// No DOM dependencies, so it can be unit-tested in JavaScriptCore.
// Exposed as the global renderMarkdown(md) -> String.
//
// Key rule: every line element's textContent must === the markdown source
// line. Styling is done via spans that wrap parts of the text, but ALL text
// is present, which is what keeps the editor's cursor offsets exact. Most
// lines are <div class="line">; GFM tables use <tr class="line"> inside a
// real <table> so columns line up without changing the source on disk.

function esc(s) {
    return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function mkDiv(i, cls, content) {
    return '<div class="line ' + cls + '" data-line="' + i + '">' + content + '</div>';
}

// GFM pipe tables. A header row plus a delimiter row (`|---|---|`) opens a
// table; following pipe rows stay in it until a blank or non-pipe line.
// Each <tr> keeps data-line and textContent === the source line (pipes live
// in hidden .mk spans) so the editor's cursor offsets stay exact.

function splitTableCells(line) {
    const cells = [];
    let current = '';
    let i = 0;
    const leadingPipe = line[0] === '|';
    if (leadingPipe) i = 1;
    while (i < line.length) {
        if (line[i] === '\\' && line[i + 1] === '|') {
            current += '\\|';
            i += 2;
            continue;
        }
        if (line[i] === '|') {
            cells.push(current);
            current = '';
            i++;
            continue;
        }
        current += line[i];
        i++;
    }
    const trailingPipe = line.length > 0 && line[line.length - 1] === '|'
        && (line.length < 2 || line[line.length - 2] !== '\\');
    if (!trailingPipe) cells.push(current);
    return { cells: cells, leadingPipe: leadingPipe, trailingPipe: trailingPipe };
}

function isSeparatorRow(line) {
    if (line.indexOf('|') === -1) return false;
    const cells = splitTableCells(line).cells;
    if (!cells.length) return false;
    return cells.every(function (c) { return /^\s*:?-{1,}:?\s*$/.test(c); });
}

function looksLikeTableHeader(line) {
    return line.indexOf('|') !== -1 && !isSeparatorRow(line);
}

function isTableBodyRow(line) {
    if (line.indexOf('|') === -1 || /^```/.test(line)) return false;
    // Headings and quotes are their own blocks; don't swallow them as rows.
    if (/^#{1,6}\s/.test(line) || /^>\s?/.test(line)) return false;
    return true;
}

function parseAligns(sepLine) {
    return splitTableCells(sepLine).cells.map(function (c) {
        const t = c.trim();
        const left = t.charAt(0) === ':';
        const right = t.charAt(t.length - 1) === ':';
        if (left && right) return 'center';
        if (right) return 'right';
        if (left) return 'left';
        return '';
    });
}

function renderTableRow(i, line, tag, aligns, extraClass) {
    const parsed = splitTableCells(line);
    let html = '<tr class="line ' + extraClass + '" data-line="' + i + '">';
    if (extraClass === 'line-table-sep') {
        html += '<td colspan="' + Math.max(parsed.cells.length, 1) + '">'
            + '<span class="mk">' + esc(line) + '</span></td></tr>';
        return html;
    }
    parsed.cells.forEach(function (cell, ci) {
        const align = aligns[ci] ? ' class="align-' + aligns[ci] + '"' : '';
        let inner = '';
        if (ci === 0 && parsed.leadingPipe) inner += '<span class="mk">|</span>';
        inner += renderInline(cell);
        if (ci < parsed.cells.length - 1 || parsed.trailingPipe) {
            inner += '<span class="mk">|</span>';
        }
        html += '<' + tag + align + '>' + inner + '</' + tag + '>';
    });
    if (!parsed.cells.length) {
        html += '<' + tag + '><span class="mk">' + esc(line) + '</span></' + tag + '>';
    }
    return html + '</tr>';
}

function renderInline(text) {
    if (!text) return '';
    // Single-pass tokenizer: scan left to right, match markdown patterns.
    // This avoids the bug where italic * regex matches inside already-replaced ** bold spans.
    let result = '';
    let i = 0;
    while (i < text.length) {
        // Inline code (highest priority -- contents not parsed).
        // A run of N backticks opens a span closed by the next run of exactly
        // N backticks, so `` `code` `` can show literal backticks inside code.
        if (text[i] === '`') {
            let run = 1;
            while (text[i + run] === '`') run++;
            const delim = text.slice(i, i + run);
            let search = i + run, end = -1;
            while (end === -1) {
                const idx = text.indexOf(delim, search);
                if (idx === -1) break;
                let closeRun = 0;
                while (text[idx + closeRun] === '`') closeRun++;
                if (closeRun === run) end = idx; else search = idx + closeRun;
            }
            if (end !== -1) {
                let inner = text.slice(i + run, end);
                let pre = delim, post = delim;
                // One space of padding belongs to the delimiters (CommonMark),
                // written into the hidden mk spans so textContent stays exact.
                if (run > 1 && inner.length > 2 && inner[0] === ' ' && inner[inner.length - 1] === ' ') {
                    pre = delim + ' ';
                    post = ' ' + delim;
                    inner = inner.slice(1, -1);
                }
                result += '<span class="mk">' + pre + '</span><span class="md-code">' + esc(inner) + '</span><span class="mk">' + post + '</span>';
                i = end + run;
                continue;
            }
        }
        // Link [text](url)
        if (text[i] === '[') {
            const closeBracket = text.indexOf(']', i + 1);
            if (closeBracket !== -1 && text[closeBracket + 1] === '(') {
                const closeParen = text.indexOf(')', closeBracket + 2);
                if (closeParen !== -1) {
                    const linkText = text.slice(i + 1, closeBracket);
                    const url = text.slice(closeBracket + 2, closeParen);
                    result += '<span class="mk">[</span><span class="md-link">' + esc(linkText) + '</span><span class="mk">](' + esc(url) + ')</span>';
                    i = closeParen + 1;
                    continue;
                }
            }
        }
        // Strikethrough ~~text~~
        if (text[i] === '~' && text[i + 1] === '~') {
            const end = text.indexOf('~~', i + 2);
            if (end !== -1) {
                const inner = text.slice(i + 2, end);
                result += '<span class="mk">~~</span><span class="md-strike">' + esc(inner) + '</span><span class="mk">~~</span>';
                i = end + 2;
                continue;
            }
        }
        // Bold+Italic ***text***
        if (text[i] === '*' && text[i + 1] === '*' && text[i + 2] === '*') {
            const end = text.indexOf('***', i + 3);
            if (end !== -1) {
                const inner = text.slice(i + 3, end);
                result += '<span class="mk">***</span><span class="md-bolditalic">' + esc(inner) + '</span><span class="mk">***</span>';
                i = end + 3;
                continue;
            }
        }
        // Bold **text**
        if (text[i] === '*' && text[i + 1] === '*') {
            const end = text.indexOf('**', i + 2);
            if (end !== -1) {
                const inner = text.slice(i + 2, end);
                result += '<span class="mk">**</span><span class="md-bold">' + esc(inner) + '</span><span class="mk">**</span>';
                i = end + 2;
                continue;
            }
        }
        // Italic *text*
        if (text[i] === '*') {
            const end = text.indexOf('*', i + 1);
            if (end !== -1) {
                const inner = text.slice(i + 1, end);
                result += '<span class="mk">*</span><span class="md-italic">' + esc(inner) + '</span><span class="mk">*</span>';
                i = end + 1;
                continue;
            }
        }
        // Plain character
        result += esc(text[i]);
        i++;
    }
    return result;
}

function renderMarkdown(md) {
    const lines = (md || '').split('\n');
    let inFence = false;
    // GitHub-style callouts: a blockquote whose first line is [!TYPE] colors
    // the whole quote run. The type carries across consecutive quote lines
    // and ends at the first non-quote line, so in any other renderer the
    // callout degrades gracefully to a plain blockquote.
    let callout = null;
    const out = [];
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        // Code fences
        if (inFence) {
            if (/^```/.test(line)) { inFence = false; out.push(mkDiv(i, 'line-code-fence', esc(line))); continue; }
            out.push(mkDiv(i, 'line-code-block', esc(line)));
            continue;
        }
        if (line[0] !== '>') callout = null;
        if (/^```/.test(line)) { inFence = true; out.push(mkDiv(i, 'line-code-fence', esc(line))); continue; }

        // GFM table: pipe header immediately followed by a delimiter row.
        if (looksLikeTableHeader(line) && i + 1 < lines.length && isSeparatorRow(lines[i + 1])) {
            const aligns = parseAligns(lines[i + 1]);
            let table = '<table class="md-table"><thead>';
            table += renderTableRow(i, line, 'th', aligns, 'line-table-head');
            table += '</thead><tbody>';
            table += renderTableRow(i + 1, lines[i + 1], 'td', aligns, 'line-table-sep');
            let r = i + 2;
            while (r < lines.length && isTableBodyRow(lines[r])) {
                table += renderTableRow(r, lines[r], 'td', aligns, 'line-table-row');
                r++;
            }
            table += '</tbody></table>';
            out.push(table);
            i = r - 1;
            continue;
        }

        // HR
        if (/^(\*\*\*|---|___)\s*$/.test(line)) {
            out.push(mkDiv(i, 'line-hr', '<span class="mk">' + esc(line) + '</span>'));
            continue;
        }

        // Headings: # text -- full line rendered, # is faded
        const hm = line.match(/^(#{1,6}\s)(.*)/);
        if (hm) {
            out.push(mkDiv(i, 'line-h' + (hm[1].trim().length),
                '<span class="mk">' + esc(hm[1]) + '</span>' + renderInline(hm[2])));
            continue;
        }

        // Blockquote: > text -- full line rendered, > is faded
        const bq = line.match(/^(>\s?)(.*)/);
        if (bq) {
            // The marker alone on its line (GitHub) or with text after it
            // (Obsidian); both open a callout of that type.
            const head = bq[2].match(/^\[!(note|tip|important|warning|caution)\](\s.*|\s*)$/i);
            if (head) {
                callout = head[1].toLowerCase();
                out.push(mkDiv(i, 'line-quote line-callout callout-' + callout + ' callout-head',
                    '<span class="mk">' + esc(bq[1]) + '[!</span>' +
                    '<span class="callout-label">' + esc(head[1]) + '</span>' +
                    '<span class="mk">]</span>' + renderInline(head[2])));
                continue;
            }
            if (callout) {
                out.push(mkDiv(i, 'line-quote line-callout callout-' + callout,
                    '<span class="mk">' + esc(bq[1]) + '</span>' + renderInline(bq[2])));
                continue;
            }
            out.push(mkDiv(i, 'line-quote',
                '<span class="mk">' + esc(bq[1]) + '</span>' + renderInline(bq[2])));
            continue;
        }

        // Image alone on a line: ![alt](src) -- raw text kept (hidden until
        // active) so cursor offsets stay exact; the img is an extra non-text
        // element, resolved through the flatnote-asset scheme for local files.
        const img = line.match(/^(!\[[^\]]*\]\(([^)\s]+)\))\s*$/);
        if (img) {
            const src = img[2];
            const resolved = /^[a-z][a-z0-9+.-]*:/i.test(src) ? src : 'flatnote-asset:///' + encodeURI(src);
            out.push(mkDiv(i, 'line-image',
                '<span class="mk">' + esc(line) + '</span>' +
                '<img class="md-image" src="' + resolved.replace(/"/g, '&quot;') + '" contenteditable="false" draggable="false">'));
            continue;
        }

        // Task list: - [x] text  (raw marker hidden, visual checkbox shown)
        const task = line.match(/^([-*]\s+\[([ xX])\]\s)(.*)/);
        if (task) {
            const checked = task[2].toLowerCase() === 'x';
            out.push(mkDiv(i, 'line',
                '<span class="mk task-raw">' + esc(task[1]) + '</span>' +
                '<span class="task-cb-vis' + (checked ? ' checked' : '') + '" data-line="' + i + '"></span>' +
                renderInline(task[3])));
            continue;
        }

        // Unordered list: - text  (raw marker hidden, bullet drawn via CSS)
        const ul = line.match(/^([-*+]\s)(.*)/);
        if (ul) {
            out.push(mkDiv(i, 'line',
                '<span class="mk list-mk">' + esc(ul[1]) + '</span>' + renderInline(ul[2])));
            continue;
        }

        // Ordered list: 1. text  (number kept visible)
        const ol = line.match(/^(\d+\.\s)(.*)/);
        if (ol) {
            out.push(mkDiv(i, 'line',
                '<span class="ol-mk">' + esc(ol[1]) + '</span>' + renderInline(ol[2])));
            continue;
        }

        // Plain
        out.push(mkDiv(i, 'line', renderInline(line) || '<br>'));
    }
    return out.join('');
}
