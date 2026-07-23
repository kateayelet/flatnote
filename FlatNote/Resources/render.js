// Pure markdown -> HTML line renderer for FlatNote's live editor.
//
// No DOM dependencies, so it can be unit-tested in JavaScriptCore.
// Exposed as the global renderMarkdown(md) -> String.
//
// Key rule: every line div's textContent must === the markdown source line.
// Styling is done via spans that wrap parts of the text, but ALL text is
// present, which is what keeps the editor's cursor offsets exact.

function esc(s) {
    return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function mkDiv(i, cls, content) {
    return '<div class="line ' + cls + '" data-line="' + i + '">' + content + '</div>';
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
    return lines.map((line, i) => {
        // Code fences
        if (inFence) {
            if (/^```/.test(line)) { inFence = false; return mkDiv(i, 'line-code-fence', esc(line)); }
            return mkDiv(i, 'line-code-block', esc(line));
        }
        if (line[0] !== '>') callout = null;
        if (/^```/.test(line)) { inFence = true; return mkDiv(i, 'line-code-fence', esc(line)); }

        // HR
        if (/^(\*\*\*|---|___)\s*$/.test(line)) return mkDiv(i, 'line-hr', '<span class="mk">' + esc(line) + '</span>');

        // Headings: # text -- full line rendered, # is faded
        const hm = line.match(/^(#{1,6}\s)(.*)/);
        if (hm) return mkDiv(i, 'line-h' + (hm[1].trim().length),
            '<span class="mk">' + esc(hm[1]) + '</span>' + renderInline(hm[2]));

        // Blockquote: > text -- full line rendered, > is faded
        const bq = line.match(/^(>\s?)(.*)/);
        if (bq) {
            // The marker alone on its line (GitHub) or with text after it
            // (Obsidian); both open a callout of that type.
            const head = bq[2].match(/^\[!(note|tip|important|warning|caution)\](\s.*|\s*)$/i);
            if (head) {
                callout = head[1].toLowerCase();
                return mkDiv(i, 'line-quote line-callout callout-' + callout + ' callout-head',
                    '<span class="mk">' + esc(bq[1]) + '[!</span>' +
                    '<span class="callout-label">' + esc(head[1]) + '</span>' +
                    '<span class="mk">]</span>' + renderInline(head[2]));
            }
            if (callout) return mkDiv(i, 'line-quote line-callout callout-' + callout,
                '<span class="mk">' + esc(bq[1]) + '</span>' + renderInline(bq[2]));
            return mkDiv(i, 'line-quote',
                '<span class="mk">' + esc(bq[1]) + '</span>' + renderInline(bq[2]));
        }

        // Image alone on a line: ![alt](src) -- raw text kept (hidden until
        // active) so cursor offsets stay exact; the img is an extra non-text
        // element, resolved through the flatnote-asset scheme for local files.
        const img = line.match(/^(!\[[^\]]*\]\(([^)\s]+)\))\s*$/);
        if (img) {
            const src = img[2];
            const resolved = /^[a-z][a-z0-9+.-]*:/i.test(src) ? src : 'flatnote-asset:///' + encodeURI(src);
            return mkDiv(i, 'line-image',
                '<span class="mk">' + esc(line) + '</span>' +
                '<img class="md-image" src="' + resolved.replace(/"/g, '&quot;') + '" contenteditable="false" draggable="false">');
        }

        // Task list: - [x] text  (raw marker hidden, visual checkbox shown)
        const task = line.match(/^([-*]\s+\[([ xX])\]\s)(.*)/);
        if (task) {
            const checked = task[2].toLowerCase() === 'x';
            return mkDiv(i, 'line',
                '<span class="mk task-raw">' + esc(task[1]) + '</span>' +
                '<span class="task-cb-vis' + (checked ? ' checked' : '') + '" data-line="' + i + '"></span>' +
                renderInline(task[3]));
        }

        // Unordered list: - text  (raw marker hidden, bullet drawn via CSS)
        const ul = line.match(/^([-*+]\s)(.*)/);
        if (ul) return mkDiv(i, 'line',
            '<span class="mk list-mk">' + esc(ul[1]) + '</span>' + renderInline(ul[2]));

        // Ordered list: 1. text  (number kept visible)
        const ol = line.match(/^(\d+\.\s)(.*)/);
        if (ol) return mkDiv(i, 'line',
            '<span class="ol-mk">' + esc(ol[1]) + '</span>' + renderInline(ol[2]));

        // Plain
        return mkDiv(i, 'line', renderInline(line) || '<br>');
    }).join('');
}
