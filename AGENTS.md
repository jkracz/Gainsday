# AGENTS.md

Gainsday is an iPhone app (iOS 26+, SwiftUI) that copies workouts from Apple Health into a calendar the user picks. It has no server, no account and no analytics: everything runs on the phone, and the only cloud storage is the user's own iCloud.

## Communication

### Content

The engineers working on this codebase spend their whole days working with AI agents. It requies a lot of reading, and they have short attention spans. Therefore it is critical that you respond as cleanly and concisely as possible. Walls of text are the enemy.

### Requesting Human Help

- End every turn where you're blocked on me, or where the next step needs me, with a short "**What I need from you**" section. Numbered, one concrete action or decision per item: exactly what to do, where (which site, app, file or person), and what to send back. e.g. "Open the Convex dashboard, add `OPENAI_API_KEY` under Settings → Environment Variables, then reply 'done'", not "I need the API key set up".
- If there are several, put the quickest or most blocking one first, and say what you'll get on with in the meantime.
- If you don't need anything from me, say "Nothing needed from you right now", and say whether the work is finished or still going.
- Never bury a request for me in the middle of a long update.

## Conventions

- Tests use Swift Testing (`import Testing`, `@Suite`, `@Test("plain-English behaviour")`, `#expect`), not XCTest. Engine tests build a `SyncHarness` (see `SyncHarness.swift` in the SyncCore tests), arrange the fakes, run a pass, then assert on the calendar, ledger and actions.
- Get time from the `Clock` port, never from `Date()`, in SyncCore. Tests use `FixedClock`.
- The app target defaults to `@MainActor` isolation (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, with approachable concurrency turned on). Mark an adapter `nonisolated` when it conforms to a `Sendable` port, as `SystemClock` does. SyncCore uses Swift 6 language mode.
- The Xcode project uses synchronized folders, so files added under `Gainsday/` or `GainsdayTests/` are picked up without editing `project.pbxproj`.
- Put user-facing strings in `Localizable.xcstrings` and `InfoPlist.xcstrings`, not in hard-coded literals.
- Never commit signing material, team IDs or personal bundle identifiers.

## Agent skills

### Issue tracker

Issues and specs live in GitHub Issues on `jkracz/Gainsday`, managed with the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root, created only when they're first needed. See `docs/agents/domain.md`.
