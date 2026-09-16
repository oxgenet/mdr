# Homebrew Cask for the macOS app bundle. NOT PUBLISHED YET.
#
# Casks that fail Gatekeeper are no longer supported (Homebrew/brew#20755,
# effective 2026-09-01) and `--no-quarantine` was removed in brew 4.7, so this
# cask only becomes usable once release.yml signs with a Developer ID and
# notarizes — see PACKAGING.md, "Signing". Until then, ship the .dmg/.zip and
# the documented `xattr -dr com.apple.quarantine` step.
#
# The `mdr` formula (mdr.rb) installs the CLI binary and is unaffected.
#
# version/sha256 below are pinned to 0.4.0 as a worked example; refresh both
# from the release being published before this is ever used.
cask "mdr-app" do
  version "0.4.0"
  sha256 "76cb0f975509b9a06795d202b2ee6287e3251a4ec51390ef5db265d3cb716d79"

  url "https://github.com/oxgenet/mdr/releases/download/v#{version}/Mdr-#{version}-macos-universal.zip",
      verified: "github.com/oxgenet/mdr/"
  name "Mdr"
  desc "Markdown viewer/editor with Mermaid and CJK-aware rendering"
  homepage "https://github.com/oxgenet/mdr"

  depends_on macos: ">= :catalina"
  conflicts_with formula: "mdr"

  app "Mdr.app"
  # Same binary the formula installs, reached from inside the bundle so the app
  # and the CLI can never drift apart.
  binary "#{appdir}/Mdr.app/Contents/MacOS/mdr"

  zap trash: [
    "~/.config/mdr",
    "~/Library/Saved Application State/net.oxge.mdr.savedState",
  ]
end
