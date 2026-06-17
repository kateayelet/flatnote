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
        // Inline code (highest priority -- contents not parsed)
        if (text[i] === '`') {
            const end = text.indexOf('`', i + 1);
            if (end !== -1) {
                const inner = text.slice(i + 1, end);
                result += '<span class="mk">`</span><span class="md-code">' + esc(inner) + '</span><span class="mk">`</span>';
                i = end + 1;
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
    return lines.map((line, i) => {
        // Code fences
        if (inFence) {
            if (/^```/.test(line)) { inFence = false; return mkDiv(i, 'line-code-fence', esc(line)); }
            return mkDiv(i, 'line-code-block', esc(line));
        }
        if (/^```/.test(line)) { inFence = true; return mkDiv(i, 'line-code-fence', esc(line)); }

        // HR
        if (/^(\*\*\*|---|___)\s*$/.test(line)) return mkDiv(i, 'line-hr', '<span class="mk">' + esc(line) + '</span>');

        // Headings: # text -- full line rendered, # is faded
        const hm = line.match(/^(#{1,6}\s)(.*)/);
        if (hm) return mkDiv(i, 'line-h' + (hm[1].trim().length),
            '<span class="mk">' + esc(hm[1]) + '</span>' + renderInline(hm[2]));

        // Blockquote: > text -- full line rendered, > is faded
        const bq = line.match(/^(>\s?)(.*)/);
        if (bq) return mkDiv(i, 'line-quote',
            '<span class="mk">' + esc(bq[1]) + '</span>' + renderInline(bq[2]));

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
