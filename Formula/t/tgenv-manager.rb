class TgenvManager < Formula
  desc "TGENV - Terragrunt Version Manager"
  homepage "https://github.com/tgenv/tgenv"
  url "https://github.com/tgenv/tgenv/archive/refs/tags/v1.3.0.tar.gz"
  sha256 "cccf0d5714cf1156aaa9f451d98601afa3e7bb0b104eda61013a9a8849bee2fb"
  license "MIT"
  head "https://github.com/tgenv/tgenv.git", branch: "main"

  livecheck do
    url :stable
    regex(/^v?(\d+(?:\.\d+)+)$/i)
  end

  uses_from_macos "unzip"

  conflicts_with "tgenv", because: "both install a tgenv executable"
  conflicts_with "tenv", because: "tgenv symlinks terragrunt binaries"
  conflicts_with "terragrunt", because: "tgenv symlinks terragrunt binaries"

  def install
    prefix.install %w[bin libexec]
  end

  test do
    assert_match "Usage: tgenv", shell_output("#{bin}/tgenv help")
  end
end
