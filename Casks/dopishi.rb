cask "dopishi" do
  version "1.5.0"
  sha256 "33a344d4be7a36761766c25c27c4aabe7b623f842ee0988347617517a820d561"

  url "https://github.com/luksiko/dopishi/releases/download/v#{version}/Dopishi-#{version}-universal.dmg"
  name "Dopishi"
  desc "On-device AI writing copilot, typo & layout auto-corrector, and keyboard switcher"
  homepage "https://github.com/luksiko/dopishi"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :ventura

  app "Dopishi.app"

  uninstall quit: "com.dopishi.app"

  zap trash: [
    "~/Library/Application Support/Dopishi",
    "~/Library/Application Support/LangSwitcher",
    "~/Library/Caches/com.dopishi.app",
    "~/Library/Preferences/com.dopishi.app.plist",
  ]
end
