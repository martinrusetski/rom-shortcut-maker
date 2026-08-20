cask "rom-shortcut-maker" do
  version "0.1.0"
  sha256 "1e8678a1c1cbc2dcd665fbf1dfc16d86c8b53b3c0783eeb4465baef951d11092"

  url "https://github.com/martinrusetski/rom-shortcut-maker/releases/download/v#{version}/RomShortcutMaker-v#{version}.dmg"
  name "Rom Shortcut Maker"
  desc "Generate native macOS launchers for your ROMs from installed emulators"
  homepage "https://github.com/martinrusetski/rom-shortcut-maker"

  depends_on macos: :tahoe

  app "Rom Shortcut Maker.app"

  postflight do
    system_command "/usr/bin/xattr", args: ["-cr", "#{appdir}/Rom Shortcut Maker.app"]
  end

  zap trash: [
    "~/Library/Application Support/RomShortcutMaker",
    "~/Library/Caches/com.romshortcutmaker.app",
    "~/Library/Preferences/com.romshortcutmaker.app.plist",
  ]
end
