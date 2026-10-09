# Releasing Bridge Commander

Produces a Developer ID signed, notarized, stapled `.dmg` suitable for distribution outside the App Store.

## One-time setup

1. Install tools:
   ```sh
   brew install create-dmg
   ```
2. Generate and install a **Developer ID Application** certificate in the login keychain.
   - Requires a paid Apple Developer Program membership.
   - In Xcode: *Settings → Accounts → Manage Certificates → + → Developer ID Application*, **or** on developer.apple.com → *Certificates, Identifiers & Profiles → Certificates → + → Software → Developer ID Application* (macOS distribution outside the App Store). Download the `.cer` and double-click to install.
   - Do **not** use *Apple Development*, *Apple Distribution*, *Mac App Distribution*, or *Developer ID Installer* — those sign for Xcode runs, the App Store, or `.pkg` installers respectively and will be rejected by notarization or Gatekeeper for a distributed `.app`/`.dmg`.
   - Verify with `security find-identity -p codesigning -v` — the identity you copy into `.env.release` must start with `Developer ID Application:` and end with your team ID in parentheses.
3. Store your notarization credentials once:
   ```sh
   xcrun notarytool store-credentials bridge-commander-notary \
     --apple-id <your-apple-id> \
     --team-id <TEAMID>
   ```
   When prompted for a password, use an [app-specific password](https://support.apple.com/en-us/102654) generated in your Apple ID account settings.
4. Make sure the Sparkle signing key is in your login keychain. Every update is signed with it,
   and installed copies accept only updates signed with the key whose public half is
   `SUPublicEDKey` in `BridgeCommander/Info.plist`. The tools come with the Sparkle package, so
   after the first `make build-release`:
   ```sh
   build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys -p          # prints the public key if present
   build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys -x key.txt  # back the key up somewhere safe
   build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys -f key.txt  # import it on another machine
   ```
   **Losing this key means no installed copy can ever be updated again**: a new key needs a new
   `SUPublicEDKey`, and only a manually installed build would carry it.
5. Copy the env template and fill in your values:
   ```sh
   cp .env.release.example .env.release
   $EDITOR .env.release
   ```

## Version

Bump the version on `main` before releasing:

```sh
make bump                   # patch: 0.9.2 -> 0.9.3
make bump VERSION=0.10.0    # anything else, only when asked for
git push
```

`make bump` sets `MARKETING_VERSION` in both configurations (`CFBundleVersion` follows it) and commits `chore: bump version to <version>`. Release a patch unless a minor or major version is asked for.

## Release

After bumping a Point-Free package (TCA, Dependencies, CasePaths…), `make build-release` stops with `Macro "…MacrosPlugin" … was changed since a previous approval`: open the project in Xcode, build once and choose **Trust & Enable**, then run it again.

From the repository root:

```sh
make check-tools    # verify prerequisites
make release        # full pipeline
```

`make release` runs: `check-tools → build-release → notarize-app → dmg → notarize-dmg`.

Output: `dist/BridgeCommander-<version>.dmg`.

## Individual steps

Each phase is also a standalone target, useful when iterating:

| Target | Output |
|---|---|
| `make build-release` | `dist/Bridge Commander.app` (signed, not notarized) |
| `make notarize-app` | same `.app`, stapled |
| `make dmg` | `dist/BridgeCommander-<version>.dmg` (signed, not notarized) |
| `make notarize-dmg` | same DMG, stapled |
| `make publish` | GitHub release + tag, with the DMG and `appcast.xml` attached |
| `make clean` | removes `build/` and `dist/` |

## Publish to GitHub

Requires the [GitHub CLI](https://cli.github.com) (`brew install gh`) authenticated with `gh auth login`.

```sh
make publish
```

Tags the current commit `<version>`, pushes the tag, and creates a GitHub release with `dist/BridgeCommander-<version>.dmg` attached. Release notes are generated from the commits since the previous tag.

The release also carries `appcast.xml`, the Sparkle feed for this version (`scripts/make-appcast.sh`): the DMG's EdDSA signature, its download URL, and the same release notes, rendered as Markdown in the update dialog. Installed copies read it from `releases/latest/download/appcast.xml` (`SUFeedURL`), which GitHub resolves to the newest published release, so publishing a release is what offers it as an update. The script refuses to tag anything if the keychain's Sparkle key does not match the app's `SUPublicEDKey`.

`DRAFT=1 make publish` creates the release as a draft so you can edit the notes before making it public.

The target does **not** rebuild — run `make release` first. It refuses to publish if the working tree is dirty, `HEAD` is not pushed, the DMG is missing or unstapled, the DMG was built from a different commit than `HEAD`, or a release for that version already exists.

`make build-release` records the source commit in `dist/.build-revision` (gitignored); the freshness check compares it against `HEAD`. DMGs built before this file existed are treated as stale and must be rebuilt.

## Version bump

Edit `MARKETING_VERSION` in `BridgeCommander.xcodeproj/project.pbxproj` (bump it in both the Debug and Release configurations), then `make release`. `CURRENT_PROJECT_VERSION` (`CFBundleVersion`) is `$(MARKETING_VERSION)`. Sparkle compares versions by `CFBundleVersion`, so it must increase with every release. It used to be a constant `1`, which every release would have shared.

## Troubleshooting

- **Notarization rejected** — scripts print the notarytool log automatically; common causes are missing `--options=runtime`, unsigned binaries inside the bundle, or a revoked certificate.
- **Gatekeeper still warns after install** — verify the app and DMG are stapled:
  ```sh
  xcrun stapler validate dist/Bridge\ Commander.app
  xcrun stapler validate dist/BridgeCommander-<version>.dmg
  ```
- **`security find-identity` doesn't show your cert** — the cert's private key may be missing; re-download the `.p12` bundle or regenerate the cert.
