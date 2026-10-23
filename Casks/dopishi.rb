cask "dopishi" do
  version "1.5.1"
  sha256 "70d82e6d644b187c47b625b4a377830777f801a1411a71ca3e3c4eed430dbc3a"

  url "https://github.com/luksiko/dopishi/releases/download/v#{version}/Dopishi-#{version}-universal.dmg"
  name "Dopishi"
  desc "Smart keyboard layout switcher, inline auto-correction and text converter"
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
