# FlatNote — App Store Submission Checklist

A start-to-finish guide for App Store Connect. Copy from `METADATA.md` for the
text fields. Do the steps in order. The build is already uploaded, so you are
mostly filling in the listing.

Legal entity / team: aftrveil (SMQ3T59TFL). Bundle ID: com.aftrveil.flatnote.

---

## 0. Before you start

- [ ] Pick a **Support URL** and a **Privacy Policy URL** (see METADATA.md).
      Fill in the contact email in `PRIVACY.md`, then host that file publicly
      (GitHub Pages or a simple page) and use its URL.
- [ ] Builds are uploaded: macOS build 5 and iOS build (whatever is current).
      Builds take a few minutes to an hour to finish "Processing."

---

## 1. Add the macOS platform to the app

App Store Connect → **My Apps → FlatNote**.

- [ ] If there is no macOS version, add it. With a matching bundle ID, FlatNote
      becomes one universal app across iPhone, iPad, and Mac.
- [ ] Confirm the macOS build (build 5) appears under the macOS version once it
      finishes processing.

---

## 2. App Information (set once, all platforms)

- [ ] **Subtitle:** Plain markdown notes that sync
- [ ] **Category:** Primary Productivity, Secondary Utilities
- [ ] **Content Rights:** does not use third-party content.
- [ ] **Age Rating:** answer all No → 4+.
- [ ] **EU Trader status:** declare individual/trader as applies, or exclude the
      EU from availability.

---

## 3. Privacy

- [ ] **App Privacy → Data Collection:** "No, we do not collect data."
      FlatNote has no analytics, no SDKs, no server. (Details in METADATA.md.)
- [ ] **Privacy Policy URL:** paste your hosted PRIVACY.md URL.

---

## 4. Per-version listing (fill for both the iOS and the macOS version)

- [ ] **Promotional Text** — from METADATA.md
- [ ] **Description** — from METADATA.md
- [ ] **Keywords** — from METADATA.md
- [ ] **Support URL** — your page
- [ ] **What's New** — from METADATA.md (use the matching platform's text)
- [ ] **Copyright:** 2026 Kate Benediktsson

### Screenshots (drag in from appstore/screenshots/)

- [ ] **iPhone 6.9":** `iphone-6.9/` (1-editor, 2-library, 3-find)
- [ ] **iPad 13":** `ipad-13/` (1-editor, 2-library)
- [ ] **Mac:** `mac/` (1-editor, 2-library, 3-note) — these are 1440x900,
      a valid Mac size.

---

## 5. Build, pricing, release

- [ ] **Build:** attach the processed macOS build 5 (and the iOS build) to the
      version.
- [ ] **Export compliance:** should not prompt (ITSAppUsesNonExemptEncryption is
      set to NO in the build). If asked, answer "No" to using non-exempt
      encryption.
- [ ] **Pricing:** Free (or set a price).
- [ ] **Availability:** all territories, or exclude the EU if you did not declare
      trader status.
- [ ] **Release:** "Automatically release after review" is simplest.

---

## 6. Optional but recommended: TestFlight first (proves iCloud sync)

Before submitting for review, test the real build on your own devices:

- [ ] App Store Connect → **TestFlight → macOS** → wait for build 5 to process.
- [ ] Add yourself as an internal tester and install the TestFlight Mac build.
- [ ] Confirm notes sync between your iPhone and Mac through iCloud.
- [ ] Do the same for the iOS build if you have not already.

---

## 7. Submit

- [ ] Hit **Add for Review / Submit** on each platform's version.
- [ ] First review usually lands in a day or two.

---

## Notes and gotchas

- **Icon:** comes from the build automatically once processing finishes. Nothing
  to upload separately. It is a 1024x1024 with no alpha (App Store compliant).
- **One app, two versions:** iOS and macOS are separate version pages under the
  same app. Each needs its own screenshots and What's New, but they share App
  Information and App Privacy.
- **Re-uploading a build:** every upload needs a unique build number. The current
  macOS build is 5. Bump `CFBundleVersion` in `FlatNote/Info.plist` for the next.
