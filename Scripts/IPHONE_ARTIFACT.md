# Readout unsigned iPhone build

This package contains an **unsigned arm64 iOS device archive** with Readout and
its widget extension. It is not an installable IPA and cannot be installed by
AirDrop, Files, or dragging it into an iPhone. Apple signing and provisioning are
required before the app can run on a device.

Contents:

- `Readout.xcarchive.zip`: the app and widget archive.
- `BUILD_INFO.json`: source commit, Xcode/SDK versions, bundle IDs, and signing status.
- `SHA256SUMS`: SHA-256 checksum for the archive ZIP.
- `INSTALLING.md`: these instructions.

On a Mac, verify the download with `shasum -a 256 -c SHA256SUMS` and unzip the
archive. Opening `Readout.xcarchive` in Xcode Organizer lets you inspect the
build. The archive has no signing identity or provisioning profiles; opening it
does not make it installable.

The reliable route to your own iPhone is to build and sign from the same source
commit on your Mac:

1. Clone/download `https://github.com/JoniSuominen/ios-weather-widget` and check out
   the commit recorded in `BUILD_INFO.json`.
2. Install Xcode and XcodeGen (`brew install xcodegen`). Add your Apple account in
   Xcode → Settings → Accounts.
3. Connect and trust your iPhone, and enable Developer Mode when requested. Ensure
   your Apple Developer team owns the app IDs and shared App Group.
4. Run `Scripts/install-on-iphone.sh --list` for the physical iPhone's ID.
5. Run `Scripts/install-on-iphone.sh --team YOUR_TEAM_ID --device YOUR_IPHONE_UDID`.
   Add `--broker-url https://your-deployed-broker` if you have configured direct Oura
   access; without it, use Apple Health mode.

The local script regenerates the project, builds with automatic signing, installs
both the app and embedded widget, and launches Readout. Alternatively, open the
project in Xcode, set your Team on both targets, and Run on your iPhone. Consult
`DEPLOYMENT.md` in the repository for capabilities, Oura configuration, and testing.

For TestFlight or an ad-hoc IPA, create a **signed** archive in Xcode using your
Apple Developer distribution credentials, then export through Organizer. This
unsigned CI artifact is not a TestFlight upload or an App Store submission. Do not
send private keys, certificates, passwords, or provisioning profiles in chat or
commit them to the repository.
