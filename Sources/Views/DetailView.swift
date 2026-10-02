import SwiftUI

/// 记忆详情页 —— 点问页搜索结果进入，阅读这条已归巢记忆的全文
/// 定位：手机端是「接住 + 回传」的桥，不做确认归档；这里只读，不提供归巢/拒绝决策
struct 记忆详情页: View {
    let result: HiveSearchResult
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var config: HiveConfig
    @State private var showDeleteConfirm = false
    @State private var showMoveSheet = false
    @State private var opBusy = false
    @State private var opResultText = ""

    var body: some View {
        ZStack {
            HiveTheme.bgVoid.ignoresSafeArea()
            HexGrid()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    detailCard
                    actionBar
                    footerInfo
                }
                .padding(.horizontal, HiveTheme.contentInset)
                .padding(.top, HiveTheme.contentTop)
                .padding(.bottom, HiveTheme.contentBottom)
            }
            StitchAccent().allowsHitTesting(false)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MEMORY HIVE · 记忆详情")
                .font(.system(size: 12, weight: .bold))
                .tracking(3)
                .foregroundStyle(HiveTheme.amber)
            HStack(spacing: 8) {
                Circle()
                    .fill(HiveTheme.green)
                    .frame(width: 7, height: 7)
                    .shadow(color: HiveTheme.green.opacity(0.8), radius: 5)
                Text("已归档")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HiveTheme.green)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(HiveTheme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(HiveTheme.holoTop)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var detailCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(result.title)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(HiveTheme.textTitle)
            Text(result.raw.isEmpty ? result.title : result.raw)
                .font(.system(size: 15))
                .foregroundStyle(HiveTheme.textSecondary)
                .lineSpacing(7)
            if result.type == "image" && !result.mediaPath.isEmpty {
                mediaView
            }
            HStack(spacing: 8) {
                tag(HiveWarehouses.displayName(result.wh))
                tag(result.typeLabel)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .holoCard()
    }

    private func tag(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(HiveTheme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .overlay(
                Capsule().stroke(HiveTheme.textMuted.opacity(0.5), lineWidth: 1)
            )
    }

    /// 已归巢照片渲染：后端 /media/* 免鉴权吐图片字节，拼 baseURL + media_path 拉取
    private var mediaView: some View {
        AsyncImage(url: mediaURL) { phase in
            switch phase {
            case .success(let img):
                img.resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(HiveTheme.textMuted.opacity(0.3), lineWidth: 1))
            case .failure:
                Label("图片加载失败", systemImage: "photo.badge.exclamationmark")
                    .font(.system(size: 13))
                    .foregroundStyle(HiveTheme.textCaption)
            case .empty:
                ProgressView().tint(HiveTheme.amber)
            @unknown default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var mediaURL: URL? {
        let base = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: base + "/" + result.mediaPath)
    }

    private var footerInfo: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 12))
                .foregroundStyle(HiveTheme.green)
            Text("已安全归档 · \(HiveWarehouses.displayName(result.wh)) · \(result.displayTime)")
                .font(.system(size: 12))
                .foregroundStyle(HiveTheme.textCaption)
        }
        .padding(.horizontal, 8)
    }

    /// 底部操作区（㉘ 问页/详情可操作闭环）：转移换仓 + 删除（软删进回收站）
    private var actionBar: some View {
        VStack(spacing: 10) {
            if !opResultText.isEmpty {
                Text(opResultText)
                    .font(.system(size: 12))
                    .foregroundStyle(HiveTheme.textSecondary)
                    .transition(.opacity)
            }
            HStack(spacing: 12) {
                Button {
                    showMoveSheet = true
                } label: {
                    Label("转移", systemImage: "arrow.triangle.swap")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(HiveTheme.cyan)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(HiveTheme.cyan.opacity(0.45), lineWidth: 1)
                        )
                        .background(HiveTheme.holoTop)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(opBusy)

                Button {
                    showDeleteConfirm = true
                } label: {
                    Label("删除", systemImage: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(HiveTheme.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(HiveTheme.red.opacity(0.45), lineWidth: 1)
                        )
                        .background(HiveTheme.holoTop)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(opBusy)
            }
            if opBusy {
                ProgressView().tint(HiveTheme.amber)
            }
        }
        .confirmationDialog("删除这条记忆？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除（移入回收站，可恢复）", role: .destructive) {
                Task { await doDelete() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后进入回收站，还能恢复，不会立刻消失。")
        }
        .sheet(isPresented: $showMoveSheet) {
            moveSheet
        }
    }

    /// 转移目标仓选择（工作区 4 仓 + 隐私区 4 仓）
    /// 按钮显示 displayName（「归档历史」显示为「历史仓」），点下去仍用后端真名当 target
    private var moveSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("转移到哪个仓")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(HiveTheme.textStrong)
            ForEach(HiveWarehouses.all, id: \.self) { wh in
                Button {
                    showMoveSheet = false
                    Task { await doMove(to: wh) }
                } label: {
                    HStack {
                        Text(HiveWarehouses.displayName(wh))
                            .font(.system(size: 14))
                            .foregroundStyle(HiveTheme.textStrong)
                        Spacer()
                        if wh == result.wh {
                            Text("当前")
                                .font(.system(size: 11))
                                .foregroundStyle(HiveTheme.textCaption)
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(HiveTheme.holoTop)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HiveTheme.bgVoid)
        .presentationDetents([.height(420)])
    }

    private func doDelete() async {
        opBusy = true
        opResultText = ""
        switch await HiveWarehouseService.deleteMemory(result, config: config) {
        case .ok(let text):
            opResultText = text
            HiveHaptics.success()
            try? await Task.sleep(nanoseconds: 600_000_000)
            dismiss()
        case .offline:
            opResultText = String(localized: "连不上家，删除没成")
        case .notReady:
            opResultText = String(localized: "还没填家地址/密钥")
        case .failed(let msg):
            opResultText = msg
        }
        opBusy = false
    }

    private func doMove(to target: String) async {
        opBusy = true
        opResultText = ""
        switch await HiveWarehouseService.moveMemory(result, to: target, config: config) {
        case .ok(let text):
            opResultText = text
            HiveHaptics.success()
        case .offline:
            opResultText = String(localized: "连不上家，转移没成")
        case .notReady:
            opResultText = String(localized: "还没填家地址/密钥")
        case .failed(let msg):
            opResultText = msg
        }
        opBusy = false
    }
}

#Preview {
    记忆详情页(result: HiveSearchResult(
        id: "x",
        title: "把手机版的脸先描出来看看",
        raw: "手机 app 不是记事本，是「agent 接口层」在移动端，命脉就是连接手机上的智能体。",
        timestamp: "2026-09-11 17:00:00",
        type: "observe",
        score: 1.0,
        matched: 1,
        wh: "当前主线"
    ))
    .environmentObject(HiveConfig())
}
