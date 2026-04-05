# Dietry First Public Release Guide

This document provides a step-by-step checklist for preparing Dietry for its first public release (`v1.0.0`).

## Pre-Release Checklist

### Code & Quality
- [ ] Run `flutter analyze` — fix all warnings and errors
- [ ] Run `flutter test --coverage` — ensure all tests pass
- [ ] Run `flutter format lib/` — apply consistent code formatting
- [ ] Review recent commits for any debug code, console logs, or TODOs
- [ ] Test on all platforms: web (Chrome), Android device/emulator, iOS (if applicable), Linux desktop
- [ ] Test offline mode — queue writes and verify sync on reconnect
- [ ] Test OAuth flow end-to-end (Google login, token refresh)
- [ ] Verify RLS policies work as expected (user can only see their own data)

### Database & Migrations
- [ ] All migrations in `sql/` are numbered sequentially (no gaps)
- [ ] Test migration from `00_init.sql` to latest on a fresh database
- [ ] Verify RLS policies are correctly applied to all tables
- [ ] Confirm no test data is left in production database
- [ ] Document any manual setup steps needed for deployment

### Documentation
- [ ] Update README.md with accurate badges and links
- [ ] Update CLAUDE.md with complete getting-started instructions
- [ ] Add CHANGELOG.md with version history and breaking changes (if any)
- [ ] Verify all code comments are up-to-date and helpful
- [ ] Document API endpoints used by the app in `docs/` (if not already done)

### Configuration & Secrets
- [ ] Production config files are documented but NOT committed (use `.example` templates)
- [ ] All environment-specific values are externalized (`--dart-define-from-file`)
- [ ] No secrets (API keys, JWT test tokens) in version control
- [ ] Verify `.gitignore` prevents sensitive files from being accidentally committed

### Build & Deployment
- [ ] Run `./build.sh ce dev` successfully
- [ ] Verify APK builds: `flutter build apk --release --dart-define-from-file=config/ce-dev.json`
- [ ] Verify web build: `flutter build web --dart-define-from-file=config/ce-dev.json`
- [ ] Verify Linux build: `flutter build linux --release --dart-define-from-file=config/ce-dev.json`
- [ ] Test deployed artifacts on actual device/emulator
- [ ] Verify app icon appears correctly on all platforms

### Marketing & Community
- [ ] Update landing page (dietry-hp) with correct links
- [ ] Add badges to README (Flutter version, Dart version, License)
- [ ] Create CONTRIBUTORS.md if applicable
- [ ] Add code of conduct (CODE_OF_CONDUCT.md)

---

## Setting Version Numbers

### Update `pubspec.yaml`

The version format is `MAJOR.MINOR.PATCH+BUILD`:

```yaml
version: 1.0.0+1
```

**For the first release**, use:

```yaml
version: 1.0.0+1
```

**After first release** (when making changes), use semantic versioning:
- `1.0.1+2` — bug fix (patch)
- `1.1.0+3` — new feature (minor)
- `2.0.0+4` — breaking change (major)

### Update Version Across Platforms

1. **Android** (`android/app/build.gradle`):
   - `versionName "1.0.0"` (must match pubspec.yaml)
   - `versionCode 1` (increments by 1 each release)

2. **iOS** (`ios/Runner.xcodeproj/project.pbxproj` or via Xcode):
   - Bundle version = `1.0.0`
   - Build number = `1`

3. **Web** (automatically derived from pubspec.yaml)

### Create a Release Commit

```bash
# Update version
# Edit pubspec.yaml: version: 1.0.0+1

git add pubspec.yaml android/app/build.gradle
git commit -m "chore: bump version to 1.0.0 for first public release"
git push origin develop
```

---

## Creating a GitHub Release

### Prerequisites
- Repository is public on GitHub (`https://github.com/tcriess/dietry`)
- You have push access
- `gh` CLI is installed (`brew install gh` or from https://github.com/cli/cli)

### Step 1: Create a Release Tag

```bash
# On main branch (after PR merge from develop)
git checkout main
git pull origin main

# Create and push a tag
git tag -a v1.0.0 -m "Release v1.0.0: First public release

Features:
- Full nutrition tracking with macros and calories
- Food database with Open Food Facts integration
- Activity tracking with Health Connect/HealthKit
- Body measurements and progress tracking
- Community Edition: self-hosted, fully open source

See CHANGELOG.md for details."

git push origin v1.0.0
```

### Step 2: Create Release on GitHub

```bash
# Using GitHub CLI (recommended)
gh release create v1.0.0 \
  --title "Dietry v1.0.0 — First Public Release" \
  --notes-file CHANGELOG.md \
  --draft=false

# Or create manually at: https://github.com/tcriess/dietry/releases/new
# - Tag: v1.0.0
# - Title: "Dietry v1.0.0 — First Public Release"
# - Description: Copy from CHANGELOG.md
```

### Step 3: Attach Build Artifacts (Optional)

If you want to provide pre-built APKs or Linux binaries:

```bash
# Build artifacts
flutter build apk --release --dart-define-from-file=config/ce-dev.json
flutter build linux --release --dart-define-from-file=config/ce-dev.json

# Upload to release
gh release upload v1.0.0 \
  build/app/outputs/flutter-app.apk \
  build/linux/x64/release/bundle/dietry
```

---

## Updating Landing Page

### Landing Page Location
File: `/home/spanz/WebstormProjects/dietry-hp/index.html`

### Current Dev Links (to update)

The landing page currently points to development URLs. For first release, update these sections:

#### 1. **Open App Button** (hero section)
Change: `https://cloud-dev.dietry.de` → appropriate URL:
- **Community Edition (self-hosted)**: `https://ce.dietry.de` (or your domain)
- **Cloud Edition**: `https://app.dietry.de`

#### 2. **GitHub Links**
These are correct: `https://github.com/tcriess/dietry`

#### 3. **Download Buttons** (in Downloads section)
- **iOS**: `https://apps.apple.com` (update when App Store listing is ready)
- **Android**: `https://play.google.com/store/apps/details?id=de.dietry` (update when Play Store ready)
- **Web**: Point to appropriate domain
- **Linux**: Keep as-is (GitHub builds)

#### 4. **WIP Banner** (line 632)
Current:
```html
wipBanner: '<strong>🚧 Work in Progress</strong> — Only the web app is currently set up...'
```

For v1.0.0, update to:
```html
wipBanner: '<strong>✅ v1.0.0 Released</strong> — Full Flutter app with Web, Android, iOS, and Linux support'
```

### Quick Search & Replace Guide

```html
<!-- Change these lines in index.html -->

<!-- Line ~351: GitHub ribbon (correct) -->
<!-- Line ~385, 399, 510, 530, 585: Open App URL -->
https://cloud-dev.dietry.de → https://app.dietry.de

<!-- Line ~632: WIP Banner -->
wipBanner: '<strong>🚧 Work in Progress</strong>...' 
→ wipBanner: '<strong>✅ v1.0.0 Released</strong> — Full multi-platform support'

<!-- Line ~632: wipBanner English/Deutsch/Español translations -->
Update all three language versions
```

### Example Minimal Edits

Before:
```html
<a href="https://cloud-dev.dietry.de" class="btn btn-primary">
  <i class="icon-rocket"></i>
  <span data-i18n="heroOpenApp">Open Cloud App</span>
</a>
```

After:
```html
<a href="https://app.dietry.de" class="btn btn-primary">
  <i class="icon-rocket"></i>
  <span data-i18n="heroOpenApp">Open Cloud App</span>
</a>
```

---

## Updating CLAUDE.md

Add a new section at the top to document the release process:

```markdown
## Releasing a New Version

### Pre-Release Checklist
See `RELEASE.md` for comprehensive pre-release steps including:
- Code quality checks (`flutter analyze`, `flutter test`)
- Platform testing (web, Android, iOS, Linux)
- Database migration validation
- Build artifact generation

### Versioning
- Version format: `MAJOR.MINOR.PATCH+BUILD`
- Location: `pubspec.yaml` (primary source of truth)
- Update `android/app/build.gradle` versionName/versionCode when building for Android

### Creating a GitHub Release
1. Merge develop → main via PR
2. Create annotated tag: `git tag -a v1.0.0 -m "Release notes"`
3. Push tag: `git push origin v1.0.0`
4. Create release on GitHub with CHANGELOG.md
5. Optionally attach pre-built APK/Linux binaries

### Updating Landing Page
Landing page: `/home/spanz/WebstormProjects/dietry-hp/index.html`

Update these links for each release:
- App URL buttons: `cloud-dev.dietry.de` → production URL
- WIP banner: Update version and feature status
- App Store buttons: Update when iOS/Android apps are published

Use find-and-replace to update all instances across HTML.
```

---

## Release Timeline Example

### Week 1: Final Testing
- Run through pre-release checklist
- Test on actual devices
- Gather feedback from testers

### Week 2: Prepare Release
- Update version in pubspec.yaml
- Write CHANGELOG.md
- Update landing page links
- Create PR: develop → main

### Week 3: Release
- Merge PR to main
- Create git tag `v1.0.0`
- Create GitHub release with artifacts
- Deploy to production domains
- Announce on social media / communities

---

## Checklist Summary

```
Pre-Release:
  ☐ flutter analyze (no errors)
  ☐ flutter test (all pass)
  ☐ flutter format lib/
  ☐ Test on web, Android, iOS, Linux
  ☐ Review database migrations
  ☐ Update README.md, CLAUDE.md, CHANGELOG.md

Version:
  ☐ Update pubspec.yaml to 1.0.0+1
  ☐ Update android/app/build.gradle
  ☐ Create commit: "chore: bump version to 1.0.0"

GitHub Release:
  ☐ Create annotated tag: v1.0.0
  ☐ Push tag to GitHub
  ☐ Create release with CHANGELOG.md
  ☐ (Optional) Attach APK/Linux binaries

Landing Page:
  ☐ Update dev URLs to production URLs
  ☐ Update WIP banner to release status
  ☐ Update all language versions (en, de, es)
  ☐ Test links work correctly
```

---

## Resources

- [Semantic Versioning](https://semver.org/)
- [Flutter Build Documentation](https://docs.flutter.dev/deployment)
- [GitHub Releases Documentation](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)
- [Android Versioning Guide](https://developer.android.com/studio/publish/versioning)
