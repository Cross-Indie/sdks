import Foundation
#if canImport(Network)
import Network
#endif

/// Global SDK settings. All optional - a banner only needs its app id.
public enum CrossIndie {
    public static let version = "1.2.0"
    public static let defaultAPIBase = "https://api.crossindie.com"

    /// Default API base for every banner that doesn't set its own.
    public static var apiBase: String = defaultAPIBase

    /// Print swallowed network errors to the console. Off by default.
    public static var debugLogging = false

    /// Open ad links in an in-app SFSafariViewController instead of the
    /// external browser. App Store links always open the App Store app.
    public static var opensLinksInApp = false

    static func log(_ message: String) {
        if debugLogging { NSLog("[CrossIndie] %@", message) }
    }
}

/// Banner layouts, the same set as the web SDK. Sizes are maximum widths /
/// fixed heights in points; the banner shrinks to the available width.
public enum CrossIndieFormat: String, CaseIterable {
    /// 320x50 strip: icon + headline. The classic in-app banner (default).
    case mobile
    /// 320 wide, 16:9 artwork with headline + description below.
    case card
    /// 300x250 medium rectangle.
    case rectangle
    /// 728x90 leaderboard (iPad).
    case leaderboard
    /// Text only: headline + description.
    case text

    var maxWidth: Double {
        switch self {
        case .mobile, .card, .text: return 320
        case .rectangle: return 300
        case .leaderboard: return 728
        }
    }
    /// 0 = height follows the content.
    var fixedHeight: Double {
        switch self {
        case .mobile: return 50
        case .rectangle: return 250
        case .leaderboard: return 90
        case .card, .text: return 0
        }
    }
    var horizontal: Bool { self == .mobile || self == .leaderboard }
    var hasMedia: Bool { self != .text }
    var mediaWidth: Double { self == .leaderboard ? 150 : 50 }      // horizontal formats
    var mediaHeight: Double { self == .rectangle ? 150 : 0 }        // vertical; 0 = 16:9
    var showsDescription: Bool { self != .mobile }
    var showsBadge: Bool { self != .mobile }

    public init(apiName: String?) {
        self = CrossIndieFormat(rawValue: (apiName ?? "").lowercased()) ?? .mobile
    }
}

/// Watches the network so video banners are only requested on unmetered
/// connections without Low Data Mode (the viewer's data is sacred).
final class NetworkWatch {
    static let shared = NetworkWatch()
    private let lock = NSLock()
    private var cheap = false
    #if canImport(Network)
    private var monitor: AnyObject?
    #endif

    private init() {
        #if canImport(Network)
        if #available(iOS 13.0, macOS 10.15, *) {
            let m = NWPathMonitor()
            m.pathUpdateHandler = { [weak self] path in
                let ok = path.status == .satisfied && !path.isExpensive && !path.isConstrained
                self?.lock.lock()
                self?.cheap = ok
                self?.lock.unlock()
            }
            m.start(queue: DispatchQueue(label: "com.crossindie.network", qos: .utility))
            monitor = m
        }
        #endif
    }

    var canStreamVideo: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cheap
    }
}
