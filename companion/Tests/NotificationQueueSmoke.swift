import AppKit
import Foundation

@main
struct NotificationQueueSmoke {
    @MainActor
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("doneguard-queue-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let events = root.appendingPathComponent("events")
        try FileManager.default.createDirectory(at: events, withIntermediateDirectories: true)
        func enqueue(_ id: String) throws -> URL {
            let bundle = root.appendingPathComponent("reports/temporary/\(id)")
            try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
            let report: [String: Any] = [
                "report_id": id, "project_name": "通知回归测试", "checked_at": "2026-09-07T09:00:00Z",
                "status": "success", "mode": "warn", "passed": [], "warnings": [], "blockers": [], "changed_paths": []
            ]
            let path = bundle.appendingPathComponent("report.json")
            try JSONSerialization.data(withJSONObject: report).write(to: path)
            try JSONSerialization.data(withJSONObject: [
                "report_id": id, "report_path": path.path, "delivery_token": "token-\(id)"
            ]).write(to: events.appendingPathComponent("\(id).json"))
            return path
        }
        func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
        let first = try enqueue("first")
        var store = ReportStore(dataDirectory: root, minimumDisplayTime: 0)
        store.poll()
        precondition(store.report?.reportID == "first")
        precondition(exists(events.appendingPathComponent("first.json")), "read must not consume event")
        store.acknowledgePresentation(isVisible: false)
        precondition(!exists(first.deletingLastPathComponent().appendingPathComponent("delivery.json")))
        // A process restart before presentation must replay the still-durable event.
        store = ReportStore(dataDirectory: root, minimumDisplayTime: 0)
        store.poll()
        precondition(store.report?.reportID == "first")
        store.acknowledgePresentation(isVisible: true)
        precondition(!exists(events.appendingPathComponent("first.json")))
        let receipt = try JSONSerialization.jsonObject(with: Data(contentsOf:
            first.deletingLastPathComponent().appendingPathComponent("delivery.json"))) as! [String: String]
        precondition(receipt["delivery_token"] == "token-first" && receipt["state"] == "presented")
        store.postpone()
        precondition(store.report == nil && store.reportPath == nil && exists(first))
        _ = try enqueue("second")
        store.poll()
        precondition(store.report?.reportID == "second", "postpone must release the queue")
        store.acknowledgePresentation(isVisible: true)
        _ = try enqueue("third")
        store.poll()
        precondition(store.report?.reportID == "third", "ignored banner must not block new reports")
        store.acknowledgePresentation(isVisible: true)
        store.showDetails()
        precondition(store.detailReport?.reportID == "third" && store.report == nil)
        _ = try enqueue("fourth")
        store.poll()
        precondition(store.report?.reportID == "fourth" && store.detailReport?.reportID == "third",
                     "reading details must not block or replace new banners")
        store.acknowledgePresentation(isVisible: true)
        store.finish()
        precondition(store.report?.reportID == "fourth" && store.detailReport == nil)
        store.postpone()
        let corrupt = events.appendingPathComponent("broken.json")
        try Data("broken".utf8).write(to: corrupt)
        store.poll()
        precondition(!exists(corrupt) && exists(events.appendingPathComponent("failed")))
        _ = try enqueue("fifth")
        store.poll()
        precondition(store.report?.reportID == "fifth", "corrupt event must not poison queue")
        print("Notification queue smoke passed: durable replay, visibility receipts, postpone, rotation, detail isolation, corrupt-event recovery")
    }
}
