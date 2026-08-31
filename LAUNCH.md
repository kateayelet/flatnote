# FlatNote — 1.1 ship checklist

Pick this up cold. 1.0 has been live on the App Store since 2026-06-30.
This is the 1.1 submission, not a first launch.

Store listing: https://apps.apple.com/us/app/flatnote/id6781590712
Code: https://github.com/kateayelet/flatnote
Support page: https://kateayelet.github.io/flatnote/
Privacy: https://kateayelet.github.io/flatnote/privacy.html
Paste-ready listing copy: `appstore/METADATA.md`

## Where things stand

- Version **1.1**, build **11** in the project. Build 10 was archived locally
  on 2026-08-10 and never released. Builds 8–10 of 1.1 were never submitted.
- 1.1 code is on `main` (last commit 2026-08-19: Mac opens to a blank note,
  near-white paper, smaller outline).
- App icon, screenshots, preview video, and privacy page are in the repo.
- `ITSAppUsesNonExemptEncryption = NO` is set.
- iCloud container: `iCloud.com.aftrveil.flatnote`. Team: aftrveil (SMQ3T59TFL).
- Repo lives at `/Users/kateayelet/10-flatnote-app` (moved out of the LifeOS
  vault so Obsidian sync would stop eating icons and screenshots).

## Hard deadline

- **Age-rating questionnaire due 2026-09-07.** Apple will pull the app if this
  is not answered. Do it in App Store Connect under App Information, whether
  or not 1.1 is submitted yet.

## What 1.1 actually adds (user-facing)

Library cards with rendered markdown and photos. Real folders. Trash instead
of destroy. Open `.md` files in place. Welcome + sample notes. About card.
Paste/attach images. Sketch pad. Share as PDF / Word / Markdown. Find and
replace. GitHub-style callouts. Calmer type. Mac opens to a blank note.

## Step 1 — Tests

```bash
cd /Users/kateayelet/10-flatnote-app
xcodebuild test -project FlatNote.xcodeproj -scheme FlatNote \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expect 54 passing tests. The invariant is `textContent === source`: the editor
never rewrites the markdown you typed.

## Step 2 — Archive and upload (iOS, then Mac)

1. `open /Users/kateayelet/10-flatnote-app/FlatNote.xcodeproj`
2. Destination **Any iOS Device (arm64)** → **Product → Archive**.
3. Organizer: **Distribute App → App Store Connect → Upload.** Automatic signing.
4. Repeat with destination **Any Mac**.
5. Wait for both builds to finish Processing in App Store Connect (5–60 min).

If Apple rejects a duplicate build number, bump `CURRENT_PROJECT_VERSION` in
`FlatNote.xcodeproj/project.pbxproj` (all four occurrences) and archive again.

## Step 3 — TestFlight on a real device

Install the 1.1 build from TestFlight. Confirm:

- [ ] A new note opens ready to type (Mac must not show a Finder open-panel).
- [ ] Paper is near-white, not beige.
- [ ] Library cards update when you edit a note and go back.
- [ ] Attach a photo; sketch; share as PDF.
- [ ] iCloud: edit on one device, see it on another.
- [ ] Delete goes to Trash.

## Step 4 — Listing (cannot change until a new version is submitted)

In App Store Connect → FlatNote → create version **1.1** (iOS and macOS).

Paste from `appstore/METADATA.md`:

- [ ] Subtitle: **Markdown notes. No account.**
- [ ] Promotional text, description, keywords, What's New
- [ ] Support URL: https://kateayelet.github.io/flatnote/
- [ ] Privacy URL: https://kateayelet.github.io/flatnote/privacy.html
- [ ] iPhone 6.9" screenshots, in numbered order from `appstore/screenshots/iphone-6.9/`
- [ ] iPad 13" screenshots from `appstore/screenshots/ipad-13/`
- [ ] Mac screenshots from `appstore/screenshots/mac/`
- [ ] Preview video from `appstore/preview/flatnote-preview-iphone-6.9.mp4`
- [ ] Attach processed build 11
- [ ] Age-rating questionnaire (due 2026-09-07)
- [ ] Release: automatically after review

## Reference: file map

```
/Users/kateayelet/10-flatnote-app/
  README.md
  LAUNCH.md                      this file
  LICENSE
  FlatNote.xcodeproj
  FlatNote/                      app source
  FlatNoteTests/
  docs/                          GitHub Pages (support + privacy)
  appstore/
    METADATA.md                  paste-ready App Store text
    PRIVACY.md
    SUBMISSION_CHECKLIST.md      older 1.0 walkthrough; METADATA is current
    screenshots/iphone-6.9/      1320x2868
    screenshots/ipad-13/         2064x2752
    screenshots/mac/             2880x1800
    preview/                     iPhone 6.9" App Preview
```
