import AppKit
import SwiftUI

extension Notification.Name {
    static let donebaraShowCompact = Notification.Name("DonebaraShowCompact")
    static let donebaraShowDetails = Notification.Name("DonebaraShowDetails")
    static let donebaraHide = Notification.Name("DonebaraHide")
    static let donebaraHideDetails = Notification.Name("DonebaraHideDetails")
}

struct DisplayCheck: Codable, Equatable, Identifiable {
    let title: String
    let status: String
    let detail: String

    var id: String { title }
}

struct DisplayFinding: Codable, Equatable, Identifiable {
    let title: String
    let detail: String
    let nextStep: String
    let technicalDetail: String

    var id: String { title + technicalDetail }

    enum CodingKeys: String, CodingKey {
        case title
        case detail
        case nextStep = "next_step"
        case technicalDetail = "technical_detail"
    }
}

struct ReportDisplay: Codable, Equatable {
    let headline: String
    let summary: String
    let modeLabel: String
    let checks: [DisplayCheck]
    let blockers: [DisplayFinding]
    let warnings: [DisplayFinding]
    let passed: [DisplayFinding]
    let filesSummary: String

    enum CodingKeys: String, CodingKey {
        case headline
        case summary
        case modeLabel = "mode_label"
        case checks
        case blockers
        case warnings
        case passed
        case filesSummary = "files_summary"
    }
}

struct VerificationEvidence: Codable, Equatable, Identifiable {
    let kind: String?
    let command: String?
    let cwd: String?
    let scopeRoot: String?
    let exitCode: Int?
    let success: Bool?
    let recordedAt: String?
    let workspaceFingerprint: String?

    var id: String { (command ?? "") + (recordedAt ?? "") + (workspaceFingerprint ?? "") }

    enum CodingKeys: String, CodingKey {
        case kind
        case command
        case cwd
        case scopeRoot = "scope_root"
        case exitCode = "exit_code"
        case success
        case recordedAt = "recorded_at"
        case workspaceFingerprint = "workspace_fingerprint"
    }
}

struct CompletionReport: Codable, Identifiable, Equatable {
    let reportID: String
    let threadID: String?
    let hostID: String?
    let cwd: String?
    let projectName: String
    let checkedAt: String
    let status: String
    let mode: String
    let passed: [String]
    let warnings: [String]
    let blockers: [String]
    let changedPaths: [String]
    let taskSummary: String?
    let userPrompt: String?
    let promptTruncated: Bool?
    let verificationEvidence: [VerificationEvidence]?
    let display: ReportDisplay?

    var id: String { reportID }

    enum CodingKeys: String, CodingKey {
        case reportID = "report_id"
        case threadID = "thread_id"
        case hostID = "host_id"
        case cwd
        case projectName = "project_name"
        case checkedAt = "checked_at"
        case status
        case mode
        case passed
        case warnings
        case blockers
        case changedPaths = "changed_paths"
        case taskSummary = "task_summary"
        case userPrompt = "user_prompt"
        case promptTruncated = "prompt_truncated"
        case verificationEvidence = "verification_evidence"
        case display
    }

    var headline: String {
        if let display { return display.headline }
        if !blockers.isEmpty { return "暂时还不能确认任务已完成" }
        if !warnings.isEmpty { return "任务已有完成证据，但还有提醒" }
        return "任务已完成检查"
    }

    var plainSummary: String {
        if let display { return display.summary }
        if !blockers.isEmpty { return "发现 \(blockers.count) 个需要处理的问题。打开报告可以查看原因和建议。" }
        if !warnings.isEmpty { return "没有发现阻断问题，同时有 \(warnings.count) 项内容建议你确认。" }
        return "没有发现需要阻止交付的问题。"
    }

    var modeLabel: String {
        if let display { return display.modeLabel }
        switch mode {
        case "strict": return "严格模式（证据不足时会让 Codex 再检查一次）"
        case "observe": return "观察模式（只记录，不弹出提醒）"
        default: return "提醒模式（只提示，不阻止任务结束）"
        }
    }

    var checkedAtLabel: String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = parser.date(from: checkedAt)
        if date == nil {
            parser.formatOptions = [.withInternetDateTime]
            date = parser.date(from: checkedAt)
        }
        guard let date else { return checkedAt }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter.string(from: date)
    }

    private func legacyFindings(_ values: [String], category: String) -> [DisplayFinding] {
        values.enumerated().map { index, value in
            let title: String
            let detail: String
            let nextStep: String
            switch category {
            case "blocker":
                title = "问题 \(index + 1) 需要处理"
                detail = "这项检查没有满足当前项目的完成要求。"
                nextStep = "请把技术详情交给 Codex 或开发者处理，然后重新检查。"
            case "warning":
                title = "提醒 \(index + 1)"
                detail = "这项内容不会阻止任务结束，但建议交付前确认。"
                nextStep = "如果不确定是否有影响，可以请 Codex 进一步检查。"
            default:
                title = "已确认项目 \(index + 1)"
                detail = "Donebara 找到了支持任务完成的检查证据。"
                nextStep = ""
            }
            return DisplayFinding(title: title, detail: detail, nextStep: nextStep, technicalDetail: value)
        }
    }

    var displayBlockers: [DisplayFinding] { display?.blockers ?? legacyFindings(blockers, category: "blocker") }
    var displayWarnings: [DisplayFinding] { display?.warnings ?? legacyFindings(warnings, category: "warning") }
    var displayPassed: [DisplayFinding] { display?.passed ?? legacyFindings(passed, category: "passed") }
}

struct ReportEvent: Codable {
    let reportID: String
    let reportPath: String
    let deliveryToken: String?

    enum CodingKeys: String, CodingKey {
        case reportID = "report_id"
        case reportPath = "report_path"
        case deliveryToken = "delivery_token"
    }
}

enum ReportStorage {
    static func discard(reportPath: URL, dataDirectory: URL) throws {
        let bundle = reportPath.deletingLastPathComponent().standardizedFileURL
        let temporaryRoot = dataDirectory
            .appendingPathComponent("reports/temporary", isDirectory: true)
            .standardizedFileURL.path + "/"
        guard bundle.path.hasPrefix(temporaryRoot) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        if FileManager.default.fileExists(atPath: bundle.path) {
            try FileManager.default.removeItem(at: bundle)
        }
    }
}

@MainActor
final class ReportStore: ObservableObject {
    @Published var report: CompletionReport?
    @Published var detailReport: CompletionReport?
    @Published var errorMessage: String?

    private(set) var reportPath: URL?
    private(set) var detailReportPath: URL?
    private var eventURL: URL?
    private var deliveryToken: String?
    private(set) var presentedAt: Date?
    let dataDirectory: URL
    let minimumDisplayTime: TimeInterval

    init(dataDirectory: URL? = nil, minimumDisplayTime: TimeInterval = 6) {
        self.minimumDisplayTime = minimumDisplayTime
        let arguments = CommandLine.arguments
        if let dataDirectory {
            self.dataDirectory = dataDirectory
        } else if let flag = arguments.firstIndex(of: "--data-dir"), arguments.indices.contains(flag + 1) {
            self.dataDirectory = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
        } else if let configured = ProcessInfo.processInfo.environment["PLUGIN_DATA"], !configured.isEmpty {
            self.dataDirectory = URL(fileURLWithPath: configured, isDirectory: true)
        } else {
            self.dataDirectory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex/doneguard-data", isDirectory: true)
        }
    }

    func poll() {
        if report != nil {
            guard let presentedAt else {
                // A hidden window or failed receipt must be retried, not dropped.
                NotificationCenter.default.post(name: .donebaraShowCompact, object: nil)
                return
            }
            if Date().timeIntervalSince(presentedAt) < minimumDisplayTime { return }
        }
        let events = dataDirectory.appendingPathComponent("events", isDirectory: true)
        guard let candidates = try? FileManager.default.contentsOfDirectory(
            at: events,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let ordered = candidates
            .filter { $0.pathExtension == "json" }
            .sorted {
                let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left < right
            }
        guard let eventURL = ordered.first else { return }

        do {
            let event = try JSONDecoder().decode(ReportEvent.self, from: Data(contentsOf: eventURL))
            let candidate = URL(fileURLWithPath: event.reportPath)
            let temporaryRoot = dataDirectory
                .appendingPathComponent("reports/temporary", isDirectory: true)
                .standardizedFileURL.path + "/"
            guard candidate.resolvingSymlinksInPath().path.hasPrefix(
                URL(fileURLWithPath: temporaryRoot).resolvingSymlinksInPath().path + "/"
            ) else {
                throw CocoaError(.fileReadNoPermission)
            }
            let decoded = try JSONDecoder().decode(CompletionReport.self, from: Data(contentsOf: candidate))
            guard decoded.reportID == event.reportID else {
                throw CocoaError(.fileReadCorruptFile)
            }
            self.eventURL = eventURL
            deliveryToken = event.deliveryToken
            presentedAt = nil
            reportPath = candidate
            report = decoded
            errorMessage = nil
            NotificationCenter.default.post(name: .donebaraShowCompact, object: nil)
        } catch {
            errorMessage = "报告暂时无法打开：\(error.localizedDescription)"
            // Keep corrupt events for diagnosis, but never let one poison the queue.
            let failed = events.appendingPathComponent("failed", isDirectory: true)
            try? FileManager.default.createDirectory(at: failed, withIntermediateDirectories: true)
            try? FileManager.default.moveItem(at: eventURL, to: failed.appendingPathComponent(UUID().uuidString + ".json"))
            NotificationCenter.default.post(name: .donebaraShowCompact, object: nil)
        }
    }

    func acknowledgePresentation(isVisible: Bool) {
        guard isVisible, presentedAt == nil, let report, let reportPath, let eventURL else { return }
        do {
            let receipt: [String: String] = [
                "report_id": report.reportID,
                "delivery_token": deliveryToken ?? "legacy",
                "state": "presented",
                "presented_at": ISO8601DateFormatter().string(from: Date())
            ]
            try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys])
                .write(to: reportPath.deletingLastPathComponent().appendingPathComponent("delivery.json"), options: .atomic)
            // Persist the receipt BEFORE consuming the durable event.
            if FileManager.default.fileExists(atPath: eventURL.path) {
                let current = try JSONDecoder().decode(ReportEvent.self, from: Data(contentsOf: eventURL))
                if current.reportID == report.reportID && current.deliveryToken == deliveryToken {
                    try FileManager.default.removeItem(at: eventURL)
                }
            }
            presentedAt = Date()
            self.eventURL = nil
        } catch {
            NSLog("Donebara presentation receipt failed: %@", error.localizedDescription)
        }
    }

    func showDetails() {
        guard let report, let reportPath else { return }
        detailReport = report
        detailReportPath = reportPath
        clearCompact()
        NotificationCenter.default.post(name: .donebaraShowDetails, object: nil)
    }

    func showSummary() {
        // The detail snapshot is independent, so new reports can keep arriving.
        finish()
    }

    func saveReport() {
        guard let report = detailReport, let reportPath = detailReportPath else { return }
        let source = reportPath.deletingLastPathComponent()
        let savedRoot = dataDirectory.appendingPathComponent("reports/saved", isDirectory: true)
        let destination = savedRoot.appendingPathComponent(report.reportID, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: savedRoot, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                errorMessage = "这份报告已经保存过了。"
                return
            }
            try FileManager.default.moveItem(at: source, to: destination)
            finish()
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    func discardReport() {
        let bundle = detailReportPath?.deletingLastPathComponent()
        NSLog("Donebara discard requested for %@", bundle?.lastPathComponent ?? "missing-report")
        finish()

        guard let bundle else { return }
        do {
            try ReportStorage.discard(
                reportPath: bundle.appendingPathComponent("report.json"),
                dataDirectory: dataDirectory
            )
            NSLog("Donebara discarded temporary report %@", bundle.lastPathComponent)
        } catch {
            NSLog("Donebara could not discard temporary report: %@", error.localizedDescription)
            let alert = NSAlert()
            alert.messageText = "临时报告删除失败"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: "知道了")
            alert.runModal()
        }
    }

    func postpone() {
        // Retain the temporary bundle, but release the display slot immediately.
        clearCompact()
    }

    private func clearCompact() {
        report = nil
        reportPath = nil
        eventURL = nil
        deliveryToken = nil
        presentedAt = nil
        errorMessage = nil
        NotificationCenter.default.post(name: .donebaraHide, object: nil)
    }

    func finish() {
        detailReport = nil
        detailReportPath = nil
        errorMessage = nil
        NotificationCenter.default.post(name: .donebaraHideDetails, object: nil)
    }
}

struct MascotImage: View {
    let status: String

    var body: some View {
        let name = status == "success" ? "mascot-success" : "mascot-issue"
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: status == "success" ? "checkmark.seal.fill" : "magnifyingglass.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(status == "success" ? Color.green : Color.orange)
                .padding(40)
        }
    }
}

struct SummaryView: View {
    let report: CompletionReport
    let showDetails: () -> Void
    let postpone: () -> Void

    private var accent: Color {
        report.status == "success" ? Color(red: 0.12, green: 0.55, blue: 0.43) : Color(red: 0.86, green: 0.47, blue: 0.10)
    }

    var body: some View {
        HStack(spacing: 10) {
            MascotImage(status: report.status)
                .frame(width: 66, height: 88)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Circle().fill(accent).frame(width: 7, height: 7)
                    Text(report.projectName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                Text(report.headline)
                    .font(.system(size: 15.5, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text(report.plainSummary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Button("查看报告", action: showDetails)
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                        .controlSize(.small)
                        .font(.system(size: 12.5, weight: .semibold))
                    Spacer(minLength: 24)
                    Button("稍后", action: postpone)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(11)
        .frame(width: 368, height: 116)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        }
    }
}

struct TaskContextSection: View {
    let summary: String?
    let prompt: String?
    let promptTruncated: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("本次任务", systemImage: "text.bubble")
                .font(.headline)
                .foregroundStyle(.indigo)
            Text(summary?.isEmpty == false ? summary! : "本次任务（没有可用的用户 Prompt）")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let prompt, !prompt.isEmpty {
                DisclosureGroup(promptTruncated ? "查看原始 Prompt（已截断）" : "查看原始 Prompt") {
                    Text(prompt)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.indigo.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct VerificationEvidenceSection: View {
    let values: [VerificationEvidence]

    private func color(for value: VerificationEvidence) -> Color {
        if value.success == true { return .green }
        if value.success == false { return .red }
        return .orange
    }

    private func status(for value: VerificationEvidence) -> String {
        if value.success == true { return "通过" }
        if value.success == false { return "失败" }
        return "状态未知"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("验证命令", systemImage: "terminal")
                .font(.headline)
                .foregroundStyle(.teal)
            if values.isEmpty {
                Text("本次没有记录到验证命令。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(values) { value in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Circle().fill(color(for: value)).frame(width: 7, height: 7)
                            Text("\(value.kind ?? "verification") · \(status(for: value))")
                                .font(.subheadline.bold())
                            Spacer()
                            Text("退出码 \(value.exitCode.map(String.init) ?? "未知")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(value.command ?? "未知命令")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        EvidenceRow(label: "工作目录", value: value.cwd ?? value.scopeRoot ?? "未知")
                        EvidenceRow(label: "记录时间", value: value.recordedAt ?? "未知")
                        EvidenceRow(label: "代码指纹", value: value.workspaceFingerprint ?? "未知")
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(color(for: value))
                            .frame(width: 3)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct EvidenceRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct CheckOverview: View {
    let checks: [DisplayCheck]

    private func color(for status: String) -> Color {
        switch status {
        case "issue": return .red
        case "warning": return .orange
        case "passed": return .green
        default: return .secondary
        }
    }

    private func icon(for status: String) -> String {
        switch status {
        case "issue": return "xmark.circle.fill"
        case "warning": return "exclamationmark.triangle.fill"
        case "passed": return "checkmark.circle.fill"
        default: return "minus.circle.fill"
        }
    }

    var body: some View {
        if !checks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Donebara 检查了什么")
                    .font(.headline)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(checks) { check in
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: icon(for: check.status))
                                .foregroundStyle(color(for: check.status))
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(check.title).font(.subheadline.bold())
                                Text(check.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(color(for: check.status))
                                .frame(width: 3)
                        }
                    }
                }
            }
            .padding(16)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

struct FindingSection: View {
    let title: String
    let icon: String
    let color: Color
    let values: [DisplayFinding]

    var body: some View {
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundStyle(color)
                ForEach(values) { value in
                    HStack(alignment: .top, spacing: 9) {
                        Circle().fill(color).frame(width: 6, height: 6).padding(.top, 7)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(value.title).font(.subheadline.bold())
                            Text(value.detail)
                                .fixedSize(horizontal: false, vertical: true)
                            if !value.nextStep.isEmpty {
                                HStack(alignment: .top, spacing: 5) {
                                    Text("建议").font(.caption.bold()).foregroundStyle(color)
                                    Text(value.nextStep).font(.callout)
                                }
                            }
                            if !value.technicalDetail.isEmpty {
                                DisclosureGroup("查看技术详情") {
                                    Text(value.technicalDetail)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.top, 4)
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

struct FollowupResult: Decodable {
    let status: String
    let message: String
}

enum FollowupSender {
    static func send(report: CompletionReport, prompt: String, dataDirectory: URL) async -> FollowupResult {
        await Task.detached(priority: .userInitiated) {
            guard let helper = Bundle.main.url(forResource: "donebara_followup", withExtension: "py") else {
                return FollowupResult(status: "error", message: "发送组件尚未安装，请更新 Donebara。")
            }
            let process = Process()
            let input = Pipe()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = [helper.path, "--data-dir", dataDirectory.path]
            process.standardInput = input
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do {
                let reportObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(report))
                let payload = try JSONSerialization.data(withJSONObject: ["report": reportObject, "prompt": prompt])
                try process.run()
                try input.fileHandleForWriting.write(contentsOf: payload)
                try input.fileHandleForWriting.close()
                let result = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                return try JSONDecoder().decode(FollowupResult.self, from: result)
            } catch {
                return FollowupResult(status: process.processIdentifier == 0 ? "error" : "uncertain",
                    message: "发送未能确认，请查看原任务后再操作。")
            }
        }.value
    }
}

struct FollowupComposer: View {
    let report: CompletionReport
    let dataDirectory: URL
    @State private var prompt = ""
    @State private var sending = false
    @State private var result: FollowupResult?
    @State private var submittedPrompt: String?

    private var targetURL: URL? {
        guard report.hostID == "local", let id = report.threadID, UUID(uuidString: id) != nil else { return nil }
        return URL(string: "codex://threads/\(id)")
    }
    private var trimmedPrompt: String { prompt.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var alreadySubmitted: Bool {
        submittedPrompt == trimmedPrompt && (result?.status == "sent" || result?.status == "uncertain")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("让原任务继续处理", systemImage: "text.bubble").font(.headline)
                Spacer()
                if let url = targetURL {
                    Button("查看任务") { NSWorkspace.shared.open(url) }.buttonStyle(.link)
                }
            }
            if targetURL == nil {
                Text("这份旧报告没有准确的原任务标识，请在原任务重新生成报告后使用。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                TextField("例如：请检查测试失败的原因并修复", text: $prompt, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .disabled(sending)
                    .accessibilityLabel("给原任务的处理要求")
                HStack {
                    Text("会附上本报告的异常和验证结果")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if sending { ProgressView().controlSize(.small) }
                    Button(sending ? "正在发送…" : "发送到原任务并执行") {
                        let text = trimmedPrompt
                        sending = true
                        result = nil
                        submittedPrompt = text
                        Task {
                            result = await FollowupSender.send(report: report, prompt: text, dataDirectory: dataDirectory)
                            sending = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(sending || trimmedPrompt.isEmpty || trimmedPrompt.count > 8000 || alreadySubmitted)
                }
                if let result {
                    Text(result.message)
                        .font(.caption)
                        .foregroundStyle(result.status == "sent" ? Color.green : Color.orange)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.accentColor.opacity(0.06))
    }
}

struct DetailView: View {
    let report: CompletionReport
    let dataDirectory: URL
    let back: () -> Void
    let save: () -> Void
    let discard: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: back) { Label("返回", systemImage: "chevron.left") }
                    .buttonStyle(.plain)
                Spacer()
                Text("Donebara 完整报告").font(.headline)
                Spacer()
                Color.clear.frame(width: 48, height: 1)
            }
            .padding(18)
            .background(Color(nsColor: .controlBackgroundColor))

            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    HStack(spacing: 15) {
                        MascotImage(status: report.status).frame(width: 72, height: 72)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(report.projectName).font(.title2.bold())
                            Text("检查时间  \(report.checkedAtLabel)").font(.caption).foregroundStyle(.secondary)
                            Text(report.modeLabel).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        Text("检查结论").font(.caption.bold()).foregroundStyle(.secondary)
                        Text(report.headline).font(.title3.bold())
                        Text(report.plainSummary)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(17)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))

                    TaskContextSection(
                        summary: report.taskSummary,
                        prompt: report.userPrompt,
                        promptTruncated: report.promptTruncated ?? false
                    )
                    CheckOverview(checks: report.display?.checks ?? [])
                    VerificationEvidenceSection(values: report.verificationEvidence ?? [])
                    FindingSection(title: "为什么暂时不能确认完成", icon: "exclamationmark.octagon.fill", color: .red, values: report.displayBlockers)
                    FindingSection(title: "还有这些内容值得留意", icon: "exclamationmark.triangle.fill", color: .orange, values: report.displayWarnings)
                    FindingSection(title: "已经确认的内容", icon: "checkmark.seal.fill", color: .green, values: report.displayPassed)
                    VStack(alignment: .leading, spacing: 10) {
                        Label("本次检查涉及的文件", systemImage: "doc.on.doc")
                            .font(.headline)
                            .foregroundStyle(.blue)
                        Text(report.display?.filesSummary ?? (report.changedPaths.isEmpty ? "本次没有发现需要验证的项目改动。" : "本次共检查 \(report.changedPaths.count) 个相关文件。"))
                            .foregroundStyle(.secondary)
                        ForEach(report.changedPaths, id: \.self) { path in
                            Text(path)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                    Text("Donebara 提供的是完成证据，不等同于需求正确性或完整测试覆盖。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(24)
            }

            Divider()
            FollowupComposer(report: report, dataDirectory: dataDirectory)
                .id(report.reportID)
            Divider()
            HStack {
                Button(role: .destructive, action: discard) {
                    Label("关闭且不保存", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                Spacer()
                Text("只有点击保存，报告才会长期保留")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("保存报告", action: save)
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.12, green: 0.55, blue: 0.43))
            }
            .padding(18)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(width: 680, height: 720)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct ContentView: View {
    @ObservedObject var store: ReportStore
    var details = false

    var body: some View {
        Group {
            if details, let report = store.detailReport {
                    DetailView(
                        report: report,
                        dataDirectory: store.dataDirectory,
                        back: store.showSummary,
                        save: store.saveReport,
                        discard: store.discardReport
                    )
            } else if let report = store.report {
                    SummaryView(
                        report: report,
                        showDetails: store.showDetails,
                        postpone: store.postpone
                    )
            } else {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(store.errorMessage ?? "等待 Donebara 报告…")
                        .foregroundStyle(.secondary)
                }
                .frame(width: 368, height: 116)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .alert("Donebara", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("知道了") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = ReportStore()
    private var notificationPanel: NSPanel?
    private var detailWindow: NSWindow?
    private var poller: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 368, height: 116),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = NSHostingView(rootView: ContentView(store: store))
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.notificationPanel = panel

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showCompact),
            name: .donebaraShowCompact,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showDetails),
            name: .donebaraShowDetails,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hidePanel),
            name: .donebaraHide,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(hideDetails), name: .donebaraHideDetails, object: nil
        )
        // App-owned timer continues when every SwiftUI window is hidden/closed.
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        poller = timer
        store.poll()
        if store.report != nil || store.errorMessage != nil {
            if CommandLine.arguments.contains("--preview-details") && store.report != nil {
                store.showDetails()
            } else {
                showCompact()
            }
        }
    }

    @objc private func showCompact() {
        guard let panel = notificationPanel else { return }
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.setContentSize(NSSize(width: 368, height: 116))
        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first
        if let visible = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(
                x: visible.maxX - panel.frame.width - 18,
                y: visible.maxY - panel.frame.height - 18
            ))
        }
        NSApp.unhideWithoutActivation()
        panel.orderFrontRegardless()
        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.store.acknowledgePresentation(
                isVisible: panel.isVisible && panel.isOnActiveSpace && !NSApp.isHidden
            )
        }
    }

    @objc private func showDetails() {
        notificationPanel?.orderOut(nil)
        let window: NSWindow
        if let existing = detailWindow {
            window = existing
        } else {
            let created = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 720),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            created.contentView = NSHostingView(rootView: ContentView(store: store, details: true))
            created.delegate = self
            created.isReleasedWhenClosed = false
            created.titleVisibility = .hidden
            created.titlebarAppearsTransparent = true
            created.isMovableByWindowBackground = true
            created.backgroundColor = .windowBackgroundColor
            created.isOpaque = true
            created.hasShadow = true
            created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                created.standardWindowButton(kind)?.isHidden = true
            }
            detailWindow = created
            window = created
        }
        window.setContentSize(NSSize(width: 680, height: 720))
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func hidePanel() {
        notificationPanel?.orderOut(nil)
    }

    @objc private func hideDetails() {
        detailWindow?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === detailWindow { store.finish() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        store.poll()
        if store.report != nil { showCompact() }
        return false
    }
}

#if !DONEBARA_TESTING
@main
struct DonebaraCompanionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
#endif
