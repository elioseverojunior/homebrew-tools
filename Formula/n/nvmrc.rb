# Generated from packaging/homebrew/nvmrc.rb.in by `mise run homebrew:render`.
# Edit the template, not this file.
class Nvmrc < Formula
  desc "Native Rust port of nvm, the Node Version Manager"
  homepage "https://github.com/elioseverojunior/nvmrc"
  url "https://github.com/elioseverojunior/nvmrc/archive/refs/tags/v0.0.1.tar.gz"
  sha256 "08f3fba9894b3f1a4981d7ec98de57c4ac9203ca24059c2bb23cf4f487842d34"
  license "MIT"
  head "https://github.com/elioseverojunior/nvmrc.git", branch: "main"

  livecheck do
    url :stable
    strategy :github_latest
  end

  depends_on "rust" => :build

  def install
    # The repository's .cargo/config.toml denies warnings for its own CI; a
    # newer rustc lint must not fail an install, so warnings stay warnings.
    # RUSTFLAGS replaces that list; the release profile there still applies.
    ENV["RUSTFLAGS"] = "--cap-lints=warn"
    # One package, three binaries: nvmrc, nvm (the same program under nvm's
    # name) and nvm-exec.
    system "cargo", "install", *std_cargo_args
  end

  test do
    # A --HEAD build reports the version in Cargo.toml, not Homebrew's HEAD-<sha>.
    expected = version.head? ? /\Anvm \d+\.\d+\.\d+/ : /\Anvm #{Regexp.escape(version.to_s)}\z/
    assert_match expected, shell_output("#{bin}/nvmrc --version").strip
    assert_path_exists bin/"nvm-exec"

    # An alias is plain state under $NVM_DIR, so this exercises the real
    # command path without touching the network.
    ENV["NVM_DIR"] = testpath
    system bin/"nvm", "alias", "homebrew", "20.1.0"
    assert_equal "20.1.0", (testpath/"alias/homebrew").read.strip
  end
end
