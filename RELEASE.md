# Releasing Dietry

The repeatable release process for both repos. Dietry ships from **two** repositories that
stay on the **same version number**:

| Repo | Contains | Public? |
|---|---|---|
| `dietry` (this one) | Community Edition, the app itself, `CHANGELOG.md` | yes |
| `dietry-cloud` (`../dietry-cloud`) | Cloud-only features, importers, cloud schema | no |

Both must be released. A CE-only release quietly ships **nothing** to the Play Store.

---

## What a release actually triggers

Publishing a GitHub release fires `Build & Release` (`.github/workflows/build.yml`) in that
repo with `event_name == release`, which means **production** keystore, **production** config
and the real app name (a push to `develop` builds the same thing with dev secrets and the
"Dietry Dev" label). On a release it:

- builds web, Linux, Android APK **and** the Play Store App Bundle (`.aab`),
- **deploys the web app to the production host** (`ce.dietry.de` / `app.dietry.de`),
- attaches every artifact to the GitHub release.

Two things are **not** automatic:

- **The Play Store upload.** Nothing pushes to Google Play. Download the `.aab` from the
  *cloud* release and upload it in the Play Console by hand.
- **Database migrations.** Apply them *before* the release builds, or the new app meets an old
  schema. See below.

Expect **three** workflow runs per repo after a release (push-to-`main`, push-to-`develop`,
and the release itself). Only the release run deploys production and attaches artifacts; the
other two are CI checks.

---

## Version numbers

`pubspec.yaml` is the **single source of truth** — `MAJOR.MINOR.PATCH+BUILD`.

**Do not edit `android/app/build.gradle`.** Its `versionCode`/`versionName` are read from
`local.properties`, which Flutter fills in from `pubspec.yaml`. Likewise **never pass
`--build-number`** to a build script: that once desynced the Play Store versionCode, and Play
refuses a build number it has already seen (the store's high-water mark is 203 — every future
build must exceed it, which `+256` and up comfortably does).

- The build number **only ever increases** and is never reused, even for a re-cut release.
- CE and cloud carry the **same** version.
- **minor** for anything users gain, **patch** for fixes only. How recently the last release
  went out is irrelevant — semver keys off *what changed*, not the calendar. Version numbers
  are free; a misleading one is not.

---

## Before you start

- [ ] `flutter analyze` — no errors
- [ ] `flutter test` — all pass
- [ ] Everything new has been **manually verified** in the running app
- [ ] **Database migrations are applied to production** — `./flyway.sh info` shows nothing
      pending. Deploy order for a cloud database is always **CE first, then cloud**
      (`docs/database/MIGRATIONS.md`)
- [ ] `git status` is clean apart from intentional changes

### The `pubspec.lock` trap

If `pubspec_overrides.yaml` exists in this repo (the local link to `../dietry-cloud`), then
**any** `flutter` command — including the `flutter analyze` a commit hook may run — rewrites
`pubspec.lock` to resolve `dietry_cloud` to `../dietry-cloud`, dragging in cloud-only
dependencies.

**That lock must never be committed to CE.** The committed lock resolves `dietry_cloud` to
`packages/dietry_cloud` (the public stub). Check before every release commit:

```bash
grep -A4 "^  dietry_cloud:" pubspec.lock | grep path:   # must be packages/dietry_cloud
git checkout -- pubspec.lock                            # if it says ../dietry-cloud
```

It re-dirties itself after each commit while the override is in place, and a dirty lock also
blocks `git checkout main` mid-release.

---

## The release

`X.Y.Z` is the new version, `N` the next build number.

### 1. Changelog (CE only — cloud has no `CHANGELOG.md`)

Add a section above the previous release, written for **users**, not from the commit log:

```markdown
## [X.Y.Z] — YYYY-MM-DD

### Added
- **Short bold claim** — what it does for you, in plain language.

### Changed
### Fixed
### Security
- Disclose real exposures plainly, and say what self-hosters must do about them.
```

### 2. Bump the version in **both** repos

```bash
sed -i 's/^version: .*/version: X.Y.Z+N/' pubspec.yaml
sed -i 's/^version: .*/version: X.Y.Z+N/' ../dietry-cloud/pubspec.yaml
```

### 3. Release commit on `develop`, in both repos

```bash
git add pubspec.yaml CHANGELOG.md && git commit -m "chore: release vX.Y.Z"
git -C ../dietry-cloud add pubspec.yaml
git -C ../dietry-cloud commit -m "chore: release vX.Y.Z"
```

Re-check `pubspec.lock` here — a commit hook may have just rewritten it.

### 4. Fast-forward `main`, then tag it

`main` only ever fast-forwards from `develop` — no merge commits.

```bash
git checkout main && git pull --ff-only origin main
git merge --ff-only develop
git tag -a vX.Y.Z -m "Release vX.Y.Z

<summary — features, then any security fixes and what self-hosters must run>

See CHANGELOG.md for details."
```

Tag from `main`, **after** the fast-forward. An annotated tag's SHA is the tag object, not the
commit — verify with the peeled ref:

```bash
git rev-parse vX.Y.Z^{commit}   # must equal `git rev-parse main`
```

### 5. Push and publish — **CE first, then cloud**

```bash
git push origin main && git push origin vX.Y.Z && git push origin develop
gh release create vX.Y.Z --title "Dietry vX.Y.Z — <headline>" --notes-file <notes>
```

Then repeat steps 4–5 in `../dietry-cloud`; `gh release create` there is what triggers the
Play Store AAB build.

### 6. Ship the Android build

Wait for `Build & Release (Cloud Edition)` on the **release** run to go green, then:

```bash
gh release download vX.Y.Z --repo tcriess/dietry-cloud --pattern '*.aab'
```

Upload the `.aab` in the Play Console. Nothing does this for you.

### 7. Afterwards

- Both repos back on `develop`.
- Check `ce.dietry.de` and `app.dietry.de` are serving the new build.
- Update the landing page (`/home/spanz/WebstormProjects/dietry-hp/index.html`) if the release
  changes what it advertises — version banner and download links, in **all three** languages
  (en, de, es).

---

## Checklist

```
Pre-flight:
  ☐ flutter analyze / flutter test clean
  ☐ new features manually verified
  ☐ prod migrations applied (CE first, then cloud)
  ☐ pubspec.lock points at packages/dietry_cloud

Release:
  ☐ CHANGELOG.md — new section (CE)
  ☐ pubspec.yaml bumped in BOTH repos, build number increased
  ☐ "chore: release vX.Y.Z" on develop in both
  ☐ main fast-forwarded, annotated tag on main, peeled SHA verified
  ☐ push main + tag + develop, both repos
  ☐ gh release create — CE first, then cloud

After:
  ☐ release workflow green in both repos
  ☐ .aab downloaded from the cloud release, uploaded to the Play Console
  ☐ ce.dietry.de / app.dietry.de serving the new build
  ☐ landing page updated if needed
```

---

## Resources

- [Semantic Versioning](https://semver.org/)
- [Keep a Changelog](https://keepachangelog.com/)
- Migrations runbook: `docs/database/MIGRATIONS.md`
