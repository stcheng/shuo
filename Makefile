.PHONY: install-dev install-dev-adhoc install-dev-signed build build-community test test-community test-community-config perf verify audit-public-source scan-secrets test-release-scripts package package-zip package-dmg package-all release-rc release-public-assets appcast export-public

build:
	xcodebuild -scheme ShuoDirect -destination 'platform=macOS' \
		-onlyUsePackageVersionsFromResolvedFile \
		-disableAutomaticPackageResolution \
		-skipPackageUpdates build

build-community:
	xcodebuild -scheme ShuoCommunity -configuration Community -destination 'platform=macOS' \
		-onlyUsePackageVersionsFromResolvedFile \
		-disableAutomaticPackageResolution \
		-skipPackageUpdates build

test:
	xcodebuild test -scheme ShuoCommunity -configuration Community -destination 'platform=macOS' \
		-onlyUsePackageVersionsFromResolvedFile \
		-disableAutomaticPackageResolution \
		-skipPackageUpdates

test-community:
	xcodebuild test -scheme ShuoCommunity -configuration Community -destination 'platform=macOS' \
		-onlyUsePackageVersionsFromResolvedFile \
		-disableAutomaticPackageResolution \
		-skipPackageUpdates

test-community-config:
	./Tests/Scripts/community-build-tests.sh

perf:
	mkdir -p build/perf
	SHUO_PERF_OUTPUT="$(CURDIR)/build/perf/shuo-perf-latest.json" \
		xcodebuild test -scheme ShuoCommunity -configuration Community -destination 'platform=macOS' \
		-onlyUsePackageVersionsFromResolvedFile \
		-disableAutomaticPackageResolution \
		-skipPackageUpdates \
		-only-testing:ShuoTests/PerformanceBenchmarkTests/testPerformanceSnapshot
	test -s build/perf/shuo-perf-latest.json
	jq empty build/perf/shuo-perf-latest.json
	cp build/perf/shuo-perf-latest.json build/perf/shuo-perf-$$(date +%Y%m%d-%H%M%S).json

verify: test-release-scripts
	./Scripts/verify.sh

audit-public-source:
	./Scripts/audit-public-source.sh

scan-secrets:
	./Scripts/scan-secrets.sh

test-release-scripts:
	./Tests/Scripts/release-packaging-tests.sh
	./Tests/Scripts/appcast-security-tests.sh

package: package-zip

package-zip:
	./Scripts/package-app.sh zip

package-dmg:
	./Scripts/package-app.sh dmg

package-all:
	./Scripts/package-app.sh all

release-rc:
	@set -eu; \
	if [ "$$(git rev-parse --is-inside-work-tree 2>/dev/null || true)" != "true" ]; then \
		echo "Release candidates must be built from a Git working tree." >&2; \
		exit 2; \
	fi; \
	dirty="$$(git status --porcelain --untracked-files=all)"; \
	if [ -n "$$dirty" ]; then \
		echo "Release candidates require a clean Git working tree." >&2; \
		printf '%s\n' "$$dirty" >&2; \
		exit 2; \
	fi; \
	team_id='4GQ47468NJ'; \
	identity="$${SHUO_CODESIGN_IDENTITY:-}"; \
	if [ -z "$$identity" ]; then \
		identities="$$(security find-identity -v -p codesigning \
			| awk -F '"' -v team="($$team_id)" \
			'$$2 ~ /^Developer ID Application:/ && index($$2, team) { print $$2 }')"; \
		identity_count="$$(printf '%s\n' "$$identities" | awk 'NF { count += 1 } END { print count + 0 }')"; \
		if [ "$$identity_count" -ne 1 ]; then \
			echo "Expected exactly one Developer ID Application identity for team $$team_id; found $$identity_count." >&2; \
			echo "Set SHUO_CODESIGN_IDENTITY explicitly if this Mac has multiple valid identities." >&2; \
			exit 2; \
		fi; \
		identity="$$identities"; \
	fi; \
	SHUO_RELEASE=1 \
	SHUO_SIGN_MODE=identity \
	SHUO_CODESIGN_IDENTITY="$$identity" \
	SHUO_NOTARIZE=1 \
	SHUO_NOTARY_PROFILE="$${SHUO_NOTARY_PROFILE:-Shuo-Notary}" \
	SHUO_WHISPER_ARCHITECTURES='arm64;x86_64' \
	SHUO_SENSEVOICE_ARCHITECTURES='arm64;x86_64' \
	./Scripts/package-app.sh all

# Print the complete public-upload allowlist for one verified RC manifest.
# Private dSYM archives are deliberately absent; never replace this with a glob.
release-public-assets:
	@set -eu; \
	manifest="$${SHUO_RELEASE_MANIFEST:?Set SHUO_RELEASE_MANIFEST to the versioned RC manifest}"; \
	test -f "$$manifest"; \
	directory="$$(cd "$$(dirname "$$manifest")" && pwd)"; \
	version="$$(jq -r '.version // empty' "$$manifest")"; \
	zip="$$(jq -r '.artifacts.zip.filename // empty' "$$manifest")"; \
	dmg="$$(jq -r '.artifacts.dmg.filename // empty' "$$manifest")"; \
	checksum="$$directory/Shuo-$$version-macOS.sha256"; \
	latest_zip="$$directory/Shuo-latest-macOS.zip"; \
	latest_dmg="$$directory/Shuo-latest-macOS.dmg"; \
	printf '%s\n' "$$version" | grep -Eq '^[0-9A-Za-z][0-9A-Za-z.+-]*$$'; \
	test "$$zip" = "Shuo-$$version-macOS.zip"; \
	test "$$dmg" = "Shuo-$$version-macOS.dmg"; \
	test "$$(basename "$$manifest")" = "Shuo-$$version-macOS.manifest.json"; \
	test "$$(jq -r '.schema_version // empty' "$$manifest")" = 1; \
	test "$$(jq -r '.product // empty' "$$manifest")" = Shuo; \
	test "$$(jq -r '.bundle_id // empty' "$$manifest")" = dev.shuotian.Shuo; \
	test "$$(jq -r '.source.repository // empty' "$$manifest")" = https://github.com/stcheng/shuo.git; \
	test "$$(jq -r '.source.tag // empty' "$$manifest")" = "v$$version"; \
	test "$$(jq -r '.dependencies.sparkle.repository // empty' "$$manifest")" = https://github.com/sparkle-project/Sparkle; \
	test "$$(jq -r '.dependencies.sparkle.version // empty' "$$manifest")" = 2.9.4; \
		test "$$(jq -r '.dependencies.sparkle.revision // empty' "$$manifest")" = b6496a74a087257ef5e6da1c5b29a447a60f5bd7; \
		test "$$(jq -r '.dependencies.sensevoice_runtime.segment_delimiter_patch_sha256 // empty' "$$manifest")" = 16b5a7420bfb79fe4d6a4564adf2bae8552735413f46fd80d2e2f234063e955a; \
		test -f "$$directory/$$zip"; \
	test -f "$$directory/$$dmg"; \
	test -f "$$checksum"; \
	test -f "$$latest_zip"; \
	test -f "$$latest_dmg"; \
	test "$$(shasum -a 256 "$$directory/$$zip" | awk '{print $$1}')" = "$$(jq -r '.artifacts.zip.sha256 // empty' "$$manifest")"; \
	test "$$(shasum -a 256 "$$directory/$$dmg" | awk '{print $$1}')" = "$$(jq -r '.artifacts.dmg.sha256 // empty' "$$manifest")"; \
	test "$$(awk 'NF { count += 1 } END { print count + 0 }' "$$checksum")" = 2; \
	awk -v zip="$$zip" -v dmg="$$dmg" \
		'$$1 ~ /^[0-9a-fA-F]{64}$$/ && ($$2 == zip || $$2 == dmg) { seen[$$2] += 1 } END { exit !(seen[zip] == 1 && seen[dmg] == 1) }' \
		"$$checksum"; \
	(cd "$$directory" && shasum -a 256 --check "$$(basename "$$checksum")" >/dev/null); \
	cmp -s "$$directory/$$zip" "$$latest_zip"; \
	cmp -s "$$directory/$$dmg" "$$latest_dmg"; \
	for path in \
		"$$directory/$$zip" \
		"$$directory/$$dmg" \
		"$$checksum" \
		"$$directory/Shuo-$$version-macOS.manifest.json" \
		"$$latest_zip" \
		"$$latest_dmg"; do \
		printf '%s\n' "$$path"; \
	done

appcast:
	@set -eu; \
	derived_data="$$(mktemp -d "$${TMPDIR:-/tmp}/shuo-appcast-derived.XXXXXX")"; \
	trap 'rm -rf "$$derived_data"' EXIT HUP INT TERM; \
	xcodebuild -resolvePackageDependencies \
		-project Shuo.xcodeproj \
		-scheme ShuoDirect \
		-onlyUsePackageVersionsFromResolvedFile \
		-disableAutomaticPackageResolution \
		-skipPackageUpdates \
		-derivedDataPath "$$derived_data" >/dev/null; \
	SHUO_DERIVED_DATA="$$derived_data" \
		./Scripts/generate-appcast.sh "$${SHUO_APPCAST_ARCHIVE:-}"

export-public:
	./Scripts/export-public.sh

install-dev:
	SHUO_SIGN_MODE=local ./Scripts/install-dev.sh

install-dev-adhoc:
	SHUO_SIGN_MODE=adhoc ./Scripts/install-dev.sh

install-dev-signed:
	SHUO_SIGN_MODE=local ./Scripts/install-dev.sh
