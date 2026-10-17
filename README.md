# Gainsday

Gainsday is an iPhone app that puts your workouts from Apple Health into a calendar you choose. It works with any calendar already set up on your phone: iCloud, Google, or Outlook/Exchange.

- Workouts appear in your calendar automatically, shortly after they finish.
- You decide what each event says, using templates like `{emoji} {type} · {distance}`.
- If you delete a workout in Health, its event goes too. If you edit or delete an event yourself, Gainsday leaves it alone.
- An activity log shows everything the app did, with Undo.

Gainsday is in early development, and these features are being built now.

## No server, no account

Gainsday has no server, no account and no analytics. Your workouts are read on your phone and written to your calendar on your phone. The only cloud storage it uses is your own iCloud, to remember which event belongs to which workout and to back up your settings.

The code is open source so that you can check this for yourself.

## Building

You need a Mac with Xcode 27 or later. The app runs on iOS 26 or later.

1. Clone the repository and open `Gainsday.xcodeproj`.
2. Choose the **Gainsday** scheme and an iPhone simulator, then press ⌘R to run.

To run on your own iPhone, select the Gainsday target and, under **Signing & Capabilities**, choose your own team and change the bundle identifier and iCloud container to ones you own. HealthKit and iCloud need a paid Apple Developer account.

## Testing

The sync logic lives in **SyncCore**, a Swift package in `Packages/SyncCore` with no UI and no HealthKit, EventKit or CloudKit dependency. Its tests run on the Mac without a simulator:

```sh
cd Packages/SyncCore
swift test
```

In Xcode, ⌘U on the Gainsday scheme runs both the SyncCore tests and the app's tests on the simulator.

## Project layout

- `Packages/SyncCore`: domain types, the sync engine, and protocols (ports) for every side effect. `SyncCoreTesting` holds in-memory fakes of each port for tests and previews.
- `Gainsday`: the SwiftUI app and the adapters that implement SyncCore's ports with HealthKit, EventKit, SwiftData and iCloud.
- `GainsdayTests`: tests for the app target.

User-facing strings live in String Catalogs (`Localizable.xcstrings` and `InfoPlist.xcstrings`), so translations can be added there.

## License

MIT. See [LICENSE](LICENSE).
