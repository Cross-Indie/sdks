#if canImport(UIKit) && !os(watchOS)
import AVFoundation
import ImageIO
import SafariServices
import UIKit

/// Callbacks for a banner slot. All methods are optional and run on the main thread.
public protocol CrossIndieBannerDelegate: AnyObject {
    func bannerDidLoad(_ banner: CrossIndieBannerView, ad: CrossIndieAd)
    /// The network had no eligible ad right now; the slot stays collapsed and retries later.
    func bannerDidNotFill(_ banner: CrossIndieBannerView)
    func bannerDidFail(_ banner: CrossIndieBannerView, reason: String)
    /// A viewable impression was reported (your app earns credits for it).
    func bannerDidRecordImpression(_ banner: CrossIndieBannerView, ad: CrossIndieAd)
    func bannerWasClicked(_ banner: CrossIndieBannerView, ad: CrossIndieAd)
    /// The viewer dismissed the slot with the close button.
    func bannerWasClosed(_ banner: CrossIndieBannerView)
}

public extension CrossIndieBannerDelegate {
    func bannerDidLoad(_ banner: CrossIndieBannerView, ad: CrossIndieAd) {}
    func bannerDidNotFill(_ banner: CrossIndieBannerView) {}
    func bannerDidFail(_ banner: CrossIndieBannerView, reason: String) {}
    func bannerDidRecordImpression(_ banner: CrossIndieBannerView, ad: CrossIndieAd) {}
    func bannerWasClicked(_ banner: CrossIndieBannerView, ad: CrossIndieAd) {}
    func bannerWasClosed(_ banner: CrossIndieBannerView) {}
}

/// CrossIndie cross-promotion banner (UIKit).
///
///     let banner = CrossIndieBannerView(appId: "YOUR_APP_ID")
///     view.addSubview(banner)   // Auto Layout: pin leading/trailing/top; height is intrinsic
///
/// The slot has zero height until an ad is available. An impression is
/// reported only after the banner has been continuously >= 50 % on screen,
/// with the app active, for the server's minimum display time; hidden slots
/// make no network requests after their first fetch.
open class CrossIndieBannerView: UIView {

    // MARK: Config

    /// Your app id from Dashboard > Integration.
    public var appId: String = "" { didSet { if appId != oldValue { changed() } } }
    /// Category pool to request: game | mobile_app | web_tool | saas.
    public var category: String = "game" { didSet { if category != oldValue { changed() } } }
    public var format: CrossIndieFormat = .mobile {
        didSet { if format != oldValue { applyFormat(); changed() } }
    }
    /// Per-banner API base; nil uses `CrossIndie.apiBase`.
    public var apiBase: String? { didSet { if apiBase != oldValue { changed() } } }
    /// Rotate to a new ad this long after an impression (0 = never, min 15).
    public var refreshSeconds: Int = BannerState.defaultRefreshSeconds {
        didSet { state.setRefreshSeconds(refreshSeconds) }
    }
    /// Allow muted video creatives (requested only on unmetered networks).
    public var videoEnabled = true { didSet { if videoEnabled != oldValue { changed() } } }
    /// Show a small close button that hides the slot.
    public var closeable = false { didSet { closeButton.isHidden = !closeable } }
    /// Optional viewer country (ISO-3166 alpha-2) for region targeting.
    public var country: String? { didSet { if country != oldValue { changed() } } }

    public weak var delegate: CrossIndieBannerDelegate?

    // MARK: State

    private let state = BannerState()
    private var timer: Timer?
    private var configGen = 0
    private var renderGen = 0
    private var collapsed = true
    private var dismissed = false
    private var batching = false
    private var reloadPending = false
    private var pendingVideoURL = ""
    private var player: AVQueuePlayer?
    private var looper: AnyObject?
    private var playerLayer: AVPlayerLayer?
    private var lastWidth: CGFloat = -1

    // MARK: Views

    private let card = UIView()
    private let tapArea = UIControl()
    private let mediaView = UIView()
    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let descLabel = UILabel()
    private let badgeButton = UIButton(type: .custom)
    private let closeButton = UIButton(type: .custom)

    // MARK: Init

    public convenience init(appId: String, category: String = "game", format: CrossIndieFormat = .mobile) {
        self.init(frame: .zero)
        configure(appId: appId, category: category, format: format)
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    /// Interface Builder: set these as User Defined Runtime Attributes.
    @IBInspectable public var ibAppId: String {
        get { appId }
        set { appId = newValue }
    }
    @IBInspectable public var ibFormat: String {
        get { format.rawValue }
        set { format = CrossIndieFormat(apiName: newValue) }
    }
    @IBInspectable public var ibCategory: String {
        get { category }
        set { category = newValue }
    }

    deinit {
        timer?.invalidate()
    }

    /// Set everything at once (one reload). Used by the SwiftUI wrapper.
    public func configure(appId: String, category: String = "game", format: CrossIndieFormat = .mobile,
                          apiBase: String? = nil, refreshSeconds: Int = BannerState.defaultRefreshSeconds,
                          videoEnabled: Bool = true, closeable: Bool = false, country: String? = nil) {
        batching = true
        self.appId = appId.trimmingCharacters(in: .whitespaces)
        self.category = category
        self.format = format
        self.apiBase = apiBase
        self.videoEnabled = videoEnabled
        self.country = country
        self.refreshSeconds = refreshSeconds
        self.closeable = closeable
        batching = false
        if reloadPending { reload() }
    }

    private func changed() {
        if batching { reloadPending = true } else { reload() }
    }

    /// Drop the current ad and fetch a new one.
    public func reload() {
        reloadPending = false
        configGen += 1
        renderGen += 1
        state.reset()
        dismissed = false
        releaseVideo()
        pendingVideoURL = ""
        setCollapsed(true)
        if window != nil { tick() }
    }

    // MARK: Lifecycle

    open override func didMoveToWindow() {
        super.didMoveToWindow()
        timer?.invalidate()
        timer = nil
        if window != nil {
            let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(t, forMode: .common) // keep ticking while scrolling
            timer = t
            tick()
        } else {
            releaseVideo() // re-created lazily (pendingVideoURL is kept) if the slot comes back
        }
    }

    private static func nowMs() -> Int64 { Int64(ProcessInfo.processInfo.systemUptime * 1000) }

    private func tick() {
        if appId.isEmpty || dismissed { return }
        let now = Self.nowMs()
        let onScreen = isOnScreen
        let viewable = onScreen && isViewable
        if state.shouldFetch(now: now, onScreen: onScreen, viewable: viewable) { fetch() }
        if state.tick(now: now, viewable: viewable), let ad = state.ad {
            AdClient.track(apiBase: resolvedBase, token: ad.trackingToken, eventType: "impression")
            delegate?.bannerDidRecordImpression(self, ad: ad)
        }
        // Video: lazy-load only once actually viewable; pause when not.
        if viewable && player == nil && !pendingVideoURL.isEmpty { startVideo(pendingVideoURL) }
        if let p = player {
            if viewable { if p.rate == 0 { p.play() } } else if p.rate != 0 { p.pause() }
        }
    }

    private var isOnScreen: Bool {
        guard window != nil, !dismissed, !isHidden, alpha > 0.01 else { return false }
        var v = superview
        while let s = v {
            if s.isHidden || s.alpha <= 0.01 { return false }
            v = s.superview
        }
        return true
    }

    private var isViewable: Bool {
        guard let window = window, !collapsed, UIApplication.shared.applicationState == .active else { return false }
        let size = card.bounds.size
        guard size.width > 0, size.height > 0 else { return false }
        var rect = card.convert(card.bounds, to: window)
        var v: UIView? = card.superview
        while let s = v {
            if s.clipsToBounds { rect = rect.intersection(s.convert(s.bounds, to: window)) }
            v = s.superview
        }
        rect = rect.intersection(window.bounds)
        if rect.isNull || rect.isEmpty { return false }
        return Visibility.isViewable(visibleWidth: Double(rect.width), visibleHeight: Double(rect.height),
                                     width: Double(size.width), height: Double(size.height))
    }

    // MARK: Networking

    private var resolvedBase: String {
        let b = (apiBase?.isEmpty == false ? apiBase! : CrossIndie.apiBase)
        return CrossIndieAd.normalizeBase(b)
    }

    private func fetch() {
        let gen = configGen
        let base = resolvedBase
        let url = AdRequests.fetchURL(
            apiBase: base, appId: appId, category: category,
            bundleId: Bundle.main.bundleIdentifier ?? "",
            lang: Locale.preferredLanguages.first, country: country,
            video: videoEnabled && format.hasMedia && NetworkWatch.shared.canStreamVideo
        )
        state.onFetchStarted()
        AdClient.fetchAd(url: url, apiBase: base) { [weak self] result in
            guard let self = self, gen == self.configGen else { return }
            let hadAd = self.state.ad != nil
            self.state.onFetchResult(now: Self.nowMs(), result)
            switch result {
            case .loaded(let ad): self.render(ad)
            case .noFill: if !hadAd { self.delegate?.bannerDidNotFill(self) }
            case .error: self.delegate?.bannerDidFail(self, reason: "ad fetch failed")
            }
        }
    }

    // MARK: Rendering

    private func render(_ ad: CrossIndieAd) {
        renderGen += 1
        let gen = renderGen
        releaseVideo()
        pendingVideoURL = ""
        let apply: (UIImage?) -> Void = { [weak self] image in
            guard let self = self, gen == self.renderGen else { return }
            self.imageView.image = image
            self.titleLabel.text = ad.name
            self.descLabel.text = ad.description
            self.descLabel.isHidden = !(self.format.showsDescription && !ad.description.isEmpty)
            self.tapArea.accessibilityLabel = ad.name
            if self.format.hasMedia { self.pendingVideoURL = ad.videoURL }
            self.setCollapsed(false)
            self.state.onRendered()
            self.delegate?.bannerDidLoad(self, ad: ad)
        }
        if format.hasMedia && !ad.bannerImageURL.isEmpty {
            let maxPx = max(Double(format.maxWidth), 180) * Double(UIScreen.main.scale)
            AdClient.loadImageData(url: ad.bannerImageURL) { data in
                apply(data.flatMap { Self.downsample($0, maxPixel: maxPx) })
            }
        } else {
            apply(nil)
        }
    }

    /// Decode at roughly display size (big artwork never balloons memory).
    private static func downsample(_ data: Data, maxPixel: Double) -> UIImage? {
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, opts) else { return nil }
        let thumbOpts = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts) else { return nil }
        return UIImage(cgImage: cg)
    }

    @objc private func bannerTapped() {
        guard let ad = state.ad else { return }
        if state.consumeClick(now: Self.nowMs()) {
            AdClient.track(apiBase: resolvedBase, token: ad.trackingToken, eventType: "click")
        }
        open(ad.targetURL)
        delegate?.bannerWasClicked(self, ad: ad)
    }

    @objc private func badgeTapped() {
        open("https://crossindie.com")
    }

    @objc private func closeTapped() {
        dismissed = true
        renderGen += 1
        releaseVideo()
        pendingVideoURL = ""
        setCollapsed(true)
        delegate?.bannerWasClosed(self)
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        let host = url.host?.lowercased() ?? ""
        let isStore = host.hasSuffix("apps.apple.com") || host.hasSuffix("itunes.apple.com")
        if CrossIndie.opensLinksInApp, !isStore, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
           let presenter = nearestViewController() {
            let safari = SFSafariViewController(url: url)
            presenter.present(safari, animated: true)
            return
        }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    private func nearestViewController() -> UIViewController? {
        var r: UIResponder? = self
        while let cur = r {
            if let vc = cur as? UIViewController {
                var top = vc
                while let p = top.presentedViewController { top = p }
                return top
            }
            r = cur.next
        }
        return nil
    }

    // MARK: Video

    private func startVideo(_ urlString: String) {
        guard let url = URL(string: urlString), format.hasMedia else {
            pendingVideoURL = ""
            return
        }
        let item = AVPlayerItem(url: url)
        let p = AVQueuePlayer()
        p.isMuted = true
        p.preventsDisplaySleepDuringVideoPlayback = false
        p.actionAtItemEnd = .advance
        looper = AVPlayerLooper(player: p, templateItem: item)
        let layer = AVPlayerLayer(player: p)
        layer.videoGravity = .resizeAspectFill
        layer.frame = mediaView.bounds
        layer.opacity = 0 // keep the poster until the first frame
        mediaView.layer.addSublayer(layer)
        player = p
        playerLayer = layer
        layer.addObserver(self, forKeyPath: "readyForDisplay", options: [.new], context: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(videoFailed(_:)),
                                               name: .AVPlayerItemFailedToPlayToEndTime, object: nil)
        p.play()
    }

    open override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                                    change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "readyForDisplay", let layer = object as? AVPlayerLayer, layer === playerLayer {
            DispatchQueue.main.async { [weak self] in
                if layer.isReadyForDisplay, layer === self?.playerLayer { layer.opacity = 1 }
            }
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

    @objc private func videoFailed(_ note: Notification) {
        guard let item = note.object as? AVPlayerItem, let p = player, p.items().contains(item) else { return }
        CrossIndie.log("video playback failed")
        DispatchQueue.main.async { [weak self] in
            self?.releaseVideo()
            self?.pendingVideoURL = "" // fall back to the static poster for this ad
        }
    }

    private func releaseVideo() {
        guard let p = player else { return }
        p.pause()
        p.removeAllItems()
        if let l = playerLayer {
            l.removeObserver(self, forKeyPath: "readyForDisplay")
            l.removeFromSuperlayer()
        }
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: nil)
        player = nil
        looper = nil
        playerLayer = nil
    }

    // MARK: Layout

    private func setUp() {
        backgroundColor = .clear
        clipsToBounds = false
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)

        card.backgroundColor = UIColor(red: 0x14 / 255, green: 0x12 / 255, blue: 0x10 / 255, alpha: 1)
        card.layer.borderColor = UIColor(red: 0x27 / 255, green: 0x27 / 255, blue: 0x2a / 255, alpha: 1).cgColor
        card.layer.borderWidth = 1
        card.clipsToBounds = true
        card.isHidden = true
        addSubview(card)

        tapArea.addTarget(self, action: #selector(bannerTapped), for: .touchUpInside)
        tapArea.isAccessibilityElement = true
        tapArea.accessibilityTraits = .link
        card.addSubview(tapArea)

        mediaView.backgroundColor = UIColor(red: 0x0a / 255, green: 0x0a / 255, blue: 0x0c / 255, alpha: 1)
        mediaView.clipsToBounds = true
        mediaView.isUserInteractionEnabled = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        mediaView.addSubview(imageView)
        tapArea.addSubview(mediaView)

        titleLabel.textColor = UIColor(red: 0xf5 / 255, green: 0xf3 / 255, blue: 0xef / 255, alpha: 1)
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.isUserInteractionEnabled = false
        descLabel.textColor = UIColor(red: 0xa8 / 255, green: 0xa2 / 255, blue: 0x9a / 255, alpha: 1)
        descLabel.font = .systemFont(ofSize: 12)
        descLabel.lineBreakMode = .byTruncatingTail
        descLabel.isUserInteractionEnabled = false
        tapArea.addSubview(titleLabel)
        tapArea.addSubview(descLabel)

        // Ad label, always visible so the banner is never mistaken for app content.
        // Bigger formats carry the full attribution, its own link to crossindie.com
        // (never tracked as an ad click); the 320x50 strip gets a compact "AD" chip.
        // Title, font and tap target are set per format in applyFormat().
        badgeButton.accessibilityLabel = "Advertisement"
        badgeButton.setTitleColor(UIColor(red: 0xd6 / 255, green: 0xd3 / 255, blue: 0xcd / 255, alpha: 1), for: .normal)
        badgeButton.backgroundColor = UIColor(red: 10 / 255, green: 10 / 255, blue: 12 / 255, alpha: 0.72)
        badgeButton.addTarget(self, action: #selector(badgeTapped), for: .touchUpInside)
        card.addSubview(badgeButton)

        // Small universal close button; dismissing before the dwell time records nothing.
        closeButton.setTitle("\u{00D7}", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 14)
        closeButton.setTitleColor(UIColor(red: 0xf5 / 255, green: 0xf3 / 255, blue: 0xef / 255, alpha: 1), for: .normal)
        closeButton.backgroundColor = UIColor(red: 10 / 255, green: 10 / 255, blue: 12 / 255, alpha: 0.55)
        closeButton.layer.cornerRadius = 9
        closeButton.accessibilityLabel = "Close"
        closeButton.isHidden = true
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        card.addSubview(closeButton)

        applyFormat()
    }

    private func applyFormat() {
        let small = format.fixedHeight > 0 && format.fixedHeight <= 50
        card.layer.cornerRadius = small ? 8 : 12
        titleLabel.font = .systemFont(ofSize: small ? 13 : 14, weight: .semibold)
        descLabel.numberOfLines = format.horizontal ? 1 : 2
        mediaView.isHidden = !format.hasMedia
        let full = format.showsBadge
        badgeButton.setTitle(full ? "AD \u{00B7} PROMOTED WITH CROSSINDIE" : "AD", for: .normal)
        badgeButton.titleLabel?.font = .systemFont(ofSize: full ? 9 : 8, weight: .medium)
        badgeButton.layer.cornerRadius = full ? 6 : 4
        badgeButton.contentEdgeInsets = full
            ? UIEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
            : UIEdgeInsets(top: 1, left: 4, bottom: 1, right: 4)
        badgeButton.isUserInteractionEnabled = full
        badgeButton.isHidden = false
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    private func setCollapsed(_ c: Bool) {
        collapsed = c
        card.isHidden = c
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        superview?.setNeedsLayout()
    }

    private var textPadding: UIEdgeInsets {
        format.fixedHeight > 0 && format.fixedHeight <= 50
            ? UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 26)
            : UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
    }

    private func mediaHeight(forCardWidth w: CGFloat) -> CGFloat {
        guard format.hasMedia, !format.horizontal else { return 0 }
        return format.mediaHeight > 0 ? CGFloat(format.mediaHeight) : (w * 9 / 16).rounded()
    }

    private func textHeight(forCardWidth w: CGFloat) -> CGFloat {
        let pad = textPadding
        let tw = max(w - pad.left - pad.right, 0)
        var h = pad.top + titleLabel.font.lineHeight.rounded(.up)
        if !descLabel.isHidden {
            h += 2 + descLabel.sizeThatFits(CGSize(width: tw, height: .greatestFiniteMagnitude)).height
        }
        if format.showsBadge && !format.horizontal { h += 14 }
        return h + pad.bottom
    }

    private func cardWidth(for width: CGFloat) -> CGFloat {
        min(width > 0 ? width : CGFloat(format.maxWidth), CGFloat(format.maxWidth))
    }

    /// Height of the slot for a given width (0 while collapsed).
    public func contentHeight(forWidth width: CGFloat) -> CGFloat {
        if collapsed { return 0 }
        if format.fixedHeight > 0 { return CGFloat(format.fixedHeight) }
        let w = cardWidth(for: width)
        return mediaHeight(forCardWidth: w) + textHeight(forCardWidth: w)
    }

    open override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: contentHeight(forWidth: bounds.width))
    }

    open override func sizeThatFits(_ size: CGSize) -> CGSize {
        let w = size.width > 0 ? size.width : CGFloat(format.maxWidth)
        return CGSize(width: collapsed ? 0 : min(w, CGFloat(format.maxWidth)), height: contentHeight(forWidth: w))
    }

    open override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width != lastWidth {
            lastWidth = bounds.width
            if format.fixedHeight == 0 { invalidateIntrinsicContentSize() }
        }
        let w = cardWidth(for: bounds.width)
        let h = contentHeight(forWidth: bounds.width)
        card.frame = CGRect(x: ((bounds.width - w) / 2).rounded(), y: 0, width: w, height: h)
        tapArea.frame = card.bounds

        let pad = textPadding
        var textFrame: CGRect
        if !format.hasMedia {
            mediaView.frame = .zero
            textFrame = card.bounds
        } else if format.horizontal {
            let mw = CGFloat(format.mediaWidth)
            mediaView.frame = CGRect(x: 0, y: 0, width: mw, height: h)
            textFrame = CGRect(x: mw, y: 0, width: max(w - mw, 0), height: h)
        } else {
            let mh = mediaHeight(forCardWidth: w)
            mediaView.frame = CGRect(x: 0, y: 0, width: w, height: mh)
            textFrame = CGRect(x: 0, y: mh, width: w, height: max(h - mh, 0))
        }
        imageView.frame = mediaView.bounds
        playerLayer?.frame = mediaView.bounds

        // Title (+ description) block, vertically centred in the text area.
        let inner = textFrame.inset(by: pad)
        let titleH = titleLabel.font.lineHeight.rounded(.up)
        var descH: CGFloat = 0
        if !descLabel.isHidden {
            descH = min(descLabel.sizeThatFits(CGSize(width: inner.width, height: .greatestFiniteMagnitude)).height,
                        max(inner.height - titleH - 2, 0))
        }
        let blockH = titleH + (descH > 0 ? 2 + descH : 0)
        let top = format.horizontal ? inner.minY + max((inner.height - blockH) / 2, 0) : inner.minY
        titleLabel.frame = CGRect(x: inner.minX, y: top, width: inner.width, height: titleH)
        descLabel.frame = CGRect(x: inner.minX, y: top + titleH + 2, width: inner.width, height: descH)

        let bs = badgeButton.sizeThatFits(CGSize(width: w, height: 20))
        let bm: CGFloat = format.showsBadge ? 6 : 4
        badgeButton.frame = CGRect(x: w - bs.width - bm, y: h - bs.height - bm, width: bs.width, height: bs.height)
        closeButton.frame = CGRect(x: w - 18 - 5, y: 5, width: 18, height: 18)
        card.bringSubviewToFront(badgeButton)
        card.bringSubviewToFront(closeButton)
    }
}
#endif
