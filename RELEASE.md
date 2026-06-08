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
4. Copy the env template and fill in your values:
   ```sh
   cp .env.release.example .env.release
   $EDITOR .env.release
   ```

## Release

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
| `make clean` | removes `build/` and `dist/` |

## Version bump

Edit `MARKETING_VERSION` in `BridgeCommander.xcodeproj/project.pbxproj` (bump it in both the Debug and Release configurations), then `make release`.

## Troubleshooting

- **Notarization rejected** — scripts print the notarytool log automatically; common causes are missing `--options=runtime`, unsigned binaries inside the bundle, or a revoked certificate.
- **Gatekeeper still warns after install** — verify the app and DMG are stapled:
  ```sh
  xcrun stapler validate dist/Bridge\ Commander.app
  xcrun stapler validate dist/BridgeCommander-<version>.dmg
  ```
- **`security find-identity` doesn't show your cert** — the cert's private key may be missing; re-download the `.p12` bundle or regenerate the cert.
