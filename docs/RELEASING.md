# Releasing a new version

Everyone running Grid Studio gets the new version the next time they open the app.

## One time setup (on the Mac you release from)

1. A **Developer ID Application** certificate in your keychain (Xcode → Settings → Accounts → Manage Certificates).
2. Notarization credentials saved in the keychain, using an app specific password from [account.apple.com](https://account.apple.com):

   ```sh
   xcrun notarytool store-credentials GridStudio-notary \
     --apple-id "<your Apple ID>" --team-id "<your Team ID>" --password "<app specific password>"
   ```

3. The Sparkle signing key. It was created once with
   `.build/artifacts/sparkle/Sparkle/bin/generate_keys --account GridStudio`
   and lives in the login keychain. Its public half is `SPARKLE_PUBLIC_KEY` in `scripts/build-app.sh`.
   **Back it up** (`generate_keys --account GridStudio -x sparkle-key.txt`, store the file somewhere safe and offline).
   If the private key is lost, existing installs can never be updated again.
4. `gh auth login` so the script can create the GitHub release.

## Every release

Commit your code changes, then:

```sh
./scripts/release.sh 1.1.0 "Added scale layouts
Fixed a crash when the grid is unplugged"
```

Each line of the notes becomes a bullet in the update window.

The script:

1. writes the version to `VERSION` and builds the signed universal app,
2. sends it to Apple for notarization and staples the ticket,
3. zips it and signs the zip with the Sparkle key,
4. adds an entry to `appcast.xml`, commits it and tags `v1.1.0`,
5. creates the GitHub release with the zip attached, then pushes, so the update only goes live once the download exists.

Version numbers must always go up (1.0.0 → 1.0.1 → 1.1.0). Sparkle compares them to decide what is newer.
