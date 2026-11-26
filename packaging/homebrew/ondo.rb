# Draft for the su-record/homebrew-tap repository (Casks/ondo.rb).
# The same file can go to homebrew/cask once the repository meets Homebrew's notability rules.
# After `scripts/make-dmg.sh`, set version and sha256 from its output and upload the DMG to the GitHub release.
cask "ondo" do
  version "0.1.0"
  sha256 "2001d8bf77ed0172221c8b19bf9f04dc45e2d228945d0f24da3a01155461fcc8"

  url "https://github.com/su-record/ondo/releases/download/v#{version}/ondo-#{version}.dmg"
  name "ondo"
  desc "Keep a closed MacBook awake, with overheat and power protection"
  homepage "https://torylabs.dev/ondo"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :ventura"

  app "ondo.app"
  binary "#{appdir}/ondo.app/Contents/Helpers/ondo"

  # The helper is a LaunchDaemon registered through SMAppService; removing it in ondo's settings
  # before uninstalling is the clean path, and this unloads it if that was skipped.
  uninstall quit:      "dev.torylabs.ondo",
            launchctl: "dev.torylabs.ondo.helper"

  zap trash: [
    "~/Library/Application Support/dev.torylabs.ondo",
    "~/Library/Preferences/dev.torylabs.ondo.plist",
  ]
end
