# Homebrew formula for the oxgenet fork of mdr.
# Lives in the tap repository oxgenet/homebrew-tap as Formula/mdr.rb.
# Install:  brew install oxgenet/tap/mdr
# The release workflow regenerates this file with the real version and SHA256s.
class Mdr < Formula
  desc "Markdown viewer/editor with Mermaid and CJK-aware rendering (oxgenet fork of Clever Cloud's mdr)"
  homepage "https://github.com/oxgenet/mdr"
  version "0.4.0"
  license "MIT"

  # Not the same package as CleverCloud/misc/mdr: same binary name, different project.
  conflicts_with "mdr", because: "both install a `mdr` binary; this is the oxgenet fork"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/oxgenet/mdr/releases/download/v#{version}/mdr-aarch64-apple-darwin.tar.gz"
      sha256 "REPLACED_BY_CI_AARCH64"
    else
      url "https://github.com/oxgenet/mdr/releases/download/v#{version}/mdr-x86_64-apple-darwin.tar.gz"
      sha256 "REPLACED_BY_CI_X86_64"
    end
  end

  on_linux do
    url "https://github.com/oxgenet/mdr/releases/download/v#{version}/mdr-x86_64-unknown-linux-gnu.tar.gz"
    sha256 "REPLACED_BY_CI_LINUX"
    # Runtime libraries for the webview backend are taken from the system
    # (libwebkit2gtk-4.1, libgtk-3); install them with your distro's package manager.
  end

  def install
    bin.install "mdr"
    # Ship the license and fork notice with the package (MIT requires the notice).
    prefix.install "LICENSE" if File.exist?("LICENSE")
    prefix.install "NOTICE.md" if File.exist?("NOTICE.md")
  end

  def caveats
    <<~EOS
      This is the oxgenet fork of mdr (https://github.com/oxgenet/mdr), not the
      original Clever Cloud release. To use the original instead:
        brew uninstall oxgenet/tap/mdr && brew install CleverCloud/misc/mdr
    EOS
  end

  test do
    assert_match "mdr", shell_output("#{bin}/mdr --version")
  end
end
