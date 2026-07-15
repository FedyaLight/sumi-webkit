import SumiDomain

enum ShortcutLiveRetirementSplitProjection {
    static func removingDeletedPins(
        _ pinIDs: Set<UUID>,
        from groups: [SumiDomain.SplitGroup]
    ) -> [SumiDomain.SplitGroup] {
        groups.compactMap { source in
            pinIDs.reduce(Optional(source)) { group, pinID in
                guard let group,
                      group.memberIDs.contains(.shortcutPin(pinID)) else {
                    return group
                }
                return group.removingMember(.shortcutPin(pinID))
            }
        }
    }

}
