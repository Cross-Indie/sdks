#if canImport(SwiftUI) && canImport(UIKit) && !os(watchOS)
import SwiftUI
import UIKit

/// CrossIndie cross-promotion banner for SwiftUI.
///
///     CrossIndieBanner(appId: "YOUR_APP_ID")
///         .onImpression { ad in print("counted", ad.name) }
///
/// Wraps `CrossIndieBannerView`, so behaviour is identical: zero height until
/// an ad loads, impressions only while >= 50 % on screen for the minimum
/// display time, rotation after `refreshSeconds` (0 = never).
@available(iOS 13.0, *)
public struct CrossIndieBanner: UIViewRepresentable {
    public var appId: String
    public var category: String
    public var format: CrossIndieFormat
    public var apiBase: String?
    public var refreshSeconds: Int
    public var video: Bool
    public var closeable: Bool
    public var country: String?

    var onLoad: ((CrossIndieAd) -> Void)?
    var onImpressionHandler: ((CrossIndieAd) -> Void)?
    var onClickHandler: ((CrossIndieAd) -> Void)?
    var onNoFillHandler: (() -> Void)?
    var onCloseHandler: (() -> Void)?

    public init(appId: String, category: String = "game", format: CrossIndieFormat = .mobile,
                apiBase: String? = nil, refreshSeconds: Int = BannerState.defaultRefreshSeconds,
                video: Bool = true, closeable: Bool = false, country: String? = nil) {
        self.appId = appId
        self.category = category
        self.format = format
        self.apiBase = apiBase
        self.refreshSeconds = refreshSeconds
        self.video = video
        self.closeable = closeable
        self.country = country
    }

    public func onLoad(_ action: @escaping (CrossIndieAd) -> Void) -> Self { var c = self; c.onLoad = action; return c }
    public func onImpression(_ action: @escaping (CrossIndieAd) -> Void) -> Self { var c = self; c.onImpressionHandler = action; return c }
    public func onClick(_ action: @escaping (CrossIndieAd) -> Void) -> Self { var c = self; c.onClickHandler = action; return c }
    public func onNoFill(_ action: @escaping () -> Void) -> Self { var c = self; c.onNoFillHandler = action; return c }
    public func onClose(_ action: @escaping () -> Void) -> Self { var c = self; c.onCloseHandler = action; return c }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeUIView(context: Context) -> CrossIndieBannerView {
        let view = CrossIndieBannerView(frame: .zero)
        view.delegate = context.coordinator
        return view
    }

    public func updateUIView(_ view: CrossIndieBannerView, context: Context) {
        context.coordinator.parent = self
        view.configure(appId: appId, category: category, format: format, apiBase: apiBase,
                       refreshSeconds: refreshSeconds, videoEnabled: video, closeable: closeable,
                       country: country)
    }

    @available(iOS 16.0, *)
    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: CrossIndieBannerView, context: Context) -> CGSize? {
        let w = proposal.width ?? CGFloat(uiView.format.maxWidth)
        return CGSize(width: w, height: uiView.contentHeight(forWidth: w))
    }

    public final class Coordinator: CrossIndieBannerDelegate {
        var parent: CrossIndieBanner?

        public func bannerDidLoad(_ banner: CrossIndieBannerView, ad: CrossIndieAd) { parent?.onLoad?(ad) }
        public func bannerDidNotFill(_ banner: CrossIndieBannerView) { parent?.onNoFillHandler?() }
        public func bannerDidRecordImpression(_ banner: CrossIndieBannerView, ad: CrossIndieAd) { parent?.onImpressionHandler?(ad) }
        public func bannerWasClicked(_ banner: CrossIndieBannerView, ad: CrossIndieAd) { parent?.onClickHandler?(ad) }
        public func bannerWasClosed(_ banner: CrossIndieBannerView) { parent?.onCloseHandler?() }
    }
}
#endif
