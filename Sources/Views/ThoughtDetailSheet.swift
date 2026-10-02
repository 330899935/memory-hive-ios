import SwiftUI
import UIKit
import AVFoundation

/// 本地念头详情弹层（⑨⑩⑭ 共用）：
/// 点开一条念头看全文 + 改名/写摘要 + 删除；未同步的还提供「归档（送回家）」按钮
/// 首页「最近接住」、存页「待同步/待确认」都走这里，做到「点开能看、能改、能删、能下一步」
struct ThoughtDetailSheet: View {
    let thought: PendingThought
    @EnvironmentObject private var store: ThoughtStore
    @EnvironmentObject private var config: HiveConfig
    @Environment(\.dismiss) private var dismiss
    @State private var syncBusy = false
    @State private var resultText = ""
    @State private var showDeleteConfirm = false
    /// 任务 B：自动理解之后，想改名还能改（详情页保留人工编辑口）
    @State private var showRename = false

    /// 队列里的实时版本：改名/归档后立即反映到徽标与正文（入参是值拷贝，不会自动刷新）
    private var current: PendingThought {
        store.thoughts.first { $0.id == thought.id } ?? thought
    }

    // 14 条修复第 1 条：录音念头可点开复核听（补播放入口）。
    // 只在这层持有播放器；关掉弹层就停，不留后台声音。
    @State private var audioPlayer: AVAudioPlayer?
    @State private var audioPlaying = false
    /// AVAudioPlayer 的 `delegate` 是 weak，必须自己强持一份，否则播完回调永不触发。
    @State private var playbackDelegate: AudioPlaybackDelegate?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                bodyText
                if thought.kind == .audio { audioPlaybackRow }
                renameButton
                if !current.synced {
                    syncButton
                }
                deleteButton
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(HiveTheme.bgVoid)
        .sheet(isPresented: $showRename) {
            ThoughtNameSheet(thought: current)
        }
        .confirmationDialog("删除这条念头？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                store.remove(thought)
                HiveHaptics.light()
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("从本地移除这条念头（附件一并删除）。")
        }
        .onDisappear { stopPlayback() }
    }

    // MARK: - 录音复核（14 条修复第 1 条）

    /// 录音复核按钮：读本地附件 .m4a，AVAudioPlayer 播放；再点暂停，播完自动复位。
    private var audioPlaybackRow: some View {
        Button {
            togglePlayback()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: audioPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(HiveTheme.purple)
                Text(audioPlaying ? String(localized: "暂停") : String(localized: "播放录音"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(HiveTheme.textStrong)
                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(HiveTheme.purple.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(HiveTheme.purple.opacity(0.45), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func togglePlayback() {
        if audioPlaying {
            stopPlayback()
            return
        }
        guard let url = store.attachmentURL(for: thought) else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            // 视图是 struct，无法 [weak self]；直接捕获值拷贝（@State 仍指向同一持久存储，可安全回写）。
            let delegate = AudioPlaybackDelegate {
                DispatchQueue.main.async {
                    self.stopPlayback()
                }
            }
            player.delegate = delegate
            playbackDelegate = delegate   // 强持，防止被弱引用立刻释放
            player.play()
            audioPlayer = player
            audioPlaying = true
        } catch {
            audioPlaying = false
        }
    }

    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        audioPlaying = false
        playbackDelegate = nil
    }

    /// AVAudioPlayer 委托：播完自动复位按钮（弱引用，不阻止弹层释放）。
    private final class AudioPlaybackDelegate: NSObject, AVAudioPlayerDelegate {
        private let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            onFinish()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.15))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(kindName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                Text(thought.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11))
                    .foregroundStyle(HiveTheme.textCaption)
            }
            Spacer()
            Text(current.stage.label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(stageTint)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(stageTint.opacity(0.12))
                .clipShape(Capsule())
        }
    }

    /// 三态色：待同步金深 / 待确认琥珀 / 已归档绿
    private var stageTint: Color {
        switch current.stage {
        case .local: return HiveTheme.amberDeep
        case .awaitingConfirm: return HiveTheme.amber
        case .archived: return HiveTheme.green
        }
    }

    private var bodyText: some View {
        VStack(alignment: .leading, spacing: 10) {
            if thought.kind == .photo {
                localImageView
            }
            if !current.name.isEmpty {
                Text(current.name)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(HiveTheme.textTitle)
            }
            if !current.summary.isEmpty {
                Text(current.summary)
                    .font(.system(size: 13))
                    .foregroundStyle(HiveTheme.textBody)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(current.content)
                .font(.system(size: 15))
                .foregroundStyle(HiveTheme.textBody)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(HiveTheme.holoTop)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// 本地照片显示：读附件目录的图片文件渲染（照片接住后点开就能直接看到）
    @ViewBuilder
    private var localImageView: some View {
        if let url = store.attachmentURL(for: thought),
           let data = try? Data(contentsOf: url),
           let ui = UIImage(data: data) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(HiveTheme.textMuted.opacity(0.3), lineWidth: 1))
        }
    }

    /// 任务 B：改名 / 写摘要入口（自动理解改不动、或用户想自己起名时用）
    private var renameButton: some View {
        Button {
            showRename = true
            HiveHaptics.light()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "pencil")
                    .font(.system(size: 14))
                Text("改名 / 写摘要")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(HiveTheme.cyan)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .overlay(Capsule().stroke(HiveTheme.cyan.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var syncButton: some View {
        Button {
            Task { await doSync() }
        } label: {
            HStack(spacing: 8) {
                if syncBusy {
                    ProgressView().tint(HiveTheme.amber)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 15))
                }
                Text(syncBusy ? String(localized: "提交中...") : String(localized: "提交归档"))
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(HiveTheme.amber)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .overlay(Capsule().stroke(HiveTheme.amber.opacity(0.55), lineWidth: 1))
            .background(HiveTheme.holoTop)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(syncBusy)
    }

    private var deleteButton: some View {
        Button {
            showDeleteConfirm = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                Text("删除")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(HiveTheme.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .overlay(Capsule().stroke(HiveTheme.red.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func doSync() async {
        syncBusy = true
        resultText = ""
        switch await HiveSyncService.syncOne(thought: thought, store: store, config: config) {
        case .synced:
            // 落地态以队列实时状态为准：入库→已归档；只进收件箱→待确认（不谎报完成）
            let stage = store.thoughts.first { $0.id == thought.id }?.stage ?? .local
            resultText = stage == .archived ? String(localized: "已安全归档") : String(localized: "已投收件箱 · 等蜂巢确认")
            HiveHaptics.success()
        case .offline:
            resultText = String(localized: "连不上家里电脑，已保留在本地")
        case .notReady:
            resultText = String(localized: "先去设置页填「家地址 + 密钥」")
        case .failed(let msg):
            resultText = msg
        }
        syncBusy = false
        if !resultText.isEmpty {
            // 发出成功后停留一下再关（含「待确认」：也让用户看清落在哪一态）
            try? await Task.sleep(nanoseconds: 700_000_000)
            dismiss()
        }
    }

    private var symbol: String {
        switch thought.kind {
        case .text: return "doc.text"
        case .photo: return "photo"
        case .audio: return "mic"
        case .document: return "doc.fill"
        case .video: return "video.fill"
        }
    }

    private var tint: Color {
        switch thought.kind {
        case .text: return HiveTheme.cyan
        case .photo: return HiveTheme.green
        case .audio: return HiveTheme.purple
        case .document: return HiveTheme.amber
        case .video: return HiveTheme.red
        }
    }

    private var kindName: String {
        switch thought.kind {
        case .text: return String(localized: "文字念头")
        case .photo: return String(localized: "图片记忆")
        case .audio: return String(localized: "录音记忆")
        case .document: return String(localized: "文档记忆")
        case .video: return String(localized: "视频记忆")
        }
    }
}

#Preview {
    ThoughtDetailSheet(thought: PendingThought(content: "把手机版的脸先描出来看看", kind: .text))
        .environmentObject(ThoughtStore())
        .environmentObject(HiveConfig())
}
