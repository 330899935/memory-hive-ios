import SwiftUI
import UIKit

/// 问页（离线 Dig In）—— 家睡着了，先翻手边的副本
/// 视觉语言：断线余烬 + 冷青降级（琥珀暗下去、青蓝浮上来）
/// 2026-09-11 接真数据：OfflineResult.samples 假数据 → SearchCache 本地只读缓存
/// （在线问页每次搜索成功落快照，离线翻这份副本；搜索框做真实本地过滤）
struct 离线问页: View {
    /// 重试连接回调（由问页注入：探测成功则切回在线）
    var onReconnect: (() -> Void)? = nil
    /// 是否正在探测（按钮转圈 + 文案切换）
    var reconnecting: Bool = false

    @State private var query = ""
    @State private var snapshot: SearchCache.Snapshot?
    @FocusState private var searchFocused: Bool
    /// ⑯⑰ 点开看解释：Dig In 是什么 / 家睡着了是什么
    @State private var info: InfoItem?

    struct InfoItem: Identifiable {
        let id: Int
        let title: String
        let symbol: String
        let tint: Color
        let body: String
    }

    var body: some View {
        ZStack {
            HiveTheme.bgVoid.ignoresSafeArea()
            HexGrid()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    offlineBanner
                    searchBox
                    cacheHeader
                    content
                    retrySection
                }
                .padding(.horizontal, HiveTheme.contentInset)
                .padding(.top, HiveTheme.contentTop)
                .padding(.bottom, HiveTheme.contentBottom)
            }
            .scrollDismissesKeyboard(.interactively)
            StitchAccent().allowsHitTesting(false)
        }
        .onAppear { loadCache() }
        .sheet(item: $info) { item in
            InfoSheet(title: item.title, symbol: item.symbol, tint: item.tint, text: item.body)
        }
    }

    private func loadCache() {
        snapshot = SearchCache.load()
        // 不预填搜索框：query 留空 → 展示全部缓存（避免把缓存词当 placeholder，分不清）
    }

    /// 本地过滤后的结果（query 为空 → 全量缓存；否则按标题/摘要/仓名模糊匹配）
    ///
    /// 匹配走 `HiveSearchMatch`（归一化：去连接符 + 转小写）—— 见该类型注释。
    /// ⚠️ 归一化**只在匹配这一步**发生，`r.wh` / `r.title` 等原值一律不动，
    /// 列表显示与「进详情页传参」都还是原样 ⇒ **不污染显示值**。
    private var filtered: [HiveSearchResult] {
        guard let results = snapshot?.results else { return [] }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return results }
        return results.filter { r in
            HiveSearchMatch.matches(q, in: [
                r.title,
                r.summary,
                r.wh,
                // 2026-09-18 中英双译：仓名 **raw + 显示名双匹配** —— 英文界面下按
                //「Archive」也搜得到（`r.wh` 里存的永远是后端中文真名，不能改）
                HiveWarehouses.displayName(r.wh),
            ])
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MEMORY HIVE · 问")
                .font(.system(size: 12, weight: .bold))
                .tracking(3)
                .foregroundStyle(HiveTheme.cold)
            HStack(spacing: 8) {
                Button {
                    info = InfoItem(id: 1, title: String(localized: "Dig In 是什么"), symbol: "magnifyingglass", tint: HiveTheme.amber,
                        body: String(localized: "Dig In = 翻开家里蜂巢、把记忆捞出来。\n\n在线时，你搜一句话，它去电脑里的蜂巢找答案。\n\n离线时（家睡着了），它翻手边存过的本地缓存，先给你能给的，等家回来再补全。"))
                    HiveHaptics.light()
                } label: {
                    Text("Dig In")
                        .font(.system(size: 32, weight: .heavy))
                        .foregroundStyle(HiveTheme.textTitle)
                }
                .buttonStyle(.plain)
                HStack(spacing: 4) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 9, weight: .bold))
                    Text("离线")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(HiveTheme.cold)   // 低饱和灰，不跳出色系（P1-2）
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .overlay(Capsule().stroke(HiveTheme.amber.opacity(0.5), lineWidth: 1))  // 琥珀金细描边
                .background(HiveTheme.holoTop)
                .clipShape(Capsule())
            }
            Text("家睡着了，先翻手边的本地缓存")
                .font(.system(size: 14))
                .foregroundStyle(HiveTheme.textCaption)
        }
    }

    private var offlineBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(HiveTheme.amber.opacity(0.45))
                    .frame(width: 8, height: 8)
                // ⑰ 家睡着了 → 点开解释
                Button {
                    info = InfoItem(id: 2, title: String(localized: "家睡着了"), symbol: "moon.zzz", tint: HiveTheme.cold,
                        body: String(localized: "「家睡着了」= 手机现在连不上你电脑里的蜂巢。\n\n可能是电脑关机、没开机里的蜂巢服务，或者手机没和电脑连在同一个 Wi-Fi 下。\n\n不用担心，离线不会丢东西：你记下的都会先存在手机里，等家回来了自动送回家。"))
                    HiveHaptics.light()
                } label: {
                    HStack(spacing: 6) {
                        Text("家 · 睡着了")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(HiveTheme.textStrong)
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(HiveTheme.cold)
                    }
                }
                .buttonStyle(.plain)
            }
            Text("家里的蜂巢没回应 · 离线不丢东西，回家自动续上")
                .font(.system(size: 12))
                .foregroundStyle(HiveTheme.textSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(HiveTheme.cold.opacity(0.35), lineWidth: 1)
        )
        .background(HiveTheme.holoTop)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var searchBox: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(HiveTheme.textMuted)
            TextField("找一句话、一个时刻、一张图里的字", text: $query)
                .font(.system(size: 15))
                .foregroundStyle(HiveTheme.textStrong)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { searchFocused = false }
            if searchFocused {
                Button("取消") {
                    searchFocused = false
                }
                .font(.system(size: 15))
                .foregroundStyle(HiveTheme.amber)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .holoCard()
    }

    private var cacheHeader: some View {
        HStack {
            Text("本地缓存 · 只读")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(HiveTheme.textStrong)
            Spacer()
            Text(lastSyncText)
                .font(.system(size: 11))
                .foregroundStyle(HiveTheme.textCaption)
        }
        .padding(.top, 4)
    }

    private var lastSyncText: String {
        guard let date = snapshot?.updatedAt else { return String(localized: "暂无缓存") }
        return String(format: String(localized: "缓存快照 · %@"), SearchCache.lastSyncText(date))
    }

    /// 内容区：有缓存 → 结果列表；无缓存 → 空态引导
    @ViewBuilder
    private var content: some View {
        if filtered.isEmpty {
            noCacheHint
        } else {
            ForEach(filtered) { r in
                cacheCard(r)
            }
        }
    }

    private var noCacheHint: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(HiveTheme.textMuted)
            Text("手边还没有本地缓存")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(HiveTheme.textStrong)
            Text("连上家搜过一次，这里才会留下本地缓存")
                .font(.system(size: 12))
                .foregroundStyle(HiveTheme.textCaption)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func cacheCard(_ r: HiveSearchResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(HiveWarehouses.displayName(r.wh)) · @\(r.displayTime)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(HiveTheme.cold)
                Spacer()
                Text("本地")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(HiveTheme.cold)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .overlay(Capsule().stroke(HiveTheme.cold.opacity(0.4), lineWidth: 1))
                    .background(HiveTheme.holoTop)
                    .clipShape(Capsule())
            }
            Text(r.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(HiveTheme.textStrong)
            Text(r.summary)
                .font(.system(size: 12))
                .foregroundStyle(HiveTheme.textSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .holoCard()
    }

    private var retrySection: some View {
        VStack(spacing: 12) {
            Text("家回来了，这里会自己亮起来")
                .font(.system(size: 12))
                .foregroundStyle(HiveTheme.textCaption)
            Button {
                onReconnect?()
            } label: {
                HStack(spacing: 8) {
                    if reconnecting {
                        ProgressView()
                            .tint(HiveTheme.amber)
                            .scaleEffect(0.85)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15))
                    }
                    Text(reconnecting ? String(localized: "正在探家…") : String(localized: "重试连接"))
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(HiveTheme.amber)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .overlay(
                    Capsule().stroke(HiveTheme.amber.opacity(0.6), lineWidth: 1)
                )
                .background(HiveTheme.holoTop)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(reconnecting)
            // ⑲ 重试连接固定位置 + 「连不上为什么」排查解释
            Button {
                info = InfoItem(id: 3, title: String(localized: "为什么连不上"), symbol: "wrench.and.screwdriver", tint: HiveTheme.amber,
                    body: String(localized: "连不上家，按顺序查这几样：\n\n① 电脑开着吗？蜂巢服务在电脑里跑着吗？\n② 手机和电脑连的是不是同一个 Wi-Fi？\n③ 设置页「家连接」里的地址对不对（电脑蜂巢的局域网地址）？\n④ 密钥填对了吗？\n\n都对了还连不上，就等一会儿再点「重试连接」。")
                        + "\n\n"
                        // 引流（2026-09-19 指令书触点3）：排查兜底——万一压根没装电脑版，这里给下载口
                        + String(localized: "还没装电脑蜂巢？[点这里下载 Mac 版](https://apps.apple.com/app/id6806992983)"))
                HiveHaptics.light()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 12))
                    Text("连不上？点这里看怎么排查")
                        .font(.system(size: 12))
                }
                .foregroundStyle(HiveTheme.textCaption)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }
}

#Preview {
    离线问页()
}
