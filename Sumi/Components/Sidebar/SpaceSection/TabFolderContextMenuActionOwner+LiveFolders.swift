import Foundation

extension TabFolderContextMenuActionOwner {
    func liveFolderHeaderContextMenuEntries(
        followedBy folderEntries: [SidebarContextMenuEntry]
    ) -> [SidebarContextMenuEntry] {
        let source = currentLiveFolderSource()
        let statusTitle: String = {
            if let error = source?.lastErrorKind {
                return error.displayTitle
            }
            if let lastSuccessAt = source?.lastSuccessAt {
                return "Last Updated \(lastSuccessAt.formatted(date: .omitted, time: .shortened))"
            }
            return "Not Updated Yet"
        }()

        let liveFolderOptions = joinSidebarMenuSections(
            [
                [
                    .action(.init(
                        title: statusTitle,
                        systemImage: "clock",
                        isEnabled: false,
                        classification: .presentationOnly
                    ) { /* Disabled status row. */ }),
                    refreshIntervalSubmenu(for: source),
                    .action(.init(
                        title: "Refresh Now",
                        systemImage: "arrow.clockwise",
                        classification: .stateMutationNonStructural
                    ) {
                        browserContext.liveFolderManager.refresh(folderId: folder.id)
                    }),
                ],
                liveFolderProviderOptionEntries(source),
            ]
        )
        return makeLiveFolderHeaderContextMenuEntries(
            options: liveFolderOptions,
            folderEntries: folderEntries
        )
    }

    func refreshIntervalSubmenu(for source: SumiLiveFolderSource?) -> SidebarContextMenuEntry {
        let options: [(title: String, seconds: TimeInterval)] = [
            ("15 Minutes", 15 * 60),
            ("30 Minutes", 30 * 60),
            ("1 Hour", 60 * 60),
            ("2 Hours", 2 * 60 * 60),
            ("4 Hours", 4 * 60 * 60),
            ("8 Hours", 8 * 60 * 60),
        ]
        let currentInterval = source?.refreshIntervalSeconds

        return .submenu(
            title: "Refresh Every",
            systemImage: "timer",
            children: options.map { option in
                .action(
                    .init(
                        title: option.title,
                        systemImage: nil,
                        isEnabled: currentInterval != option.seconds,
                        state: currentInterval == option.seconds ? .on : .off,
                        classification: .stateMutationNonStructural
                    ) {
                        browserContext.liveFolderManager.setRefreshInterval(
                            folderId: folder.id,
                            seconds: option.seconds
                        )
                    }
                )
            }
        )
    }

    func liveFolderProviderOptionEntries(
        _ source: SumiLiveFolderSource?
    ) -> [SidebarContextMenuEntry] {
        guard let source else { return [] }
        switch source.kind {
        case .rss:
            return rssLiveFolderOptionEntries(source)
        case .githubPullRequests, .githubIssues:
            return gitHubLiveFolderOptionEntries(source)
        }
    }

    func rssLiveFolderOptionEntries(
        _ source: SumiLiveFolderSource
    ) -> [SidebarContextMenuEntry] {
        let itemLimits = [5, 10, 25, 50]
        let hour: TimeInterval = 60 * 60
        let timeRanges: [(String, TimeInterval)] = [
            ("All Time", 0),
            ("1 Hour", hour),
            ("6 Hours", 6 * hour),
            ("12 Hours", 12 * hour),
            ("24 Hours", 24 * hour),
            ("3 Days", 3 * 24 * hour),
        ]
        let currentTimeRange = source.timeRangeSeconds ?? 0

        return [
            .action(.init(
                title: "Feed URL…",
                systemImage: "link",
                classification: .stateMutationNonStructural
            ) {
                browserContext.folderActions.editRSSLiveFolder(
                    folder.id,
                    in: windowState
                )
            }),
            .submenu(
                title: "Item Limit",
                systemImage: "list.number",
                children: itemLimits.map { limit in
                    .action(.init(
                        title: "\(limit) Items",
                        systemImage: nil,
                        isEnabled: source.maxItems != limit,
                        state: source.maxItems == limit ? .on : .off,
                        classification: .stateMutationNonStructural
                    ) {
                        browserContext.liveFolderManager.setRSSItemLimit(
                            folderId: folder.id,
                            maxItems: limit
                        )
                    })
                }
            ),
            .submenu(
                title: "Time Range",
                systemImage: "calendar.badge.clock",
                children: timeRanges.map { option in
                    let (title, seconds) = option
                    return .action(.init(
                        title: title,
                        systemImage: nil,
                        isEnabled: currentTimeRange != seconds,
                        state: currentTimeRange == seconds ? .on : .off,
                        classification: .stateMutationNonStructural
                    ) {
                        browserContext.liveFolderManager.setRSSTimeRange(
                            folderId: folder.id,
                            seconds: seconds
                        )
                    })
                }
            ),
        ]
    }

    func gitHubLiveFolderOptionEntries(
        _ source: SumiLiveFolderSource
    ) -> [SidebarContextMenuEntry] {
        let filterEntries: [SidebarContextMenuEntry] = [
            gitHubFilterEntry(
                title: "Authored by Me",
                isEnabled: source.githubFilters.authorMe
            ) { filters in
                filters.authorMe.toggle()
            },
            gitHubFilterEntry(
                title: "Assigned to Me",
                isEnabled: source.githubFilters.assignedMe
            ) { filters in
                filters.assignedMe.toggle()
            },
        ] + (source.kind == .githubPullRequests ? [
            gitHubFilterEntry(
                title: "Review Requested",
                isEnabled: source.githubFilters.reviewRequested
            ) { filters in
                filters.reviewRequested.toggle()
            },
        ] : [])

        let repositories = source.activeRepositories
            .union(source.excludedRepositories)
            .sorted()
        let repositoryEntry: SidebarContextMenuEntry = .submenu(
            title: "Repositories",
            systemImage: "shippingbox",
            children: repositories.isEmpty
                ? [
                    .action(.init(
                        title: "No Repositories Yet",
                        systemImage: nil,
                        isEnabled: false,
                        classification: .presentationOnly
                    ) { /* Disabled empty-state row. */ }),
                ]
                : repositories.map { repository in
                    let isIncluded = !source.excludedRepositories.contains(repository)
                    return .action(.init(
                        title: repository,
                        systemImage: nil,
                        state: isIncluded ? .on : .off,
                        classification: .stateMutationNonStructural
                    ) {
                        browserContext.liveFolderManager.setGitHubRepositoryIncluded(
                            folderId: folder.id,
                            repository: repository,
                            isIncluded: !isIncluded
                        )
                    })
                }
        )
        return filterEntries + [repositoryEntry]
    }

    func gitHubFilterEntry(
        title: String,
        isEnabled: Bool,
        mutate: @escaping (inout SumiGitHubLiveFolderFilters) -> Void
    ) -> SidebarContextMenuEntry {
        .action(.init(
            title: title,
            systemImage: nil,
            state: isEnabled ? .on : .off,
            classification: .stateMutationNonStructural
        ) {
            guard var filters = currentLiveFolderSource()?.githubFilters else {
                return
            }
            mutate(&filters)
            browserContext.liveFolderManager.setGitHubFilters(
                folderId: folder.id,
                filters: filters
            )
        })
    }

    func currentLiveFolderSource() -> SumiLiveFolderSource? {
        browserContext.liveFolderManager.source(for: folder.id)
    }
}
