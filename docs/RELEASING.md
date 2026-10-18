# Versioning and release records

Each update receives an explicit major/minor/patch judgment with a reason. Major
means incompatibility requiring migration; minor means a compatible capability;
patch means a compatible correction or maintenance. Increment BUILD_NUMBER too.
The current VERSION is read by the App build; the UI reads the built bundle.

Maintain CHANGELOG.md and docs/releases/history.json. Regenerate the cumulative
Excel from that JSON, retain old rows, and attach its exact committed bytes to each
release. Local-only versions must not be given fictional Git anchors.

The workbook contains version, build, date, classification/reason, Git anchor,
behavior changes, checks and limitations. Its final commit anchor is the annotated
release tag: a tracked workbook cannot contain its own containing commit SHA.

## Regenerate the Excel

The builder uses @oai/artifact-tool as an authoring dependency; the App does not.
In Codex, use load_workspace_dependencies, its bundled Node executable and packages.
Set ARTIFACT_TOOL_NODE_MODULES to that returned node_modules directory. Outside Codex,
an available @oai/artifact-tool installation may be used without that variable.

```sh
node scripts/release-workbook.mjs
python3 scripts/check-release.py
python3 scripts/test.py
./scripts/build.sh
```

Inspect the workbook and its two rendered previews under .test-output/release-record/.
The consistency check reads Excel cells directly and compares every source row.
For a Codex artifact creation, run the spreadsheet skill's artifact-operation marker
before the first authoring run. Do not install or upgrade unrelated runtime software.

## Publish

Commit VERSION, BUILD_NUMBER, changelog, JSON, Excel and source together. Create
annotated tag v<VERSION> at that commit, push the branch and tag, then publish a
GitHub Release targeting that tag. Attach App ZIP, DMG, committed Excel and SHA256SUMS.
Binaries belong to Release assets, not the source tree. Verify strict App signature,
DMG integrity and version, the tag SHA, and downloaded asset hashes before reporting
completion. Never move a published tag to fix a release; publish a new version.

```sh
python3 scripts/check-release.py --built --tag
```

That final check requires the tag to exist and the App to have been built. Keep any
draft PR's human readiness declarations unchecked until the owner supplies review.
