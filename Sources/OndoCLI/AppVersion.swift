import Foundation

enum AppVersion {
    /// The version of the ondo.app this CLI ships in (Contents/Helpers/ondo), following a Homebrew symlink.
    /// "dev" for a build that is not inside an app.
    static var current: String {
        let executable = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
        let contents = executable.deletingLastPathComponent().deletingLastPathComponent()
        let plist = contents.appendingPathComponent("Info.plist")
        guard let info = NSDictionary(contentsOf: plist), let version = info["CFBundleShortVersionString"] as? String else { return "dev" }
        return version
    }
}
