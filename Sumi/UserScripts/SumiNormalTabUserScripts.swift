import WebKit

@MainActor
final class SumiNormalTabUserScripts: SumiUserScriptsProvider {
    let faviconScripts = SumiDDGFaviconUserScripts()
    private var contentBlockingUserScripts: [SumiUserScript]
    private var managedUserScripts: [SumiUserScript]
    private(set) var scriptsRevision = 0

    init(
        contentBlockingUserScripts: [SumiUserScript] = [],
        managedUserScripts: [SumiUserScript] = []
    ) {
        self.contentBlockingUserScripts = contentBlockingUserScripts
        self.managedUserScripts = managedUserScripts
    }

    var userScripts: [SumiUserScript] {
        contentBlockingUserScripts + faviconScripts.userScripts + managedUserScripts
    }

    func replaceManagedUserScripts(_ userScripts: [SumiUserScript]) {
        managedUserScripts = userScripts
        scriptsRevision += 1
    }

    func loadWKUserScripts() async -> [WKUserScript] {
        var scripts: [WKUserScript] = []
        scripts.reserveCapacity(userScripts.count)
        for userScript in userScripts {
            scripts.append(SumiUserScriptBuilder.makeWKUserScript(from: userScript))
        }
        return scripts
    }
}
