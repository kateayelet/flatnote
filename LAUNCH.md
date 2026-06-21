# FlatNote — Launch Checklist

Everything needed to finish shipping FlatNote, written so you can pick it up cold
later. Work top to bottom. Paste-ready copy lives in `appstore/METADATA.md`.

## Where things stand (done already)

- App is complete and tested (42 passing tests). Code is on GitHub:
  `https://github.com/kateayelet/flatnote` (branch `main`).
- Version **1.0**, build **3** in the project. Build 1 was uploaded to
  TestFlight earlier; build 3 is the current one to ship.
- Real app icon is in place.
- `ITSAppUsesNonExemptEncryption = NO` is set, so the export-compliance prompt
  will NOT appear on uploads.
- iCloud capability is enabled in Xcode (iCloud Documents + the
  `iCloud.com.aftrveil.flatnote` container).
- App Store assets are generated and in the repo:
  - Screenshots (plain, exact required sizes) in `appstore/screenshots/`
    - `iphone-6.9/` is 1320x2868 (editor, library, find)
    - `ipad-13/` is 2064x2752 (editor, library)
  - `appstore/METADATA.md` — name, subtitle, description, keywords, promo text,
    categories, App Privacy answers
  - `appstore/PRIVACY.md` — a privacy policy to host
  - README and MIT LICENSE are in the repo root

## What you still need to supply

1. **Support URL** (required). Easiest: make the GitHub repo public (see the
   open-source step) and use `https://github.com/kateayelet/flatnote`.
2. **Privacy Policy URL** (required). Host `appstore/PRIVACY.md` somewhere public
   (GitHub Pages, Notion, or a one-page site) and use that link. Add your contact
   email to the bottom of PRIVACY.md first.
3. **EU trader status** declaration (required before EU distribution). Set in
   App Store Connect under App Information / Business. If you are an individual
   not acting as a trader, declare that, or exclude the EU in availability.

---

## Step 1 — Build and test on your phone (do this first)

1. Open the project: `open ~/05-flatnote-app/FlatNote.xcodeproj`
2. Top of the Xcode window: set the destination to **Any iOS Device (arm64)**.
3. Menu bar: **Product -> Archive**. Wait for the Organizer window.
4. **Distribute App -> TestFlight Internal Only -> Upload.** Accept automatic
   signing and the defaults.
5. After it processes (5-15 min), it appears in App Store Connect -> FlatNote ->
   **TestFlight** tab. If you have not already, click the **+** next to
   **Internal Testing**, make a group, and add your Apple ID email.
6. On your iPhone, install the **TestFlight** app, sign in with the same Apple
   ID, and install FlatNote from there.

**Verify on the real device (these could not be tested in the simulator):**
- [ ] iCloud sync: edit a note, check it appears on a second device signed into
      the same Apple ID (or check it shows in iCloud Drive -> FlatNote).
- [ ] The formatting bar above the keyboard actually inserts markdown
      (bold, italic, heading, list, checkbox, link).
- [ ] Find-in-note (magnifying glass) highlights and jumps between matches.
- [ ] Creating a note: tapping compose opens a blank note; its title comes from
      the first line after you leave; an empty note discards itself.

---

## Step 2 — Submit to the App Store

Do this once you are happy with the TestFlight build.

In **App Store Connect -> FlatNote**, on the **1.0 Prepare for Submission** page:

1. **Screenshots:** drag the three files from `appstore/screenshots/iphone-6.9/`
   into the iPhone slot. Switch to the **iPad** tab and drag the two from
   `appstore/screenshots/ipad-13/`.
2. **Promotional Text** and **Description:** paste from `appstore/METADATA.md`.
3. **Keywords:** paste from `appstore/METADATA.md`.
4. **Build:** click the **+** by "Build" and select **build 3**.

In the **left sidebar**:

5. **App Information:** Category = **Productivity** (secondary Utilities,
   optional). Paste the **Support URL** and **Privacy Policy URL**. Set copyright
   to `2026 Kate Benediktsson`.
6. **App Privacy** (under Trust & Safety): run the questionnaire and answer
   **No, we do not collect data** -> Data Not Collected -> Publish.
7. **Age rating:** complete the short questionnaire (all answers No) -> 4+.
8. **Pricing and Availability:** set price to **Free**. Handle **EU trader
   status** here / under Business.

Then:

9. Click **Add for Review -> Submit for Review.** Export compliance is already
   handled, so it will not ask. Review usually takes one to two days.
10. If it gets rejected, read the reason in the Resolution Center; most first-app
    rejections are about a missing URL or a privacy detail, all of which are
    covered above.

---

## Step 3 — Open source it (optional, recommended)

Open-sourcing reinforces the privacy promise ("read the code"), and it is free
anyway. License is already MIT.

- GitHub repo -> **Settings -> General -> Danger Zone -> Change visibility ->
  Public.**
- That also gives you a free Support URL for the App Store.

---

## Reference: file map

```
~/05-flatnote-app/
  README.md                      project overview
  LICENSE                        MIT
  LAUNCH.md                      this file
  FlatNote.xcodeproj             open this in Xcode
  FlatNote/                      app source
  FlatNoteTests/                 tests
  appstore/
    METADATA.md                  paste-ready App Store text
    PRIVACY.md                   privacy policy to host
    screenshots/iphone-6.9/      1320x2868 (upload to iPhone 6.9")
    screenshots/ipad-13/         2064x2752 (upload to iPad 13")
```

## Notes for next time

- To make a new build, bump **CFBundleVersion** in `FlatNote/Info.plist`
  (currently 3) before each upload; Apple rejects duplicate build numbers.
- Run tests anytime with:
  `xcodebuild test -project FlatNote.xcodeproj -scheme FlatNote -destination 'platform=iOS Simulator,name=iPhone 17'`
- Re-generate screenshots by running the app in the `iPhone 17 Pro Max` and
  `iPad Pro 13-inch (M5)` simulators and using
  `xcrun simctl io <device> screenshot`.
