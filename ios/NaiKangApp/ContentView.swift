import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: NaiKangAppModel
    @StateObject private var viewState = ContentViewState()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    hero
                    quotaCard
                    networkCard
                    connectionCard
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("奶康")
            .refreshable { await model.refreshNetworkInfo() }
            .task { await model.refreshNetworkInfo() }
            .sheet(isPresented: $viewState.showsBrowserCapture) {
                BrowserUsageCaptureView { text in
                    let result = model.applyBrowserUsage(text: text)
                    Task { await model.refreshNetworkInfo() }
                    return result
                }
            }
        }
    }

    private var hero: some View {
        HStack(spacing: 16) {
            Image("NaiKang")
                .resizable().scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 5)
            VStack(alignment: .leading, spacing: 6) {
                Text("奶康").font(.largeTitle.bold())
                Text(model.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(model.liveActivityEnabled ? "结束锁屏状态" : "显示在锁屏／灵动岛") {
                    Task { await model.toggleLiveActivity() }
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var quotaCard: some View {
        VStack(spacing: 16) {
            quotaRow(title: "5 小时额度", value: model.snapshot.primaryRemaining, color: quotaColor(model.snapshot.primaryRemaining))
            quotaRow(title: "7 天额度", value: model.snapshot.secondaryRemaining, color: .green)
            HStack {
                Label(String(format: "消耗 %.1f%% / 小时", model.snapshot.burnRate), systemImage: "flame.fill")
                Spacer()
                if let reset = model.snapshot.resetDate {
                    Text(reset, style: .relative).foregroundStyle(.secondary)
                }
            }
            .font(.footnote)
        }
        .cardStyle()
    }

    private var networkCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("网络", systemImage: "network").font(.headline)
            valueRow("公网 IP", model.snapshot.publicIP)
            valueRow("IP 归属地", model.snapshot.ipLocation)
            valueRow("数据来源", model.snapshot.localIP)
            HStack {
                Label("公网信息由 iPhone 获取", systemImage: "iphone.and.arrow.forward")
                Spacer()
                if model.isRefreshingNetwork { ProgressView().controlSize(.small) }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("浏览器同步", systemImage: "safari.fill").font(.headline)
            Text("在奶康内打开 OpenAI 官方 Usage 页面，登录后读取页面上可见的 5 小时和 7 天额度。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                viewState.showsBrowserCapture = true
            } label: {
                Label("登录并读取额度", systemImage: "person.crop.circle.badge.checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Text("密码与登录状态由 OpenAI 网页处理；奶康不保存密码，也不读取 Cookie 或令牌。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private func quotaRow(title: String, value: Int, color: Color) -> some View {
        VStack(spacing: 7) {
            HStack { Text(title).fontWeight(.semibold); Spacer(); Text("剩余 \(value)%").fontWeight(.bold) }
            ProgressView(value: Double(value), total: 100).tint(color)
        }
    }

    private func valueRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
    }

    private func quotaColor(_ value: Int) -> Color {
        value > 50 ? .green : (value > 20 ? .orange : .red)
    }
}

private final class ContentViewState: ObservableObject {
    @Published var showsBrowserCapture = false
}

private extension View {
    func cardStyle() -> some View {
        padding(18)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

