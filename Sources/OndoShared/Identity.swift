import Foundation
import Security

/// Names shared by the app, the privileged helper and the CLI.
public enum Identity {
    public static let appBundleID = "dev.torylabs.ondo"
    public static let helperID = "dev.torylabs.ondo.helper"
    /// The helper's launchd plist inside Contents/Library/LaunchDaemons.
    public static let helperPlistName = "\(helperID).plist"
    public static let website = URL(string: "https://torylabs.dev/ondo")!

    /// Folder for the control socket: ~/Library/Application Support/dev.torylabs.ondo
    public static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(appBundleID)", isDirectory: true)
    }

    /// The team ID this process is signed with, or nil when it is unsigned or ad-hoc signed.
    public static func ownTeamID() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let info = info as? [String: Any] else { return nil }
        return info[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// A code requirement matching `identifier` signed by the same team as this process.
    /// Nil when this process has no team ID: then nothing is trusted.
    public static func sameTeamRequirement(identifier: String) -> String? {
        guard let team = ownTeamID() else { return nil }
        return "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
    }
}
