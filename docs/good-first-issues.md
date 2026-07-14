# Prepared Good First Issues

These maintainer-curated drafts are ready to become GitHub issues after the
initial public source push. Apply the `good first issue` and `help wanted`
labels only after a maintainer confirms that the scope and pointers still match
`main`. Remove each draft from this file when its public issue is created.

## Add a safe argument check to the Community icon generator

**Outcome:** `Tools/generate_community_app_icon.swift` prints a concise usage
message and exits cleanly when no output directory is supplied.

**Pointers:** follow the argument handling in the existing asset generators;
do not change the generated icon artwork or official icon.

**Acceptance:** the valid invocation still reproduces every declared Community
icon size, and a missing argument no longer causes an index-out-of-range crash.

## Add a public Markdown-link checker

**Outcome:** one small script checks relative Markdown links in the public
documentation set and runs from `make verify` in both the working and exported
trees.

**Pointers:** check only repository-relative links; skip HTTP, `mailto:`, and
same-page anchors. Do not add a package dependency for this task.

**Acceptance:** a fixture with one valid and one missing target proves both the
pass and failure paths, and the current public docs pass.

## Record reproducible CLDR emoji-data provenance

**Outcome:** the repository records the exact Unicode CLDR revision and a
deterministic command or script that produces `EmojiAnnotations.json` from the
three documented locales.

**Pointers:** preserve current runtime schema and matching behavior; do not
download data during an app build or include unrelated CLDR files.

**Acceptance:** regeneration from the pinned revision is byte-identical, the
license remains bundled, and `Scripts/audit-public-source.sh` verifies the
recorded provenance.

## Audit Community-facing product-name labels

**Outcome:** Community windows and About surfaces consistently say **Shuo
Community** where the application identity is being shown, while ordinary
sentences may still refer to the upstream Shuo project.

**Pointers:** use `AppBuildIdentity.displayName`; do not rename settings,
storage formats, official Shuo, or user data.

**Acceptance:** focused tests cover official and Community identities in at
least English and Simplified Chinese, and both schemes still compile.
