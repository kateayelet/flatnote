# FlatNote — App Store Submission Package

Everything here is ready to paste into App Store Connect. Fields map to the
"App Information" and the version "Distribution" pages.

## App Information (set once)

- **Name:** FlatNote
- **Subtitle (max 30):** Plain markdown notes that sync
- **Primary category:** Productivity
- **Secondary category:** Utilities
- **Age rating:** 4+ (no objectionable content)
- **Copyright:** 2026 Kate Benediktsson
- **Bundle ID:** com.aftrveil.flatnote

## URLs (you must provide these)

- **Support URL (required):** a page where users can reach you. Simplest option:
  make the GitHub repo public and use `https://github.com/kateayelet/flatnote`,
  or a one-page site with an email. Apple just needs a reachable page.
- **Privacy Policy URL (required):** host the text in `PRIVACY.md` somewhere
  public (GitHub Pages, a Notion page, or a plain HTML page) and paste that URL.
- **Marketing URL (optional):** leave blank or point to a landing page.

## Promotional Text (max 170, editable without review)

A fast, focused markdown editor that formats as you type and keeps every note as
a plain .md file in your iCloud. No accounts, no lock-in, no clutter.

## Description (max 4000)

FlatNote is a markdown notes app for people who want their writing to stay
plain, portable, and theirs.

Type markdown and watch it format as you go. Headings, bold, italic,
strikethrough, links, quotes, bullet lists, and tappable checkboxes all render
while you write. The raw symbols stay out of your way and reappear only on the
line you are editing, so you always know exactly what you typed.

WHAT YOU GET

- Live formatting. See the result as you type, with a reference built into the
  welcome note.
- Real checkboxes. Tap to check things off, right in the note.
- Find in a note. Search the open note and jump between highlighted matches.
- A formatting bar above the keyboard for bold, italic, headings, lists,
  checkboxes, and links.
- Find your notes fast. Search the whole library by title or content.

YOUR WORDS BELONG TO YOU

- Every note is a plain .md file. No proprietary format, no lock-in, readable in
  any app, on any device, years from now.
- Your notes live in your iCloud and sync across your iPhone and iPad
  automatically, signed in with your Apple ID. No separate account to make.
- Export or share any note as markdown, or grab them all from the Files app.

QUIET BY DESIGN

- No ads. No tracking. No analytics. Nothing about you leaves your devices and
  your iCloud.
- Works on iPhone and iPad, in light and dark, portrait and landscape.

FlatNote keeps the format simple so you can keep your thinking clear.

## Keywords (max 100 chars, comma-separated)

markdown,notes,editor,plain text,md,writing,icloud,sync,checklist,note taking,journal,markdown editor

## What's New (for this version, 1.0)

First release. Live markdown editing, iCloud sync, find in note, a formatting
bar, and export to plain .md files.

## App Privacy (the questionnaire in App Store Connect)

Answer: **Data Not Collected.**

FlatNote does not collect any data. Notes are stored on the device and in the
user's own iCloud. There is no analytics, no tracking, no third-party SDKs, and
no server that the app talks to. When asked "Do you or your third-party partners
collect data from this app?", answer **No**.

Encryption: already handled. ITSAppUsesNonExemptEncryption is set to NO in the
build, so the export-compliance prompt will not appear.

EU trader status: App Store Connect now requires you to declare trader status
(under the EU Digital Services Act) before the app can be distributed in the EU.
Set this under App Information; if you are an individual not acting as a trader,
declare accordingly, or you can limit availability to exclude the EU.

## Screenshots

Already generated at the exact required sizes, in `appstore/screenshots/`:

- `iphone-6.9/` — 1320 x 2868 (required iPhone size): editor, library, find
- `ipad-13/` — 2064 x 2752 (required iPad size): editor, library

Upload the iPhone set under the 6.9" display and the iPad set under the 13"
display in the Previews and Screenshots section. The first three are the ones
shown on the product page, so the order (editor, library, find) is intentional.
