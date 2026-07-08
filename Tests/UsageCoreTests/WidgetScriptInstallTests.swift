import Testing
@testable import UsageCore

struct WidgetScriptInstallTests {
    @Test func installsWhenAbsent() {
        #expect(WidgetScriptInstall.decide(existing: nil) == .install)
    }

    @Test func skipsUserOwnedWithoutMarker() {
        // A hand-pasted or user-authored script has no marker: never clobber it.
        #expect(WidgetScriptInstall.decide(existing: "// my own widget\nlet x = 1")
                == .skipUserOwned)
    }

    @Test func skipsWhenSameVersion() {
        let existing = WidgetScriptInstall.stamped("body", version: 1)
        #expect(WidgetScriptInstall.decide(existing: existing, currentVersion: 1)
                == .skipUpToDate)
    }

    @Test func skipsWhenNewerOnDisk() {
        let existing = WidgetScriptInstall.stamped("body", version: 5)
        #expect(WidgetScriptInstall.decide(existing: existing, currentVersion: 2)
                == .skipUpToDate)
    }

    @Test func reinstallsWhenOlder() {
        let existing = WidgetScriptInstall.stamped("body", version: 1)
        #expect(WidgetScriptInstall.decide(existing: existing, currentVersion: 3)
                == .install)
    }

    @Test func stampRoundTrips() {
        let stamped = WidgetScriptInstall.stamped("console.log(1)", version: 7)
        #expect(WidgetScriptInstall.managedVersion(of: stamped) == 7)
        // The original body is preserved after the marker line.
        #expect(stamped.hasSuffix("\nconsole.log(1)"))
    }

    @Test func markerToleratesNoTrailingBody() {
        #expect(WidgetScriptInstall.managedVersion(of: WidgetScriptInstall.markerLine(version: 2)) == 2)
    }

    @Test func findsMarkerAfterScriptablePrependsItsHeader() {
        // Scriptable rewrites the top of a script the user opens; our marker
        // ends up a few lines down. We must still recognize (and update) it.
        let scriptableized = """
        // Variables used by Scriptable.
        // These must be at the very top of the file. Tap to edit.
        // icon-color: deep-blue; icon-glyph: magic;
        \(WidgetScriptInstall.markerLine(version: 1))
        // ... rest of the widget ...
        """
        #expect(WidgetScriptInstall.managedVersion(of: scriptableized) == 1)
        #expect(WidgetScriptInstall.decide(existing: scriptableized, currentVersion: 2) == .install)
    }
}
