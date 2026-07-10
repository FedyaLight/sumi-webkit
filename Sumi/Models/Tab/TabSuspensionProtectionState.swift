struct TabSuspensionProtectionState {
    var pageVeto: TabPageSuspensionVeto = .none
    var hasPictureInPictureVideo = false
    var isPDFDocument = false

    mutating func resetForNewPage() {
        pageVeto = .none
        hasPictureInPictureVideo = false
        isPDFDocument = false
    }
}
