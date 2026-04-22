extension Void {
    /// Possible errors from internal Void calls.
    enum Error: Swift.Error, CustomLocalizedStringResourceConvertible {
        case apiFailed

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .apiFailed: return "libvoid API call failed"
            }
        }
    }
}
