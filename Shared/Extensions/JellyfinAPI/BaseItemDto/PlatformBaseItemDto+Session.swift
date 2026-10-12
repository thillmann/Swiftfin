import JellyfinAPI

extension BaseItemDto {
    @MainActor
    func getFullItem(userSession: UserSession) async throws -> BaseItemDto {
        let entry = try await userSession.getFullItem(self)
        guard let value = entry.value else { throw ItemStore.StoreError.itemUnavailable }
        return value
    }
}
