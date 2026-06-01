# Codogotchi v1 distribution runbook

Date: 2026-06-01  
Status: **Work-in-progress checklist** — packaging track after Phase 08 (product gate is done)  
Related: [phase-08-lite-install.md](../../docs/runbooks/phase-08-lite-install.md), [phase-08 ticket P8.01](../../docs/product/delivery/phase-08/ticket-01-compile-bundle-binaries.md). Monetization and distribution stance: local `notes/private/codogotchi-distribution-and-monetization-stance.md` (not in repo).

---

## What this is for

Phase 08 shipped the **product** (self-contained `.app`, Settings control plane, Lite + SoA). This runbook is the **distribution** track: Apple Developer Program → Developer ID signing → notarization → DMG → GitHub Release → (optional) Sparkle.

**Prerequisite:** [Apple Developer Program](https://developer.apple.com/programs/) — **~$99 USD/year**. Required for notarized DMG distribution; not required for local source builds (see phase-08 install runbook).

**Recommended order:** notarized DMG on GitHub first; Sparkle second. Sparkle is not required for a credible v1.0.0 download.

---

## Time budget (focused work, after Apple activates the account)

| Milestone | Outcome | Estimate |
| --- | --- | --- |
| **Track A** — Account + certs | Can sign Release builds in Xcode | 2–4 hours |
| **Track B** — First notarized `.app` | Gatekeeper-clean on another Mac | 1–2 days |
| **Track C** — DMG + GitHub Release `v1.0.0` | Public download artifact | 2–4 hours (after B) |
| **Track D** — Sparkle | In-app update checks | 1–1.5 days |
| **Track E** — CI (optional) | Tag → build → notarize → attach DMG | 1–2 days |

**Totals:** ~**2–4 days** for DMG-only; ~**4–7 days** with Sparkle; ~**7–10 days** with polished GitHub Actions.

**Wall clock:** enrollment can take **hours to 48 hours** before certificates work — start enrollment on day 0 even if you cannot sign yet.

---

## Repo state today (do not rediscover)

| Item | Location / note |
| --- | --- |
| Bundle ID | `com.codogotchi.app` — `apps/menubar/project.yml` |
| App version in plist | `CFBundleShortVersionString` **0.1.0**, `CFBundleVersion` **1** — align with release tag |
| CLI version | `packages/cli/src/version.ts` → **0.0.0** today — bump with release |
| Signing today | Ad hoc (`CODE_SIGN_IDENTITY: "-"`, empty `DEVELOPMENT_TEAM`) |
| Embedded CLIs | `scripts/build-binaries.sh` → `Contents/Resources/codogotchi` + `codogotchi-hook` (~128 MB) |
| Embed order | Binaries embedded **before** app CodeSign — correct; keep it |
| **Notarization blocker** | Nested binaries ad hoc-sign as identifier **`a.out`** — notarization will reject until release script signs them with real IDs (see Track B) |
| Release archive | `docs/runbooks/phase-08-lite-install.md` Step 2 + `apps/menubar/ExportOptions.plist` |
| Sparkle | **Not integrated** — greenfield in Track D |

---

## Track A — Enroll and certificates

### A1. Apple Developer Program

- [ ] Enroll at https://developer.apple.com/programs/
- [ ] Wait for **Active** membership (check email + https://developer.apple.com/account)
- [ ] Accept any pending agreements in App Store Connect / Developer portal

### A2. Certificates (Keychain Access + developer portal)

Create in [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/certificates/list):

- [ ] **Developer ID Application** — signs `.app` for distribution **outside** Mac App Store
- [ ] **Developer ID Installer** — only if you ship a `.pkg` (skip if DMG-only)

Download and install into login keychain. Confirm they appear under “My Certificates” with a private key.

### A3. App ID (if prompted)

- [ ] Register **App ID** `com.codogotchi.app` (explicit or automatic via Xcode)

### A4. Xcode / project signing

- [ ] Note your **Team ID** (10-character) from Membership details
- [ ] Update `apps/menubar/project.yml`:
  - `DEVELOPMENT_TEAM: "<TeamID>"`
  - Release config: `CODE_SIGN_IDENTITY: "Developer ID Application"`
  - Enable **Hardened Runtime** for Release
- [ ] Regenerate Xcode project if you use xcodegen: `cd apps/menubar && xcodegen`
- [ ] Update `apps/menubar/ExportOptions.plist` for export (team ID, provisioning profile if manual)
- [ ] Open `Codogotchi.xcodeproj` → Signing & Capabilities: confirm **Release** signs with Developer ID

**Entitlements stance:** Codogotchi is a menubar agent that writes `~/.codogotchi`, edits agent hook JSON, and spawns bundled CLIs — same class as CodexBar-style tools. Expect **no App Sandbox** for v1. If notarization fails, Apple’s log will name missing hardened-runtime entitlements; add minimally (do not enable sandbox “just because”).

---

## Track B — First notarized build

Goal: `Codogotchi.app` opens on a **second Mac** (or clean user) without right-click → Open.

### B1. Version bump (before first public artifact)

- [ ] `apps/menubar/project.yml` — `CFBundleShortVersionString` / `CFBundleVersion`
- [ ] `packages/cli/src/version.ts` + `packages/cli/package.json` — match semver
- [ ] Git tag plan: e.g. `v1.0.0`

### B2. Sign embedded binaries (Codogotchi-specific — do not skip)

After `build-binaries.sh` produces the two Mach-O files, **before** the final app signature:

- [ ] Sign each with Developer ID Application and a **stable identifier**, e.g.:
  - `com.codogotchi.cli`
  - `com.codogotchi.hook`
- [ ] Do **not** leave `a.out` as the code-signing identifier (P8.01 contract note)

Example pattern (adjust paths and cert name):

```bash
# After archive/export, or in a release script between embed and app codesign:
IDENTITY="Developer ID Application: Your Name (TEAMID)"
codesign --force --options runtime --sign "$IDENTITY" \
  --identifier com.codogotchi.cli \
  Codogotchi.app/Contents/Resources/codogotchi
codesign --force --options runtime --sign "$IDENTITY" \
  --identifier com.codogotchi.hook \
  Codogotchi.app/Contents/Resources/codogotchi-hook
```

Then deep-sign the app bundle.

- [ ] Verify: `codesign --verify --deep --strict Codogotchi.app`
- [ ] Verify: `spctl -a -vv Codogotchi.app` (may still fail until notarized)

Consider adding `scripts/release.sh` in-repo once this works once manually.

### B3. Archive and export

```bash
cd /path/to/codogotchi

xcodebuild \
  -project apps/menubar/Codogotchi.xcodeproj \
  -scheme Codogotchi \
  -configuration Release \
  -archivePath /tmp/Codogotchi.xcarchive \
  archive

xcodebuild \
  -exportArchive \
  -archivePath /tmp/Codogotchi.xcarchive \
  -exportPath /tmp/CodogotchiExport \
  -exportOptionsPlist apps/menubar/ExportOptions.plist
```

- [ ] Archive succeeds with Developer ID
- [ ] Export produces `/tmp/CodogotchiExport/Codogotchi.app`

### B4. Notarize and staple

Prefer **app-specific password** or **App Store Connect API key** with `notarytool` (store secrets in 1Password, not in git).

```bash
# Zip for upload (Apple wants a zip of the .app)
ditto -c -k --keepParent /tmp/CodogotchiExport/Codogotchi.app /tmp/Codogotchi.zip

xcrun notarytool submit /tmp/Codogotchi.zip \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "@keychain:AC_PASSWORD" \
  --wait

xcrun stapler staple /tmp/CodogotchiExport/Codogotchi.app
xcrun stapler validate /tmp/CodogotchiExport/Codogotchi.app
```

- [ ] `notarytool` status: **Accepted**
- [ ] Staple succeeds
- [ ] Test on second machine: download/copy app, double-click, launches clean

**If rejected:** `xcrun notarytool log <submission-id> --apple-id ...` — fix entitlements or nested signing, resubmit.

### B5. Smoke test (distribution-shaped)

- [ ] Fresh Mac or VM: only DMG/app, no Xcode, no `codogotchi` on PATH
- [ ] Welcome sheet → Approve & install hooks
- [ ] Settings → General shows hooks installed
- [ ] Real agent session animates pet (Lite sheet)
- [ ] Optional: SoA delivery run → gate animation (SoA sheet)
- [ ] Settings → General **Update hooks** after installing a newer build (lockstep path)

---

## Track C — DMG + GitHub Release

### C1. Build DMG

Options: `create-dmg` (brew), or `hdiutil` + drag-drop layout. Notarization of the **DMG itself** is optional if the **app inside** is stapled; many teams notarize the app only for v1.

- [ ] DMG filename includes version: `Codogotchi-1.0.0-arm64.dmg`
- [ ] DMG opens to “drag Codogotchi to Applications” layout

### C2. GitHub Release

- [ ] Commit version bumps on `main`
- [ ] `git tag v1.0.0 && git push origin v1.0.0`
- [ ] `gh release create v1.0.0 Codogotchi-1.0.0-arm64.dmg --title "Codogotchi 1.0.0" --notes-file ...`
- [ ] README: replace “no notarized DMG” with download link + one-line install
- [ ] Optional: add `docs/runbooks/release-dmg.md` mirroring this track once scripted

### C3. Launch ops (lightweight, not blocking dogfood)

- [ ] Release notes (what’s in Lite v1, arm64-only, hook tools supported)
- [ ] Support URL + privacy policy links (even placeholder GitHub pages) if linking from About tab later

---

## Track D — Sparkle (defer until Track C ships)

Sparkle 2 + EdDSA + appcast. Phase 08 estimated **~1–1.5 days**.

### D1. Integrate Sparkle

- [ ] Add Sparkle 2 via SPM to `Codogotchi` target
- [ ] `SUFeedURL` → hosted appcast URL
- [ ] Embed EdDSA **public** key in Info.plist
- [ ] Store **private** key outside repo (1Password / CI secret)

### D2. Appcast hosting

- [ ] Host `appcast.xml` (GitHub Pages, release branch, or static path on `main`)
- [ ] Each release: build → notarize → ZIP/DMG → update appcast entry (version, url, length, signature)

### D3. UX

- [ ] “Check for Updates…” in menubar or About
- [ ] Test update: install 1.0.0 → publish 1.0.1 → app updates and relaunches

**Release workflow after Sparkle:** notarize → staple → publish DMG/ZIP → bump appcast → GitHub Release assets.

---

## Track E — CI automation (optional)

Do **one successful manual notarization** before automating.

- [ ] GitHub Actions `macos-latest` workflow on tag push
- [ ] Import Developer ID cert + key via secrets
- [ ] App Store Connect API key for `notarytool` (preferred over Apple ID password)
- [ ] Run `build-binaries.sh` → sign nested → archive → export → notarize → staple → DMG → `gh release upload`

---

## Explicit non-goals for v1 distribution

- Mac App Store submission (sandbox incompatible with hook installer — see distribution stance)
- Intel / universal binary (arm64-only for v1; document in release notes)
- Sparkle on day one (optional; manual DMG upgrade is fine for early adopters)
- Homebrew cask (nice follow-up, not required)

---

## Troubleshooting quick reference

| Symptom | Likely cause |
| --- | --- |
| Notarization rejects bundle | Nested `codogotchi` / `codogotchi-hook` still `a.out` or unsigned |
| App runs locally, blocked elsewhere | Not stapled, or user has quarantined unsigned copy |
| `exportArchive` fails | `ExportOptions.plist` team/profile mismatch |
| Hooks work in dev, fail in Release | Different bundled binary path; re-test install from exported app |
| Lockstep banner always on | `installedHookVersion` vs bundled version mismatch — bump versions coherently |

---

## Tomorrow starter (minimal day-1 plan)

1. **Enroll** Apple Developer Program (start clock).
2. While waiting: read P8.01 signing note in [ticket-01-compile-bundle-binaries.md](../../docs/product/delivery/phase-08/ticket-01-compile-bundle-binaries.md).
3. When active: Track A (certs + team in `project.yml`).
4. First goal: **one stapled `Codogotchi.app`** on a USB/share to a second Mac — **not** DMG polish yet.
5. Only after that: DMG + `v1.0.0` GitHub Release (Track C).
6. Sparkle when manual releases feel boring (Track D).

---

## Follow-up repo artifacts (when ready)

- [ ] `scripts/release.sh` — sign nested CLIs, archive, export, notarize, staple, DMG
- [ ] `docs/runbooks/release-dmg.md` — operator steps distilled from this note
- [ ] CI workflow `.github/workflows/release.yml`

---

_Created from distribution readiness review, 2026-06-01._
