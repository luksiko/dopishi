cask "dopishi" do
  version "1.5.9"
  sha256 "26d1447e2fd70ab2a40a3e81b1bc0952da381c24198bb0e953a3b75bcbf7ef3c"

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
