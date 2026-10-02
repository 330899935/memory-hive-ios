import SwiftUI
import PhotosUI

/// 存页 —— 接住念头（本地暂存 → 一键归档）
/// 视觉语言：磁吸堆叠胶片
/// 信息架构（老铁 2026-09-11 四轮定 · 三态词 2026-09-18 对齐）：
///   - 待同步 = 只在本机，左滑露出 编辑(黄)/删除(红)，右侧「归档」描边小按钮
///   - 待确认 = 已投收件箱、蜂巢未确认
///   - 已归档 = 蜂巢已确认入库（后端回 stored 才有；当前接口未暴露 → 通常为空）
///   - 待同步 ≥2 条时，底部轻量「全部归档」胶囊
///   - 空状态：全息蜂巢投影 + 一句话（免费 App 的温度）
struct 存页: View {
    @State private var draft = ""
    @EnvironmentObject private var store: ThoughtStore
    @EnvironmentObject private var config: HiveConfig
    @State private var syncing = false
    @State private var lastResult = ""
    @State private var editingThought: PendingThought?
    @State private var editText = ""
    @FocusState private var inputFocused: Bool
    /// ⑨⑭ 点开本地念头看详情（全文 + 改名 + 删除 + 未同步归档）
    @State private var detailThought: PendingThought?
    /// ⑬ 存入框关联手机数据：相册选图 / 文件选文档
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showDocPicker = false
    // 2026-09-18（任务 B）：相册/文件接住后不再必弹起名层，改由后台自动理解补名
    /// ⑫ 接住念头位置可点解释
    @State private var showIntro = false

    var body: some View {
        ZStack {
            HiveTheme.bgVoid.ignoresSafeArea()
            HexGrid()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    inputCard
                    pendingSection
                    batchSyncButton
                    awaitingSection
                    archivedSection
                    footerStat
                }
                .padding(.horizontal, HiveTheme.contentInset)
                .padding(.top, HiveTheme.contentTop)
                .padding(.bottom, HiveTheme.contentBottom)
            }
            .scrollDismissesKeyboard(.interactively)
            StitchAccent().allowsHitTesting(false)
        }
        .sheet(item: $editingThought) { thought in
            editSheet(thought)
                .presentationDetents([.height(220)])
        }
        .sheet(item: $detailThought) { thought in
            ThoughtDetailSheet(thought: thought)
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        // 三态闭环（2026-09-18）：进存页首帧回查一次「待确认 → 已归档」——
        // 电脑端在那头点过确认后，回到手机进存页就能看到终态，不必等下一刀回前台。
        .task { await HiveSyncService.refreshArchived(store: store, config: config) }
        // 分段P1-5：断线重连。存页此前失败只落一行文案（`syncAll` 的 `.offline` 分支），
        // 家回来了没人去探 —— 用户得自己切到问页才知道。挂上退避重连后，
        // 家一回来这页自己会接上（已连上时在 `shouldStart` 处立即返回，零开销）。
        .task { await HiveSyncService.reconnectLoop(config: config) }
        .sheet(isPresented: $showDocPicker) {
            DocumentPicker { url in
                loadDoc(url)
            }
        }
        .sheet(isPresented: $showIntro) {
            InfoSheet(title: String(localized: "接住念头是什么"), symbol: "hand.tap", tint: HiveTheme.amber,
                text: String(localized: "「接住念头」= 随手把你此刻的想法、画面、声音先收进手机。\n\n能做什么：\n• 写字 / 拍照 / 录音 / 选相册 / 选文件，都行\n• 先存在手机本地，不用等电脑\n• 点「归档」送回家，存进电脑里的蜂巢\n\n做不了什么：\n• 它不主动去扫描你手机里别的 App 数据\n• 不会自己联网上传，除非你点「归档」"))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MEMORY HIVE · 存")
                .font(.system(size: 12, weight: .bold))
                .tracking(3)
                .foregroundStyle(HiveTheme.amber)
            Button {
                showIntro = true
                HiveHaptics.light()
            } label: {
                HStack(spacing: 6) {
                    Text("接住念头")
                        .font(.system(size: 32, weight: .heavy))
                        .foregroundStyle(HiveTheme.textTitle)
                    Image(systemName: "info.circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(HiveTheme.textMuted)
                }
            }
            .buttonStyle(.plain)
            Text("存口袋，归家里")
                .font(.system(size: 13))
                .foregroundStyle(HiveTheme.textMuted)
        }
    }

    private var inputCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                inputDot
                TextField(
                    "",
                    text: $draft,
                    prompt: Text("此刻的念头，先搁这儿...")
                        .foregroundStyle(HiveTheme.textSecondary)
                )
                .font(.system(size: 15))
                .foregroundStyle(HiveTheme.textStrong)
                .focused($inputFocused)
                .submitLabel(.done)
                .onSubmit { inputFocused = false }
                Button {
                    guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    let t = store.add(text: draft)
                    autoUnderstand(t)
                    HiveHaptics.light()
                    draft = ""
                } label: {
                    Text("存")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(HiveTheme.bgVoid)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(HiveTheme.amber)
                        .clipShape(Capsule())
                        .shadow(color: HiveTheme.amber.opacity(0.5), radius: 8)
                }
                .buttonStyle(.plain)
            }
            // ⑬ 关联手机数据：相册选图 / 文件选文档
            HStack(spacing: 10) {
                attachButton(symbol: "photo.on.rectangle", label: String(localized: "相册"), tint: HiveTheme.green) {
                    showPhotoPicker = true
                }
                attachButton(symbol: "doc.badge.plus", label: String(localized: "文件"), tint: HiveTheme.cyan) {
                    showDocPicker = true
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .holoCard()
    }

    /// ⑬ 附件入口小按钮
    private func attachButton(symbol: String, label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(HiveTheme.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .overlay(Capsule().stroke(tint.opacity(0.4), lineWidth: 1))
            .background(HiveTheme.holoTop)
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// ⑬ 相册选图 → 存成图片念头
    @MainActor
    private func loadPhoto(_ item: PhotosPickerItem) async {
        if let data = try? await item.loadTransferable(type: Data.self) {
            if let t = store.add(imageData: data) {
                HiveHaptics.light()
                autoUnderstandMedia(t)   // 不再弹起名层
            }
        }
        photoItem = nil
    }

    /// ⑬ 文件选文档 → 读文本存成文字念头；非文本则存文件名
    @MainActor
    private func loadDoc(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let fileName = url.lastPathComponent
        let ext = (fileName as NSString).pathExtension.lowercased()
        // 文本类扩展名：直接读全文存成文字念头
        // G7-D15（1.3.5 · 段3C）：本表与「可存储类别」卡片文案（Localizable.xcstrings 的
        //   `类别格式_文本`）以及电脑端 index.html 的 STORAGE_CATEGORIES **三处同源**。
        //   为什么本段必须一起改：D15 把卡片文案对齐到电脑端清单（含 c/cpp/h/go/rs/java/
        //   kt/ts/tsx/php/rb/lua/r/sql），若此处不同步，卡片就成了「承诺支持、实际不读」
        //   —— 那是水分。本表新增项只是把「按文本读全文」的范围补齐，**失败仍然安全**：
        //   解码失败 / 内容为空都会落回下面的 else 分支走文档路径（不丢原件、不卡流程）。
        //   排序照抄电脑端 STORAGE_CATEGORIES 的 ext 串，便于日后 diff 对账。
        let textExts: Set<String> = ["txt", "md", "py", "js", "html", "css", "json", "csv",
                                     "xml", "yml", "yaml", "log", "sh", "bat", "ini", "cfg",
                                     "toml", "c", "cpp", "h", "go", "rs", "java", "kt", "ts",
                                     "tsx", "php", "rb", "lua", "r", "sql"]
        let audioExts: Set<String> = ["mp3", "wav", "m4a", "flac", "aac", "ogg", "wma", "aiff", "alac", "ape", "midi", "mid"]
        let videoExts: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "webm", "wmv", "flv", "3gp", "mpg", "mpeg"]
        if textExts.contains(ext),
           let text = try? String(contentsOf: url, encoding: .utf8),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            autoUnderstand(store.add(text: text))
        } else if let data = try? Data(contentsOf: url) {
            if videoExts.contains(ext) {
                if let t = store.add(videoFile: data, ext: ext, fileName: fileName) { autoUnderstandMedia(t) }
            } else if audioExts.contains(ext) {
                if let t = store.add(audioFile: data, ext: ext, fileName: fileName) { autoUnderstandMedia(t) }
            } else {
                // 二进制/文档（docx/pdf/zip 等）：读字节存成文档念头，归档时走 upload+extract
                if let t = store.add(document: data, ext: ext, fileName: fileName) { autoUnderstandMedia(t) }
            }
        } else {
            autoUnderstand(store.add(text: String(format: String(localized: "文件：%@"), fileName)))
        }
        HiveHaptics.light()
    }

    /// 第①步「接住念头的自动理解」：存下文字念头后，借电脑大脑自动起名 + 摘要 + 归类
    /// 异步后台跑，失败/离线/未配 key 静默兑底到手动填，不阻塞用户
    @MainActor
    private func autoUnderstand(_ thought: PendingThought) {
        let text = thought.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Task {
            if let r = await HiveSyncService.understand(text: text, config: config) {
                store.setUnderstand(thought, name: r.name, summary: r.summary, suggest: r.suggest)
            }
        }
    }

    /// 媒体类自动理解（图片 OCR / 录音 STT）：存完异步跑，成功自动起名+摘要+归类
    /// 异常分支（失败/离线/未配 key）：补时间戳默认名，念头仍可辨认、不丢数据、不卡流程
    @MainActor
    private func autoUnderstandMedia(_ thought: PendingThought) {
        Task {
            if let r = await HiveSyncService.understandMedia(thought: thought, store: store, config: config) {
                store.setUnderstand(thought, name: r.name, summary: r.summary, suggest: r.suggest)
            } else {
                store.ensureDefaultName(thought)
            }
        }
    }

    /// 输入框左侧小圆点：聚焦时过渡成蜂巢微缩图标
    private var inputDot: some View {
        ZStack {
            Circle()
                .fill(HiveTheme.amber)
                .frame(width: 8, height: 8)
                .shadow(color: HiveTheme.amber.opacity(0.8), radius: 6)
                .opacity(inputFocused ? 0 : 1)
            Image(systemName: "hexagon.fill")
                .font(.system(size: 11))
                .foregroundStyle(HiveTheme.amber)
                .opacity(inputFocused ? 1 : 0)
                .scaleEffect(inputFocused ? 1 : 0.6)
        }
        .frame(width: 14, height: 14)
        .animation(.easeInOut(duration: 0.22), value: inputFocused)
    }

    // MARK: - 待同步区（草稿，还没送回家）
    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("待同步")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(HiveTheme.textStrong)
                Spacer()
                Text("\(pendingCount) 条 · 暂存在本地")
                    .font(.system(size: 12))
                    .foregroundStyle(HiveTheme.textCaption)
            }
            if pendingCount == 0 {
                emptyState
            } else {
                ForEach(store.thoughts.filter { !$0.synced }) { t in
                    pendingRow(t)
                }
            }
        }
    }

    // MARK: - 空状态（全息蜂巢投影 + 温度）
    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Image(systemName: "hexagon.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(HiveTheme.amber.opacity(0.10))
                Image(systemName: "hexagon")
                    .font(.system(size: 44))
                    .foregroundStyle(HiveTheme.amber.opacity(0.28))
            }
            .shadow(color: HiveTheme.amber.opacity(0.15), radius: 18)
            Text("手边没有待同步的念头，此刻你可以专注当下。")
                .font(.system(size: 13))
                .foregroundStyle(HiveTheme.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    // MARK: - 待同步卡片（左滑编辑/删除 + 右侧描边归巢）
    private func pendingRow(_ t: PendingThought) -> some View {
        HStack(spacing: 10) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(HiveTheme.amber)
                        .frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t.displayTitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(HiveTheme.textStrong)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text("暂存在本地 · \(t.createdAt.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 11))
                            .foregroundStyle(HiveTheme.textMuted)
                    }
                    Spacer()
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HiveTheme.holoTop)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(HiveTheme.amber.opacity(0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .contentShape(RoundedRectangle(cornerRadius: 20))
            .onTapGesture {
                detailThought = t
                HiveHaptics.light()
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    store.remove(t)
                    HiveHaptics.light()
                } label: {
                    Label("删除", systemImage: "trash")
                }
                Button {
                    beginEdit(t)
                } label: {
                    Label("编辑", systemImage: "pencil")
                }
                .tint(HiveTheme.amberDeep)
            }

            Button {
                Task { await syncOne(t) }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(HiveTheme.amber)
                    .frame(width: 34, height: 34)
                    .overlay(
                        Circle().stroke(HiveTheme.amber.opacity(0.55), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 批量归档（待同步 ≥2 条才显示，轻量胶囊）
    @ViewBuilder
    private var batchSyncButton: some View {
        if pendingCount >= 2 {
            VStack(spacing: 6) {
                if syncing {
                    HStack(spacing: 8) {
                        ProgressView().tint(HiveTheme.amber)
                        Text("提交中...")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(HiveTheme.textStrong)
                    }
                } else {
                    Button {
                        Task { await syncAll() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 15))
                            Text("全部提交归档")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(HiveTheme.amber)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .overlay(Capsule().stroke(HiveTheme.amber.opacity(0.55), lineWidth: 1))
                        .background(HiveTheme.holoTop)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                if !lastResult.isEmpty {
                    Text(lastResult)
                        .font(.system(size: 12))
                        .foregroundStyle(HiveTheme.textSecondary)
                }
                // 分段P1-5：连不上家时的重试出口 + 退避倒计时。
                // 此前这一块只有一行失败文案，用户没有任何可点的东西。
                if !config.isConnected {
                    saveReconnectRow
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - 待确认区（已投收件箱、蜂巢还没确认入库）
    @ViewBuilder
    private var awaitingSection: some View {
        let awaiting = store.thoughts.filter { $0.synced && !$0.archived }
        if !awaiting.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("待确认")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(HiveTheme.textStrong)
                    Spacer()
                    Text("\(awaiting.count) 条 · 已投收件箱")
                        .font(.system(size: 12))
                        .foregroundStyle(HiveTheme.textCaption)
                }
                ForEach(awaiting) { t in
                    syncedRow(t)
                }
            }
        }
    }

    // MARK: - 已归档区（蜂巢已确认入库；后端补 stored 回查前通常为空）
    @ViewBuilder
    private var archivedSection: some View {
        let done = store.thoughts.filter { $0.archived }
        if !done.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("已归档")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(HiveTheme.textStrong)
                    Spacer()
                    Text("\(done.count) 条 · 已安全归档")
                        .font(.system(size: 12))
                        .foregroundStyle(HiveTheme.textCaption)
                }
                ForEach(done) { t in
                    syncedRow(t)
                }
            }
        }
    }

    /// 已发出的卡片（待确认 / 已归档共用）：左滑删除，点卡看详情（⑭）
    private func syncedRow(_ t: PendingThought) -> some View {
        Button {
            detailThought = t
            HiveHaptics.light()
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(t.archived ? HiveTheme.green : HiveTheme.amber)
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 3) {
                    Text(t.displayTitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(HiveTheme.textStrong)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(t.archived ? String(localized: "已安全归档") : String(localized: "已投收件箱 · 等蜂巢确认"))
                        .font(.system(size: 11))
                        .foregroundStyle(t.archived ? HiveTheme.green : HiveTheme.amber)
                }
                Spacer()
            }
            .padding(14)
            .holoCard()
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                store.remove(t)
                HiveHaptics.light()
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    // MARK: - 底部统计（填留白）
    private var footerStat: some View {
        VStack(spacing: 6) {
            if archivedCount > 0 {
                Text("已经安全归档 \(archivedCount) 条念头")
                    .font(.system(size: 12))
                    .foregroundStyle(HiveTheme.textMuted)
            }
            Button {
                // 占位：后续跳「查看全部归档记录」
            } label: {
                Text("查看全部归档记录")
                    .font(.system(size: 12))
                    .foregroundStyle(HiveTheme.amber)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private var pendingCount: Int {
        store.thoughts.filter { !$0.synced }.count
    }

    private var archivedCount: Int {
        store.thoughts.filter { $0.archived }.count
    }

    // MARK: - 编辑
    private func beginEdit(_ thought: PendingThought) {
        editText = thought.content
        editingThought = thought
    }

    private func editSheet(_ thought: PendingThought) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("编辑念头")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(HiveTheme.textStrong)
            TextField("", text: $editText, axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(HiveTheme.textStrong)
                .lineLimit(2...5)
                .padding(12)
                .background(HiveTheme.holoTop)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            HStack {
                Button {
                    store.remove(thought)
                    HiveHaptics.light()
                    editingThought = nil
                } label: {
                    Text("删除")
                        .font(.system(size: 15))
                        .foregroundStyle(HiveTheme.red)
                }
                .buttonStyle(.plain)
                Spacer()
                Button("取消") {
                    editingThought = nil
                }
                .foregroundStyle(HiveTheme.textSecondary)
                Button("保存") {
                    store.updateText(thought, content: editText)
                    HiveHaptics.light()
                    editingThought = nil
                }
                .foregroundStyle(HiveTheme.amber)
                .fontWeight(.semibold)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(HiveTheme.bgVoid)
    }

    // MARK: - 归档动作
    @MainActor
    private func syncAll() async {
        syncing = true
        lastResult = ""
        let result = await HiveSyncService.sync(store: store, config: config)
        syncing = false
        switch result {
        case .synced(0):
            lastResult = String(localized: "没有待同步的念头")
        case .synced(let n):
            let done = archivedCount
            lastResult = done > 0
                ? String(localized: "已发送 \(n) 条 · 其中 \(done) 条已归档")
                : String(localized: "已发送 \(n) 条 · 等蜂巢确认归档")
            HiveHaptics.success()
        case .offline:
            lastResult = String(localized: "连不上家里电脑，已保留在本地，稍后再试")
            // 分段P1-5：刚刚**实测**连不上 ⇒ 起退避重连（家回来了自动补上，不必用户自己去戳）
            reconnectInBackground()
        case .notReady:
            lastResult = String(localized: "先去设置页填「家地址 + 密钥」")
        case .failed(let msg):
            lastResult = msg
        }
    }

    @MainActor
    private func syncOne(_ thought: PendingThought) async {
        lastResult = ""
        let result = await HiveSyncService.syncOne(thought: thought, store: store, config: config)
        switch result {
        case .synced(let n) where n > 0:
            let stage = store.thoughts.first { $0.id == thought.id }?.stage ?? .local
            lastResult = stage == .archived ? String(localized: "已安全归档") : String(localized: "已发送 · 等蜂巢确认归档")
            HiveHaptics.success()
        case .offline:
            lastResult = String(localized: "连不上家里电脑，已保留在本地")
            // 分段P1-5：同 `syncAll` —— 单条失败也起退避重连
            reconnectInBackground()
        case .notReady:
            lastResult = String(localized: "先去设置页填「家地址 + 密钥」")
        case .failed(let msg):
            lastResult = msg
        default:
            break
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    // MARK: - 分段P1-5 · 断线重连（存页侧）
    // ══════════════════════════════════════════════════════════════════════

    /// 起一个**后台**退避重连（不阻塞当前动作 —— 归档动作该立刻给用户回话，
    /// 不能被重连循环拖着）。
    ///
    /// `force: true` 的理由：调用点都是「刚刚实测连不上」的分支，此刻
    /// `credentialVerified` 可能还是上一次的 `true`（陈旧），默认闸门
    /// （`shouldStart`）会把循环挡在门外。而我们手握一次**真实失败** ⇒
    /// 「该重连」不需要再问那个陈旧标记。
    /// 防重入由 `HiveSyncService.reconnectLoop` 内部的 `reconnectActive` 负责 ——
    /// 连点几次「全部提交归档」也只会跑一个循环。
    ///
    /// ⚠ 不做「顺手把绿灯熄掉」：绿灯（`credentialVerified`）的唯一写入点是
    ///   `HiveSyncService.probeConnection` / `SettingsView.refreshStates`（P1-4 的验收口径）。
    ///   本循环的首探就会调 `probeConnection` ⇒ **失败时绿灯会由那条既有路径自然熄灭**，
    ///   这里不需要、也不应该另开一个写入点。
    private func reconnectInBackground() {
        Task { await HiveSyncService.reconnectLoop(config: config, force: true) }
    }

    /// 分段P1-5 · 存页的「重试连接」（此前存页失败只落一行文案，没有任何可点的出口）
    private var saveReconnectRow: some View {
        HStack(spacing: 8) {
            if config.reconnectProbing {
                ProgressView().tint(HiveTheme.amber).scaleEffect(0.7)
            } else {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 10))
                    .foregroundStyle(HiveTheme.cold)
            }
            Text(saveReconnectText)
                .font(.system(size: 11))
                .foregroundStyle(HiveTheme.textCaption)
                .lineLimit(1)
            Spacer(minLength: 6)
            Button {
                HiveHaptics.light()
                Task { await HiveSyncService.retryNow(config: config) }
            } label: {
                Text("重试连接")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(HiveTheme.amber)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .overlay(Capsule().stroke(HiveTheme.amber.opacity(0.5), lineWidth: 1))
                    .background(HiveTheme.holoTop)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(config.reconnectProbing)
        }
    }

    /// 存页的重连状态文案（分段P1-5）
    private var saveReconnectText: String {
        if config.reconnectProbing { return String(localized: "正在探家…") }
        if config.isAutoReconnecting {
            return String(format: String(localized: "%lld 秒后自动重试"),
                          Int64(config.reconnectWaitSeconds))
        }
        return String(localized: "家没连上 · 念头已留在本地")
    }
}

#Preview {
    存页()
        .environmentObject(ThoughtStore())
        .environmentObject(HiveConfig())
}
