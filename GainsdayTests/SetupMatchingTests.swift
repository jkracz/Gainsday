import SyncCore
import Testing
@testable import Gainsday

@Suite("Setup's planned-events choice")
struct SetupMatchingTests {
    @Test("A fresh install shows Not Now chosen")
    func freshInstallShowsNotNow() {
        #expect(SetupModel().showsMatchingOn(Settings()) == false)
    }

    @Test("Choosing Not Now leaves matching off, even if restored settings had it on")
    func notNowLeavesMatchingOff() {
        let model = SetupModel()
        var restored = Settings()
        restored.matchingEnabled = true
        #expect(model.showsMatchingOn(restored))

        model.enablesMatching = false
        model.choices(&restored)

        #expect(restored.matchingEnabled == false)
        #expect(model.showsMatchingOn(restored) == false)
    }

    @Test("Choosing to update planned events turns matching on")
    func choosingOnTurnsMatchingOn() {
        let model = SetupModel()
        var settings = Settings()

        model.enablesMatching = true
        model.choices(&settings)

        #expect(settings.matchingEnabled)
    }

    @Test("When the user never answered, setup leaves the matching setting as it was")
    func skippedStepKeepsSetting() {
        var restored = Settings()
        restored.matchingEnabled = true

        SetupModel().choices(&restored)

        #expect(restored.matchingEnabled)
    }
}
