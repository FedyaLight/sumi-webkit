@testable import Sumi
import SumiDomain
import Testing

struct BrowserActionMenuOwnershipTests {
    @Test func everyConfigurableBrowserActionHasExactlyOneMenuOwner() {
        let actions = BrowserActionMenuOwnershipCatalog.allActions

        #expect(Set(actions).count == actions.count)
        #expect(
            Set(actions)
                == Set(ShortcutAction.allCases)
                    .subtracting(KeyboardCommandAssignments.nativeCommandActions)
        )
    }
}
