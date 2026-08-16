# Testing and deploying Pulseboard — a beginner's guide

This guide separates three different goals that are easy to confuse:

| Goal | What you need | Cost |
| --- | --- | --- |
| Check that the code compiles | GitHub account (using the included workflow) | Free within GitHub's allowance |
| Try the app in an iPhone simulator | A Mac capable of running Xcode | Free |
| Put the app and widget on an iPhone reliably | A Mac, iPhone, and usually Apple Developer Program membership | Apple currently charges for membership |
| Give the app to other testers | Apple Developer Program membership and TestFlight | Membership required |

> **Important:** Pulseboard is currently a visual prototype with shared widget
> storage. Oura, Apple Health, and Google Calendar authentication is not implemented.
> The Connect buttons save a local demonstration state, and the metrics are sample
> data. This is expected—not a setup failure.

## Option A: verify the build on GitHub (no Mac)

Every push triggers `.github/workflows/ios-build.yml`. On GitHub:

1. Open the repository and select **Actions**.
2. Select **iOS Build**.
3. Choose **Run workflow**, or push a commit and open the automatically started run.
4. Wait for **Generate project & build (app + widget)** to turn green.
5. Open the run's **Artifacts** section. The best-effort screenshot job may provide
   an `app-screenshot` download.

This proves that both targets compile. It does **not** install the app on your phone.
Apple's simulator and signing tools only run on macOS.

## Option B: run in the iPhone simulator (recommended first step)

### 1. Install the tools

1. Install the latest stable **Xcode** from the Mac App Store.
2. Open Xcode once, accept the licence, and let it install the requested components.
3. If Xcode asks for an iOS simulator runtime, install one under **Xcode → Settings →
   Platforms**.
4. Open Terminal and install [Homebrew](https://brew.sh/) if needed, then XcodeGen:

   ```bash
   brew install xcodegen
   ```

### 2. Generate and open the project

In Terminal, change to this repository and run:

```bash
cd /path/to/ios-weather-widget
xcodegen generate
open WeatherUV.xcodeproj
```

`project.yml` is the source of truth. If you edit it, regenerate the Xcode project.
Do not make important project-setting changes only in the generated project because
the next `xcodegen generate` can overwrite them.

### 3. Launch the app

1. At the top of Xcode, select the **WeatherUV** scheme.
2. Select an installed iPhone simulator, such as **iPhone 16 Pro**.
3. Press the triangular Run button or **⌘R**.
4. The simulator should open Pulseboard. Test the Today, Sources, and Widgets tabs.
5. In Sources, toggle connection buttons. Close and reopen the app to confirm the
   demonstration state persists.

No signing team is necessary for a simulator build.

### 4. Test Home Screen widgets

1. Leave Pulseboard installed and return to the simulator Home Screen.
2. Long-press an empty area and choose the **+** add button.
3. Search for **Pulseboard**.
4. Add both the small and medium variants.
5. Return to Pulseboard → Widgets and press **Refresh my widgets**.

WidgetKit decides the exact refresh time, so refresh requests are not always
instantaneous. The widget also creates a new timeline approximately every 30 minutes.

### 5. Test Lock Screen widgets

1. Lock the simulated phone, then long-press the Lock Screen and choose **Customize**.
2. Select **Lock Screen**, tap the widget area, and search for Pulseboard.
3. Try the circular, rectangular, and inline variants.

Simulator menus vary slightly by the iOS runtime. If Pulseboard is missing from the
widget gallery, launch the host app once, wait briefly, and restart the simulator.

## Option C: install on your own iPhone

Start only after the simulator build works.

### 1. Choose identifiers you control

The example identifiers cannot be used for a signed release. Pick a reverse-domain
prefix, for example `com.yourname`, and replace all of these consistently:

- App bundle ID in `project.yml`: `com.example.WeatherUV`
- Widget bundle ID in `project.yml`: `com.example.WeatherUV.Widget`
- App Group in both entitlement files: `group.com.example.WeatherUV`
- `DashboardStore.appGroupID` in `Shared/DashboardData.swift`

The widget bundle identifier should remain beneath the app identifier, and the exact
same App Group must be enabled for both targets.

Regenerate the project after changing identifiers:

```bash
xcodegen generate
```

### 2. Configure signing in Xcode

1. Connect the unlocked iPhone to the Mac and trust the computer when prompted.
2. In Xcode, open **Settings → Accounts** and add your Apple ID.
3. Select the project in the navigator, then the **WeatherUV** app target.
4. Under **Signing & Capabilities**, enable automatic signing and select your Team.
5. Repeat for the **WeatherUVWidget** target.
6. Confirm that both targets list the same **App Groups** capability and group.

A free Personal Team may be enough for basic short-lived device testing, but advanced
capabilities and reliable distribution can require paid program membership. If Xcode
reports that App Groups are unavailable for your team, use a paid developer team.

### 3. Run on the phone

1. Enable **Developer Mode** on the iPhone if iOS asks you to do so.
2. Choose your iPhone as Xcode's run destination.
3. Press **⌘R** and resolve any signing message shown in Xcode.
4. Launch Pulseboard once before adding its widgets from the iPhone Home or Lock Screen.

## Option D: distribute through TestFlight

TestFlight is the usual way to let other people test without connecting their phones
to your Mac. It requires Apple Developer Program membership and an App Store Connect
app record.

1. Create an app in App Store Connect using the final app bundle identifier.
2. In Xcode, choose **Any iOS Device (arm64)** as the destination.
3. Select **Product → Archive**.
4. In Organizer, choose **Distribute App → App Store Connect → Upload**.
5. Wait for Apple to process the build, then open its TestFlight tab in App Store
   Connect.
6. Add internal testers. External testers require Apple's beta review.

The repository's GitHub workflow only compiles for the simulator; it intentionally
does not contain distribution certificates or App Store Connect credentials. Add a
separate, secret-backed archive/upload workflow only after manual archiving succeeds.

## What to test

Use this checklist before adding real integrations:

- [ ] Today, Sources, and Widgets tabs open without layout clipping.
- [ ] Source connection state remains after relaunching the app.
- [ ] Small and medium Home Screen widgets appear.
- [ ] Circular, rectangular, and inline Lock Screen widgets appear.
- [ ] **Refresh my widgets** does not crash the app.
- [ ] Light Mode, Dark Mode, and larger Accessibility text remain readable.
- [ ] Airplane Mode does not break the sample dashboard.

After real connectors are implemented, also test authorization denial, expired OAuth
tokens, no calendar events, missing Health data, airplane mode, and stale widget data.

## Common problems

### “Apply changes and continue locally” skips every file

The apply operation expects the local checkout to still match the commit from which the
task started. It intentionally skips files when applying would overwrite local edits,
including untracked files with the same names. **Do not delete those files blindly.**

First, open Terminal in the repository and inspect the checkout:

```bash
git status --short --branch
git log --oneline -5
```

If `git status` lists modified or untracked files, save all of them—including untracked
files—before trying Apply again:

```bash
git stash push --include-untracked -m "before applying Pulseboard changes"
git status --short --branch
```

The second status should show a clean working tree. Retry **Apply changes and continue
locally**. After it succeeds, inspect the result before restoring the stash:

```bash
git status --short
git diff --check
git stash list
```

Only run `git stash pop` if the stashed changes are work you still want; it may produce
normal merge conflicts when both versions changed the same files. Use `git stash show
--stat stash@{0}` first if you are unsure.

If the working tree was already clean, the local branch probably has a different base.
The safest beginner option is to clone the repository into a new folder at the same
branch/commit where the task began and apply there. Do not use `git reset --hard` unless
you have made a backup and understand that it discards uncommitted work.

If the Pulseboard commit already appears in `git log`, there is nothing left to apply:
the files were skipped because the result is already present. Generate the project with
`xcodegen generate` and continue with the simulator steps above.

### “No such module” or project files are missing

Run `xcodegen generate` again and open `WeatherUV.xcodeproj`, not individual Swift
files.

### Signing says the bundle identifier is unavailable

You are still using `com.example`, or someone else owns that identifier. Replace it
with a globally unique prefix you control, then regenerate the project.

### The app works but the widget shows old/sample data

Confirm that both targets have the exact same App Group entitlement and that
`DashboardStore.appGroupID` matches it. Then launch the app once and request a refresh.

### The Connect buttons do not open Apple/Google/Oura login

That is the current prototype behavior. Provider authorization and API clients are a
separate implementation step; credentials alone will not activate these buttons.
