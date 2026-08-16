# Local-first architecture and App Store plan

## Short answer

Pulseboard currently works completely locally. It has no login, server, analytics SDK,
cloud database, or runtime API request. `DashboardStore` writes three values to the app's
shared App Group `UserDefaults`:

- the latest array of dashboard metrics;
- the set of sources marked as connected;
- the snapshot update time.

The widget extension reads the same App Group and renders that snapshot. The sample
metrics are compiled into the app and are used when no snapshot has been saved.

The repository still contains unused legacy weather source files. They are compiled,
but the Pulseboard app and provider do not call `WeatherService`; those files can be
removed before release to make the privacy story unambiguous.

## A no-database production design

You can ship a useful version without operating an online database:

```text
HealthKit ─┐
           ├─> host app ─> App Group snapshot ─> WidgetKit extension
EventKit ──┘
```

### Apple Health

Use HealthKit read authorization and queries inside the host app. HealthKit is the
system data store; Pulseboard does not need to copy a user's history to a server. Save
only the small, latest display snapshot needed by WidgetKit. The user can revoke access
in iOS Settings.

### Google Calendar without Google's API

Use EventKit rather than Google OAuth. If the user has added their Google account under
iOS calendar accounts, its calendars are available through EventKit after calendar
permission is granted. This avoids a Google client ID, refresh tokens, a backend, and an
additional privacy surface. It also works for iCloud, Exchange, and other calendars.

In the UI, describe this source as **Calendar** and explain that it uses calendars
configured on the iPhone. Do not imply that Pulseboard logs directly into Google.

### Oura: choose one of two approaches

**Simplest and fully local:** read the Oura data that the Oura app shares with Apple
Health. This needs no Oura login in Pulseboard and no backend. The limitation is that
some Oura-specific values—especially proprietary scores such as Readiness—may not be
available through HealthKit.

**Richer but online:** use the Oura API for Oura-only metrics. API calls necessarily use
the internet. OAuth credentials and refresh tokens must be handled safely; a public,
open-source binary cannot keep an embedded client secret secret. A small stateless token
broker may be appropriate, but it is still an online service even if it stores no user
database. Document this clearly and keep tokens in Keychain, never `UserDefaults`.

The implemented scope is HealthKit + EventKit, with Oura sleep data consumed through
Apple Health where available. Direct Oura API support should only be added if its extra
metrics justify OAuth infrastructure, operational ownership, and privacy cost.

## What “local” does and does not mean

- The App Group is storage on the device, not a hosted database.
- HealthKit and EventKit are Apple system frameworks, not Pulseboard servers.
- Google or Oura's own apps may sync their data using their services. Pulseboard does
  not control those providers' synchronization.
- iOS may include app data in an encrypted device backup depending on system settings.
- App Store distribution still requires Apple review and developer-program membership,
  even if the download price is free and the source code is public.
- A free app can still have ongoing costs such as developer membership, support, and—if
  direct Oura access is added—hosting.

## Privacy-oriented implementation rules

1. Request only the HealthKit and EventKit data types the selected widgets need.
2. Explain each permission immediately before presenting the system prompt.
3. Keep detailed health/event history in the system stores; persist only a minimal
   widget snapshot in the App Group.
4. Put OAuth tokens in Keychain if an online provider is added.
5. Add no analytics or crash-reporting SDK by default. If one is added, make it opt-in
   and document it.
6. Provide a **Delete local data** action that clears the App Group snapshot and source
   state, then reloads WidgetKit timelines.
7. Maintain an accurate privacy policy and App Store privacy disclosure, even when the
   correct disclosure is that data is not collected by the developer.

## Open-source release checklist

- [ ] Replace all example bundle and App Group identifiers.
- [ ] Add a `LICENSE` file with the chosen OSI-approved license.
- [x] Add HealthKit and calendar usage descriptions to `Info.plist`.
- [x] Add HealthKit capability to the host app; do not give the widget direct HealthKit
      access. The host should publish a minimal snapshot for the widget.
- [x] Implement EventKit authorization and filter out private event details that are not
      needed by the selected widget.
- [x] Implement local-data deletion and connector error states.
- [ ] Remove the unused weather/location code. The location permission has been removed.
- [ ] Replace sample values with honest empty/loading/error states.
- [ ] Add a privacy policy URL and complete App Store privacy answers based on the final
      binary's actual behavior.
- [ ] Keep signing certificates, App Store API keys, OAuth secrets, and provisioning
      profiles out of Git.
- [ ] Test accessibility, denied permissions, no-data states, stale snapshots, and
      widgets after reboot.

Open-source licensing and App Store distribution are compatible, but the App Store copy
is still signed and submitted by the developer account that owns its bundle identifier.
Contributors can build their own copy using different identifiers.
