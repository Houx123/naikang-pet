import SwiftUI
import WebKit

@MainActor
final class BrowserUsageController: NSObject, ObservableObject {
    @Published var pageStatus = "请在 OpenAI 页面完成登录"
    @Published var isLoading = false
    @Published var canCapture = false

    weak var webView: WKWebView?
    var onCapture: ((String) -> BrowserUsageResult)?
    private var autoCaptureTask: Task<Void, Never>?
    private var captureInProgress = false
    private var lastAutomaticResult: BrowserUsageResult?

    func openUsagePage() {
        guard let url = URL(string: "https://chatgpt.com/settings/usage") else { return }
        webView?.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
    }

    func reload() {
        webView?.reload()
    }

    func captureVisibleUsage(silently: Bool = false) {
        guard let webView, isChatGPTPage(webView.url) else {
            if !silently { pageStatus = "请先登录并打开 ChatGPT 用量面板" }
            return
        }
        guard !captureInProgress else { return }
        captureInProgress = true
        if !silently { pageStatus = "正在读取页面可见额度…" }
        webView.evaluateJavaScript("document.body ? document.body.innerText : ''") { [weak self] value, error in
            Task { @MainActor in
                guard let self else { return }
                self.captureInProgress = false
                guard error == nil, let text = value as? String, !text.isEmpty else {
                    if !silently { self.pageStatus = "无法读取页面，请刷新后重试" }
                    return
                }
                let parsed = BrowserUsageParser.parse(text)
                guard parsed.primaryRemaining != nil || parsed.secondaryRemaining != nil else {
                    if !silently { self.pageStatus = "未找到额度，请确认页面已完全加载" }
                    return
                }
                if silently, parsed == self.lastAutomaticResult { return }
                self.lastAutomaticResult = parsed
                let result = self.onCapture?(text) ?? BrowserUsageResult()
                if result.primaryRemaining != nil || result.secondaryRemaining != nil {
                    self.pageStatus = "额度已自动更新"
                } else {
                    self.pageStatus = "未找到额度，请确认页面已完全加载"
                }
            }
        }
    }

    func startAutoCapture() {
        guard isChatGPTPage(webView?.url), autoCaptureTask == nil else { return }
        autoCaptureTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard let self, !Task.isCancelled else { return }
                self.captureVisibleUsage(silently: true)
            }
        }
    }

    func stopAutoCapture() {
        autoCaptureTask?.cancel()
        autoCaptureTask = nil
    }

    fileprivate func update(for url: URL?) {
        canCapture = isChatGPTPage(url)
        if isChatGPTPage(url) {
            pageStatus = "打开“设置 → 用量”后即可读取额度"
        } else {
            stopAutoCapture()
            pageStatus = "正在 OpenAI 登录页面中…"
        }
    }

    private func isChatGPTPage(_ url: URL?) -> Bool {
        let host = url?.host?.lowercased()
        return host == "chatgpt.com" || host?.hasSuffix(".chatgpt.com") == true
    }
}

struct BrowserUsageCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = BrowserUsageController()
    let onCapture: (String) -> BrowserUsageResult

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(controller.pageStatus, systemImage: controller.canCapture ? "checkmark.shield.fill" : "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(controller.canCapture ? .green : .secondary)
                    Text("登录由 OpenAI 页面处理。奶康只在 Usage 页面读取屏幕上已经显示的额度文字，不读取密码、Cookie 或登录令牌。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.thinMaterial)

                BrowserWebView(controller: controller)

                HStack(spacing: 10) {
                    Button("打开 Usage 页面") { controller.openUsagePage() }
                        .buttonStyle(.bordered)
                    Button("刷新") { controller.reload() }
                        .buttonStyle(.bordered)
                    Button("立即读取") { controller.captureVisibleUsage() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!controller.canCapture || controller.isLoading)
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle("浏览器同步")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear { controller.onCapture = onCapture }
        }
    }
}

private struct BrowserWebView: UIViewRepresentable {
    @ObservedObject var controller: BrowserUsageController

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        controller.webView = webView
        controller.openUsagePage()
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.controller.stopAutoCapture()
        uiView.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let controller: BrowserUsageController

        init(controller: BrowserUsageController) {
            self.controller = controller
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            controller.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            controller.isLoading = false
            controller.update(for: webView.url)
            controller.startAutoCapture()
            if webView.url?.path.hasPrefix("/settings/usage") == true {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    self.controller.captureVisibleUsage(silently: true)
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            controller.isLoading = false
            controller.pageStatus = "页面加载失败：\(error.localizedDescription)"
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            controller.isLoading = false
            controller.pageStatus = "页面加载失败：\(error.localizedDescription)"
        }
    }
}
