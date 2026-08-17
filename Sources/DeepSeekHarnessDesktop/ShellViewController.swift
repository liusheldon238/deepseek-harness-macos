import AppKit
import DeepSeekHarnessCore
import WebKit

@MainActor
final class ShellViewController: NSViewController, WKNavigationDelegate {
    private let runtimeManager = NodeRuntimeManager()
    private let dshManager = DSHProcessManager()
    private let logoView = NSImageView()
    private let statusLabel = NSTextField(labelWithString: "正在准备环境…")
    private let detailLabel = NSTextField(labelWithString: "")
    private let progress = NSProgressIndicator()
    private let retryButton = NSButton(title: "重试", target: nil, action: nil)
    private let webView: WKWebView
    private var started = false
    private var startupTask: Task<Void, Never>?

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

        if let logoURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let image = NSImage(contentsOf: logoURL) {
            logoView.image = image
        }
        logoView.imageScaling = .scaleProportionallyUpOrDown
        logoView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            logoView.widthAnchor.constraint(equalToConstant: 96),
            logoView.heightAnchor.constraint(equalToConstant: 96)
        ])

        let status = NSStackView(views: [logoView, statusLabel, detailLabel, progress, retryButton])
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
        webView.isHidden = true
        statusLabel.stringValue = "正在扫描 Node.js…"
        detailLabel.stringValue = "将优先使用本机兼容环境；缺失时自动下载。"

        startupTask?.cancel()
        startupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let runtime = try await runtimeManager.resolve()
                try Task.checkCancellation()
                statusLabel.stringValue = "正在启动 DeepSeek Harness…"
                detailLabel.stringValue = "Node.js \(runtime.version)（\(runtime.architecture.rawValue)）"
                let url = try await dshManager.start(using: runtime)
                try Task.checkCancellation()
                statusLabel.stringValue = "正在加载 Web UI…"
                webView.load(URLRequest(url: url))
            } catch {
                if error is CancellationError { return }
                showError(error)
            }
        }
    }

    private func showError(_ error: Error) {
        progress.stopAnimation(nil)
        progress.isHidden = true
        retryButton.isHidden = false
        statusLabel.isHidden = false
        detailLabel.isHidden = false
        statusLabel.stringValue = "启动失败"
        let log = dshManager.logFileURL.path
        detailLabel.stringValue = "\(error.localizedDescription)\n日志：\(log)"
    }

    func stopBackend() {
        startupTask?.cancel()
        startupTask = nil
        dshManager.stop()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        progress.stopAnimation(nil)
        progress.isHidden = true
        statusLabel.isHidden = true
        detailLabel.isHidden = true
        retryButton.isHidden = true
        webView.isHidden = false
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showError(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showError(error)
    }
}
