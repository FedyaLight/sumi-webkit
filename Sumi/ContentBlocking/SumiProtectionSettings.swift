import Combine
import Foundation
import SumiDomain

@MainActor
final class SumiProtectionSettings: ObservableObject {
    private enum DefaultsKey {
        static let level = "settings.protection.level"
        static let appliedLevel = "settings.protection.appliedLevel"
        static let filterListSelection = "settings.protection.filterListSelection"
        static let appliedFilterListSelection =
            "settings.protection.appliedFilterListSelection"
    }

    @Published private(set) var level: SumiProtectionLevel {
        didSet {
            userDefaults.set(level.rawValue, forKey: DefaultsKey.level)
        }
    }

    @Published private(set) var appliedLevel: SumiProtectionLevel {
        didSet {
            userDefaults.set(appliedLevel.rawValue, forKey: DefaultsKey.appliedLevel)
        }
    }

    @Published private(set) var filterListSelection: Set<String>? {
        didSet {
            Self.persist(
                filterListSelection,
                key: DefaultsKey.filterListSelection,
                in: userDefaults
            )
        }
    }

    @Published private(set) var appliedFilterListSelection: Set<String>? {
        didSet {
            Self.persist(
                appliedFilterListSelection,
                key: DefaultsKey.appliedFilterListSelection,
                in: userDefaults
            )
        }
    }

    private let userDefaults: UserDefaults
    var changesPublisher: AnyPublisher<Void, Never> {
        objectWillChange.map { _ in () }.eraseToAnyPublisher()
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let rawLevel = userDefaults.string(forKey: DefaultsKey.level)
        let resolvedLevel = rawLevel.flatMap(SumiProtectionLevel.init(rawValue:)) ?? .off
        if rawLevel != resolvedLevel.rawValue {
            userDefaults.set(resolvedLevel.rawValue, forKey: DefaultsKey.level)
        }
        level = resolvedLevel
        let rawAppliedLevel = userDefaults.string(forKey: DefaultsKey.appliedLevel)
        let resolvedAppliedLevel = rawAppliedLevel.flatMap(SumiProtectionLevel.init(rawValue:)) ?? resolvedLevel
        appliedLevel = resolvedAppliedLevel
        if rawAppliedLevel != resolvedAppliedLevel.rawValue {
            userDefaults.set(resolvedAppliedLevel.rawValue, forKey: DefaultsKey.appliedLevel)
        }
        filterListSelection = Self.selection(
            key: DefaultsKey.filterListSelection,
            in: userDefaults
        )
        appliedFilterListSelection = Self.selection(
            key: DefaultsKey.appliedFilterListSelection,
            in: userDefaults
        )
    }

    func setLevel(_ level: SumiProtectionLevel) {
        guard self.level != level else { return }
        self.level = level
    }

    func setAppliedLevel(_ level: SumiProtectionLevel) {
        guard appliedLevel != level else { return }
        appliedLevel = level
    }

    func selectedFilterListIDs(
        in catalog: SumiFilterListCatalog
    ) -> Set<String> {
        (filterListSelection ?? catalog.defaultEnabledIDs)
            .intersection(catalog.allIDs)
    }

    func appliedFilterListIDs(
        in catalog: SumiFilterListCatalog
    ) -> Set<String> {
        (appliedFilterListSelection ?? catalog.defaultEnabledIDs)
            .intersection(catalog.allIDs)
    }

    func setFilterList(
        _ id: String,
        enabled: Bool,
        catalog: SumiFilterListCatalog
    ) {
        guard catalog.allIDs.contains(id) else { return }
        var selected = selectedFilterListIDs(in: catalog)
        if enabled {
            selected.insert(id)
        } else {
            selected.remove(id)
        }
        filterListSelection = selected
    }

    func resetFilterListsToDefaults() {
        guard filterListSelection != nil else { return }
        filterListSelection = nil
    }

    func markFilterListSelectionApplied(
        in catalog: SumiFilterListCatalog
    ) {
        setAppliedFilterListIDs(
            selectedFilterListIDs(in: catalog),
            catalog: catalog
        )
    }

    func setAppliedFilterListIDs(
        _ ids: Set<String>,
        catalog: SumiFilterListCatalog
    ) {
        let applied = ids.intersection(catalog.allIDs)
        appliedFilterListSelection = applied == catalog.defaultEnabledIDs
            ? nil
            : applied
    }

    func filterListSelectionApplyNeeded(
        in catalog: SumiFilterListCatalog
    ) -> Bool {
        selectedFilterListIDs(in: catalog)
            != appliedFilterListIDs(in: catalog)
    }

    private static func selection(
        key: String,
        in defaults: UserDefaults
    ) -> Set<String>? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return Set(defaults.stringArray(forKey: key) ?? [])
    }

    private static func persist(
        _ selection: Set<String>?,
        key: String,
        in defaults: UserDefaults
    ) {
        if let selection {
            defaults.set(selection.sorted(), forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
