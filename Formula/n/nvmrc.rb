# Generated from packaging/homebrew/nvmrc.rb.in by `mise run homebrew:render`.
# Edit the template, not this file.
class Nvmrc < Formula
  desc "Native Rust port of nvm, the Node Version Manager"
  homepage "https://github.com/elioseverojunior/nvmrc"
  license "MIT"

  livecheck do
    url :stable
    strategy :github_latest
  end

  # Each archive holds nvmrc, nvm (the same program under nvm's name) and
  # nvm-exec. Linux uses the static musl builds, which run on any distribution.
  on_macos do
    on_arm do
      url "https://github.com/elioseverojunior/nvmrc/releases/download/v0.0.1/nvmrc-0.0.1-aarch64-apple-darwin.tar.gz"
      sha256 "98b74709ef973d3f22cee2f17beefbd9d9298993a11f45071c4b653c705f3647"
    end

    on_intel do
      url "https://github.com/elioseverojunior/nvmrc/releases/download/v0.0.1/nvmrc-0.0.1-x86_64-apple-darwin.tar.gz"
      sha256 "16e52af5c2958e6507e3a3637e174cb733ded41e8d1dfefcaf012c7d6544c07c"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/elioseverojunior/nvmrc/releases/download/v0.0.1/nvmrc-0.0.1-aarch64-unknown-linux-musl.tar.gz"
      sha256 "f6ff1fa04df949c8e0844963f4c3c538e63498ff906d648505b6219a1439276f"
    end

    on_intel do
      url "https://github.com/elioseverojunior/nvmrc/releases/download/v0.0.1/nvmrc-0.0.1-x86_64-unknown-linux-musl.tar.gz"
      sha256 "5f1145c2f603c5f08b9d495632e83be1d73c9860db0dc011484ca5668b607212"
    end
  end

  def install
    bin.install "nvmrc", "nvm", "nvm-exec"
  end

  test do
    assert_equal "nvm #{version}", shell_output("#{bin}/nvmrc --version").strip

    # An alias is plain state under $NVM_DIR, so this exercises the real
    # command path without touching the network.
    ENV["NVM_DIR"] = testpath
    system bin/"nvm", "alias", "homebrew", "20.1.0"
    assert_equal "20.1.0", (testpath/"alias/homebrew").read.strip
  end
end
