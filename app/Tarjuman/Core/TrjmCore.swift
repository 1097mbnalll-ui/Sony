// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

enum TrjmCore {
    private static var started = false

    static func start() {
        guard !started else { return }
        started = true
        let rc = trjm_init({ level, msg, _ in
            guard let msg else { return }
            LogStore.shared.append(level: Int(level.rawValue), String(cString: msg))
        }, nil)
        if rc != 0 {
            LogStore.shared.error("chiaki init failed: \(errorString(rc))")
        } else {
            LogStore.shared.info("chiaki core ready")
        }
    }

    static func errorString(_ code: Int32) -> String {
        guard let s = trjm_error_string(code) else { return "error \(code)" }
        return String(cString: s)
    }
}
