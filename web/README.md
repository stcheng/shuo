# Shuo Website

This folder contains the static launch site for Shuo. It supports English,
Simplified Chinese, Traditional Chinese, and Japanese, with automatic, light,
and dark appearance modes. GitHub Pages runs a small standard-library Python
build step that produces fixed-language routes from the shared HTML sources.

Public routes:

- `index.html`: product overview and direct downloads.
- `privacy.html`: app, cloud-provider, project-index, correction, website, and
  deletion boundaries.
- `release-notes.html`: current direct-build release notes and launch status.
- `appcast.xml`: signed Sparkle update feed.
- `404.html`: not-found fallback.
- `sitemap.xml`: canonical root and fixed-language URLs.

The deploy build also generates these indexable routes:

- `/en/`, `/zh-hans/`, `/zh-hant/`, and `/ja/`.
- `privacy.html` and `release-notes.html` inside every language directory.

Each generated page has one visible language, a self-canonical URL, reciprocal
`hreflang` links, localized Open Graph/Twitter metadata, and structured data.
The root routes remain the `x-default` experience and continue to honor browser
language, a stored preference, or the legacy `?lang=` parameter.

## Preview

Build and preview the same artifact deployed by GitHub Pages:

```sh
rm -rf /tmp/shuo-web-preview
mkdir -p /tmp/shuo-web-preview
rsync -a --exclude 'concepts/' --exclude 'build-localized-site.py' web/ /tmp/shuo-web-preview/
python3 web/build-localized-site.py --source web --output /tmp/shuo-web-preview
python3 -m http.server --directory /tmp/shuo-web-preview 8080
```

Then open `http://127.0.0.1:8080`.

Open `/en/`, `/zh-hans/`, `/zh-hant/`, or `/ja/` to inspect a fixed-language
page. The root page also supports `?lang=en`, `?lang=zh-Hans`, `?lang=zh-Hant`,
or `?lang=ja`. Use `?theme=light`, `?theme=dark`, or `?theme=auto` on a fixed
route, or append the same setting with `&theme=` after a root `?lang=` query.

The homepage architecture section mirrors the app's seven-stage signal path.
Its nodes support pointer hover, touch, normal tab focus, and arrow/Home/End
keyboard navigation; the layout becomes horizontally scrollable on narrow
screens and respects `prefers-reduced-motion`.

## GitHub Pages

Recommended setup for `github.com/stcheng/shuo`:

1. Push this `web/` folder and `.github/workflows/pages.yml` to the public
   repository.
2. Open `Settings -> Pages`.
3. Under `Build and deployment`, set `Source` to `GitHub Actions`.
4. Push to `main`, or run the `Deploy GitHub Pages` workflow manually.

The workflow copies `web/`, generates the fixed-language routes, and publishes
the result as the Pages artifact. The same canonical repository contains the
GPL-licensed application source, tests, public documentation, releases, and
update feed.

## Prepare The Canonical Public Repository

The initial source publication uses a fresh curated Git history; it does not
mirror the private development history. From a clean maintainer checkout, run:

```sh
Scripts/initialize-public-repository.sh ../Shuo-public
make -C ../Shuo-public verify
```

The initializer exports application source, tests, website files, governance
documents, and release tooling, audits the result, initializes `main`, and
leaves the initial tree staged for human review. It configures no remote and
creates no commit automatically.

## Visitor Analytics

The production website uses the approved Umami Cloud tracker for anonymous
pageviews and three explicit events: `download-dmg`, `download-zip`, and
`sponsor-click`. The tracker is restricted to `stcheng.github.io`, excludes
query strings and hashes, and honors browser Do Not Track. Do not add user
identification, custom content, session replay, heatmaps, or another analytics
provider without updating Privacy and release verification first.

Umami counts clicks on the GitHub-hosted assets; GitHub Release asset statistics
remain the source for completed download requests.

## Download Links

The homepage links to stable GitHub Release asset names:

- `Shuo-latest-macOS.zip`
- `Shuo-latest-macOS.dmg`

The direct-download app checks the signed Sparkle feed at `web/appcast.xml`.
Generate or update it only after producing the final signed and notarized ZIP:

```sh
SHUO_RELEASE_TAG=v1.0.0 make appcast
```

`make appcast` resolves the repository-pinned Sparkle tools in a fresh
temporary DerivedData directory before signing the feed. Set
`SHUO_APPCAST_ARCHIVE` when more than one versioned ZIP is present.

Sparkle keeps the private EdDSA key in the release Mac's Keychain. Only the
public key and signed appcast belong in the repository.

The packaging script should keep producing these stable aliases in addition to
versioned artifacts. Upload the latest aliases to each GitHub Release so the
homepage download buttons keep working without editing HTML.

## Release Checklist

1. Confirm the canonical GitHub repository URL is still `https://github.com/stcheng/shuo` and the release tag contains the exact corresponding source.
2. Confirm the only analytics loader is the approved Umami Cloud tag, the three
   event names are unchanged, and Privacy still describes the deployed setup.
3. Build, sign, notarize, staple, and attach ZIP/DMG release artifacts.
4. Generate `appcast.xml` from the exact final ZIP and release tag.
5. Verify download, appcast, Privacy, Release Notes, issue, and support links.
6. Check the homepage in English, Simplified Chinese, Traditional Chinese, and
   Japanese, including each fixed-language Privacy and Release Notes route, in
   light and dark appearance, on desktop and mobile.
7. Confirm the privacy and release-note text matches the final app behavior and
   version/build before announcing the release.
8. Submit `https://stcheng.github.io/shuo/sitemap.xml` in Google Search Console;
   a project Pages `robots.txt` is not served from the origin root.
