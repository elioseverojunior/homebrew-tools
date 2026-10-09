# Generated from packaging/homebrew/tmq.rb.in by `mise run homebrew:render`.
# Edit the template, not this file.
class Tmq < Formula
  desc "Lightweight command-line TOML processor, like jq for JSON and yq for YAML"
  homepage "https://tomlq.ir"
  license "MIT"

  # Upstream tags releases without a "v" prefix (1.0.3, not v1.0.3).
  livecheck do
    url :stable
    strategy :github_latest
    regex(/^v?(\d+(?:\.\d+)+)$/i)
  end

  head do
    url "https://github.com/azolfagharj/tmq.git", branch: "main"

    depends_on "go" => :build
  end

  # `brew install --with-source elioseverojunior/tools/tmq` compiles the tagged
  # source instead of using the upstream binary. Homebrew still fetches the
  # binary for the stable spec first (~2.6MB), because a spec's URL is fixed
  # before options are applied; use --HEAD to skip that fetch entirely.
  option "with-source", "Build from the tagged Go source instead of the prebuilt binary"

  depends_on "go" => :build if build.with?("source")

  # Default install path: the prebuilt release binaries. Homebrew stages a bare
  # (non-archive) download under its URL basename, so `install` recovers the
  # filename from the URL rather than repeating the arch mapping.
  on_macos do
    on_arm do
      url "https://github.com/azolfagharj/tmq/releases/download/1.0.3/tmq-darwin-arm64"
      sha256 "843b30ca5380f4abdd2f5333bd977ecaba5a9be87d7b3d040e667aa6b982f73b"
    end

    on_intel do
      url "https://github.com/azolfagharj/tmq/releases/download/1.0.3/tmq-darwin-amd64"
      sha256 "69ad4b9fc1496644fb8ba0bce865fd6ce354b5be09185c300427bbac80cd9e13"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/azolfagharj/tmq/releases/download/1.0.3/tmq-linux-arm64"
      sha256 "5b5fb8dd92e9fb52de0695a0b20d928ceda65e2e360bd5a074d3df635f95f84c"
    end

    on_intel do
      url "https://github.com/azolfagharj/tmq/releases/download/1.0.3/tmq-linux-amd64"
      sha256 "754a69ec176900d8aa350419dd209011ff99c86f1d0b7c981efca38b0b50c877"
    end
  end

  resource "source" do
    url "https://github.com/azolfagharj/tmq/archive/refs/tags/1.0.3.tar.gz"
    sha256 "40c19c0203cfefe9a85f44408b7441fd06c1f24e7d5f1d044f6c8b44dd2ff691"
  end

  def install
    if build.head?
      compile_binary
    elsif build.with?("source")
      resource("source").stage { compile_binary }
    else
      bin.install File.basename(stable.url) => "tmq"
    end
  end

  # Upstream's release workflow passes an empty -X main.AZ_VERSION, so published
  # binaries report a blank version. Injecting it here means a source build
  # reports a real one, unlike the prebuilt default.
  #
  # std_go_args already prepends "-s -w" and drops them under --debug-symbols,
  # so only the version flag belongs here.
  def compile_binary
    system "go", "build", *std_go_args(ldflags: "-X main.AZ_VERSION=#{version}"), "./cmd/tmq"
  end
  private :compile_binary

  test do
    (testpath/"config.toml").write <<~TOML
      title = "tmq"

      [owner]
      name = "homebrew"
    TOML

    # tmq rejects absolute paths under /var, /etc, /usr, ... and Homebrew's test
    # directory is under /var on Linux, so pass the path relative to testpath
    # (the test runs with it as the working directory).
    assert_equal "homebrew",
      shell_output("#{bin}/tmq config.toml '.owner.name'").strip

    assert_equal "tmq",
      pipe_output("#{bin}/tmq - '.title'", (testpath/"config.toml").read).strip
  end
end
