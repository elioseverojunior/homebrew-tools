# homebrew-tools

Personal [Homebrew](https://brew.sh) tap for tools that aren't in `homebrew/core`.

## Install

```bash
brew tap elioseverojunior/tools
```

## Formulae

| Formula | Upstream | Description |
| --- | --- | --- |
| `tmq` | [azolfagharj/tmq](https://github.com/azolfagharj/tmq) | Command-line TOML processor — `jq` for TOML |
| `tgenv-manager` | [tgenv/tgenv](https://github.com/tgenv/tgenv) | Terragrunt version manager |

### tmq

A TOML processor in the spirit of `jq` (JSON) and `yq` (YAML).

```bash
brew install elioseverojunior/tools/tmq
```

```bash
# Query a nested key
tmq config.toml '.owner.name'

# Read from stdin
cat config.toml | tmq - '.title'
```

By default this installs the prebuilt release binary — no toolchain required.
Supported: macOS (arm64, x86_64) and Linux (arm64, x86_64).

#### Building tmq from source

Two source paths are available, both of which pull in `go` as a build-only
dependency:

```bash
# Compile the tagged release instead of using the upstream binary
brew install --with-source elioseverojunior/tools/tmq

# Compile the current main branch
brew install --HEAD elioseverojunior/tools/tmq
```

Prefer a source build if you want `tmq --version` to work. Upstream's release
workflow passes an empty `-X main.AZ_VERSION`, so the **published binaries
report a blank version**:

```console
$ tmq --version        # prebuilt (default)
Version:
Build Time:

$ tmq --version        # --with-source
Version: 1.0.3
Build Time: 2026-02-22
```

The formula injects the version itself when compiling, which is the only way to
get a version-reporting build today.

Note that `--with-source` still downloads the prebuilt binary (~2.6 MB) before
discarding it, because a spec's URL is fixed before options are applied. Use
`--HEAD` to skip that fetch entirely.

### tgenv-manager

Manages multiple Terragrunt versions.

```bash
brew install elioseverojunior/tools/tgenv-manager
```

It conflicts with `tenv` and `terragrunt`, since it symlinks Terragrunt
binaries into place. Currently pinned to upstream v1.2.1.

## Development

Formulae live under `Formula/<first-letter>/<name>.rb`, matching Homebrew's
sharded layout.

Homebrew 6 **refuses to load a formula from an arbitrary path** — `brew info
./Formula/t/tmq.rb` fails with "Homebrew requires formulae to be in a tap". Work
against the tapped clone instead:

```bash
cd "$(brew --repository)/Library/Taps/elioseverojunior/homebrew-tools"
```

Before committing, a formula should pass all three of these:

```bash
brew audit --strict --online elioseverojunior/tools/<formula>
brew install elioseverojunior/tools/<formula>
brew test elioseverojunior/tools/<formula>
```

A few things worth knowing:

- The first `brew audit` run bootstraps ~35 RuboCop gems. It is slow once, then
  fast; let it finish rather than interrupting it.
- Component order is enforced mechanically. The canonical sequence is
  `livecheck` → `head` block → `option` → `depends_on` → `on_macos`/`on_linux`
  → `resource` → `install`, which means the `on_*` blocks holding download URLs
  come *after* the dependency declarations.
- `livecheck` should use `url :stable` rather than a hardcoded repository URL.
- `std_go_args` already supplies `-s -w`, and deliberately drops them under
  `--debug-symbols`. Passing them again by hand duplicates the flags and breaks
  debug builds.
- Options such as `--with-source` are not permitted in `homebrew/core`, but are
  still supported in third-party taps.

After pushing, refresh the tap before installing:

```bash
brew update
```

## License

Formulae are packaging metadata only; each tool is covered by its own upstream
license.
