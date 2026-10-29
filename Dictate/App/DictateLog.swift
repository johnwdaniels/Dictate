import Foundation
import os

/// Connection and audio events for troubleshooting, readable in Console.app or with
/// `/usr/bin/log show --last 10m --info --predicate 'subsystem == "com.johndaniels.Dictate"'`.
/// Entries never include the API key or transcript text.
enum DictateLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.johndaniels.Dictate"

    static let connection = Logger(subsystem: subsystem, category: "connection")
    static let audio = Logger(subsystem: subsystem, category: "audio")
}
