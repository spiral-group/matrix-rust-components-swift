# Scripts

_Modified by the Spiral authors, 2026: local-only builds, provenance, and
publishing only to an explicitly named Spiral owner._

## Release

Builds the sibling `matrix-rust-sdk` checkout, refreshes generated Swift
sources, records exact source/artifact provenance and optionally creates a
GitHub release.

For local development, no credential, commit, push or release API call is used:

```sh
swift run release --custom-version 26.07.28-spiral.0 --local-only
```

This installs the built `MatrixSDKFFI.xcframework` beside `Package.swift`, where
the manifest automatically selects it for a sibling path dependency. The tool
also invalidates SwiftPM's manifest cache after installing the ignored local
framework. Verify target selection before an app build:

```sh
swift package --manifest-cache none dump-package
```

The `MatrixSDKFFI` target must contain `"path" :
"MatrixSDKFFI.xcframework"`, not a release URL. The local framework and zip are
ignored; `PROVENANCE.json` and generated-source diffs are reviewable.

Publishing is deliberately fail-closed. It requires an explicit Spiral GitHub
owner, asset URL and a matching `origin`; the tool never pushes to `upstream`:

```sh
swift run release \
  --custom-version 26.07.28-spiral.1 \
  --github-owner <spiral-owner> \
  --release-base-url https://github.com/<spiral-owner>/matrix-rust-components-swift/releases/download
```

For all options: `swift run release --help`.

## Requirements

To make the release you will need the following installed:
1. cargo + rustup https://www.rust-lang.org/tools/install
2. `matrix-rust-sdk` cloned next to this repository.
3. Checkout the exact SDK branch/commit to build.
4. Install the Apple targets and dependencies listed in the [Apple platforms readme](https://github.com/matrix-org/matrix-rust-sdk/blob/main/bindings/apple/README.md).
5. Publishing only: configure `api.github.com` in `~/.netrc` and a matching
   Spiral `origin` remote. Local-only builds require neither.
