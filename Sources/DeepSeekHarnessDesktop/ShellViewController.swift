import AppKit
import DeepSeekHarnessCore
import WebKit

@MainActor
final class ShellViewController: NSViewController, WKNavigationDelegate {
    private let dshManager = DSHProcessManager()
    private lazy var startupManager = SelfHealingStartup(processManager: dshManager)
    private let logoView = NSImageView()
    private let statusLabel = NSTextField(labelWithString: "正在准备环境…")
    private let detailLabel = NSTextField(labelWithString: "")
    private let errorLogView = NSTextView()
    private let errorLogScrollView = NSScrollView()
    private let logToggleButton = NSButton(title: "展开启动日志", target: nil, action: nil)
    private let copyLogButton = NSButton(title: "复制日志", target: nil, action: nil)
    private let progress = NSProgressIndicator()
    private let retryButton = NSButton(title: "重试", target: nil, action: nil)
    private let webView: WKWebView
    private var started = false
    private var startupTask: Task<Void, Never>?
    private var logTimer: Timer?
    private var logExpanded = false

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.isHidden = true
        logoView.isHidden = false

        if let logoURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let image = NSImage(contentsOf: logoURL) {
            logoView.image = image
        }
        logoView.imageScaling = .scaleProportionallyUpOrDown
        logoView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            logoView.widthAnchor.constraint(equalToConstant: 96),
            logoView.heightAnchor.constraint(equalToConstant: 96)
        ])

        errorLogView.isEditable = false
        errorLogView.isSelectable = true
        errorLogView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        errorLogView.textColor = .systemRed
        errorLogView.backgroundColor = NSColor.systemRed.withAlphaComponent(0.06)
        errorLogView.textContainerInset = NSSize(width: 10, height: 8)
        errorLogScrollView.documentView = errorLogView
        errorLogScrollView.hasVerticalScroller = true
        errorLogScrollView.hasHorizontalScroller = true
        errorLogScrollView.borderType = .bezelBorder
        errorLogScrollView.translatesAutoresizingMaskIntoConstraints = false
        errorLogScrollView.isHidden = true
        errorLogScrollView.heightAnchor.constraint(equalToConstant: 150).isActive = true

        logToggleButton.bezelStyle = .inline
        logToggleButton.isBordered = false
        logToggleButton.contentTintColor = .secondaryLabelColor
        logToggleButton.target = self
        logToggleButton.action = #selector(toggleLogs)
        copyLogButton.bezelStyle = .inline
        copyLogButton.target = self
        copyLogButton.action = #selector(copyLogs)
        let logActions = NSStackView(views: [logToggleButton, copyLogButton])
        logActions.spacing = 10
        logActions.isHidden = true

        let status = NSStackView(views: [logoView, statusLabel, detailLabel, progress, retryButton, logActions, errorLogScrollView])
        status.orientation = .vertical
        status.alignment = .centerX
        status.spacing = 12
        status.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.alignment = .center
        detailLabel.maximumNumberOfLines = 3
        progress.style = .spinning
        progress.controlSize = .regular
        progress.startAnimation(nil)
        retryButton.isHidden = true
        errorLogScrollView.isHidden = true
        logToggleButton.isHidden = true
        copyLogButton.isHidden = true
        retryButton.target = self
        retryButton.action = #selector(retry)

        root.addSubview(webView)
        root.addSubview(status)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            webView.topAnchor.constraint(equalTo: root.topAnchor),
            webView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            status.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            status.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            status.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 40),
            status.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -40)
        ])
        view = root
        startBackend()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if !started { startBackend() }
    }

    @objc private func retry() {
        startBackend()
    }

    private func startBackend() {
        started = true
        retryButton.isHidden = true
        progress.isHidden = false
        progress.startAnimation(nil)
        webView.stopLoading()
        webView.isHidden = true
        logoView.isHidden = false
        statusLabel.isHidden = false
        detailLabel.isHidden = false
        errorLogScrollView.isHidden = true
        logToggleButton.isHidden = false
        copyLogButton.isHidden = false
        logExpanded = false
        updateLogVisibility()
        errorLogView.string = ""
        statusLabel.stringValue = "正在扫描 Node.js…"
        detailLabel.stringValue = "将优先使用本机兼容环境；缺失时自动下载。"

        startupTask?.cancel()
        logTimer?.invalidate()
        logTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshLog() }
        }
        startupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let (url, report) = try await startupManager.start { [weak self] phase, detail in
                    guard let self else { return }
                    statusLabel.stringValue = phase.rawValue
                    detailLabel.stringValue = detail
                }
                try Task.checkCancellation()
                detailLabel.stringValue = "Node.js \(report.runtime.version)（\(report.runtime.architecture.rawValue)）"
                statusLabel.stringValue = "正在加载 Web UI…"
                // DSH has already passed its HTTP health check. Reveal the
                // WebView immediately so the launch logo cannot remain over
                // the page while secondary assets finish loading.
                progress.stopAnimation(nil)
                progress.isHidden = true
                logoView.isHidden = true
                statusLabel.isHidden = true
                detailLabel.isHidden = true
                retryButton.isHidden = true
                errorLogScrollView.isHidden = true
                logToggleButton.isHidden = true
                copyLogButton.isHidden = true
                logTimer?.invalidate()
                logTimer = nil
                webView.isHidden = false
                webView.load(URLRequest(url: url))
            } catch {
                if error is CancellationError { return }
                showError(error)
            }
        }
    }

    private func showError(_ error: Error) {
        webView.stopLoading()
        webView.isHidden = true
        logoView.isHidden = false
        progress.stopAnimation(nil)
        progress.isHidden = true
        retryButton.isHidden = false
        statusLabel.isHidden = false
        detailLabel.isHidden = false
        statusLabel.stringValue = "启动失败"
        detailLabel.stringValue = error.localizedDescription
        let log = dshManager.latestLog.trimmingCharacters(in: .whitespacesAndNewlines)
        errorLogView.string = log.isEmpty ? "暂无后台输出。请点击“重试”再次启动。" : log
        logToggleButton.isHidden = false
        copyLogButton.isHidden = false
        logExpanded = true
        updateLogVisibility()
        logTimer?.invalidate()
        logTimer = nil
    }

    @objc private func toggleLogs() {
        logExpanded.toggle()
        updateLogVisibility()
    }

    @objc private func copyLogs() {
        refreshLog()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(errorLogView.string, forType: .string)
        copyLogButton.title = "已复制"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.copyLogButton.title = "复制日志" }
    }

    private func refreshLog() {
        let log = dshManager.latestLog
        guard !log.isEmpty else { return }
        errorLogView.string = log
        errorLogView.scrollToEndOfDocument(nil)
    }

    private func updateLogVisibility() {
        errorLogScrollView.isHidden = !logExpanded
        logToggleButton.title = logExpanded ? "收起启动日志" : "展开启动日志"
    }

    func stopBackend() {
        startupTask?.cancel()
        startupTask = nil
        dshManager.stop()
        logTimer?.invalidate()
        logTimer = nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        if url.scheme == "about" {
            decisionHandler(.allow)
            return
        }
        guard url.host == "127.0.0.1" else {
            if let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        progress.stopAnimation(nil)
        progress.isHidden = true
        statusLabel.isHidden = true
        detailLabel.isHidden = true
        retryButton.isHidden = true
        errorLogScrollView.isHidden = true
        webView.isHidden = false
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showError(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showError(error)
    }
}
