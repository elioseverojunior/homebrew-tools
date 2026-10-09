# homebrew-tools

Personal [Homebrew](https://brew.sh) tap for tools that aren't in `homebrew/core`.

## Install

```bash
brew tap elioseverojunior/tools
```

## Formulae

- `tmq` — [azolfagharj/tmq](https://github.com/azolfagharj/tmq):
  command-line TOML processor, `jq` for TOML
- `tgenv-manager` — [tgenv/tgenv](https://github.com/tgenv/tgenv):
  Terragrunt version manager

## Casks

- `tflint` — [terraform-linters/tflint](https://github.com/terraform-linters/tflint):
  pluggable Terraform linter

```bash
brew install --cask elioseverojunior/tools/tflint
```

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
binaries into place. Currently pinned to upstream v1.3.0.

## Linux packages

Packages of `tmq` and `tflint` (deb, rpm, apk and archlinux, for amd64 and
arm64) are built by the `packages` workflow. On pushes to `main` that touch
the package inputs, and on manual runs, it attaches them to a GitHub release of
this repository named `<formula>-<version>` (for example `tmq-1.0.3`),
creating the release only if it does not exist yet. Pull requests build the
packages without publishing them.

Each package is made by `scripts/package.sh` with `nfpm` from the upstream
Linux release asset listed in the formula or cask. The script verifies the
asset's sha256 against the one recorded there before packaging. To build
locally:

```bash
mise run package <formula> <arch>   # arch: amd64 | arm64
```

The packages are written to `dist/`.

## Automated bumps

The `tests` workflow runs on pushes to `main` and on pull requests. It runs
`brew test-bot --only-tap-syntax` (style and audit), then installs and tests
`tmq` on Linux and macOS (Intel and Apple silicon), and installs the `tflint`
cask on macOS. Its `generated-files` job runs the offline generated-files check
(see "Generated files" below).

The `bump` workflow runs weekly (Mondays, 09:00 UTC) and on manual dispatch.
It has three jobs:

- `preflight` checks the token and the branch rules first (see below), so a
  misconfiguration fails early and clearly. The other two jobs need it.
- `bump` runs `brew bump --open-pr` for `tgenv-manager` only.
- `render-templates` regenerates `tmq` and `tflint` (see "Generated files")
  and opens one pull request per tool, from a `bump/<tool>-<version>` branch.

A manual run with `dry-run` enabled opens no pull requests: it only reports
what is outdated or would change.

### Secrets and variables

- `HOMEBREW_GITHUB_API_TOKEN` (secret, required): a personal access token
  with contents and pull-requests write access. Pull requests opened with the
  default `GITHUB_TOKEN` do not trigger the `tests` workflow, so a PAT is
  required.
- `BUMP_SIGNING_KEY` (secret, optional): a passphrase-less ed25519 private
  key. Register its public half as a *signing key* on the GitHub account that
  owns the PAT. When set, `render-templates` signs its commits with it.
- `BUMP_COMMIT_NAME` and `BUMP_COMMIT_EMAIL` (variables): the author of the
  signed commits. They are required when `BUMP_SIGNING_KEY` is set, and the
  email must be a verified email of the account that owns the PAT, or GitHub
  does not mark the commits as verified.

Without `BUMP_SIGNING_KEY` the `render-templates` commits are unsigned and
authored by `github-actions[bot]`, so squash-merge those pull requests: GitHub
then signs the merge commit. The pull request body says whether the commit is
signed.

### Preflight

The `preflight` job fails when:

- `HOMEBREW_GITHUB_API_TOKEN` is empty.
- The token has no push permission on this repository.
- A repository ruleset that applies to `bump/*` branches has a `creation` or
  an `update` rule, which blocks the bump branches.
- A repository ruleset that applies to `bump/*` branches has a
  `required_signatures` rule and `BUMP_SIGNING_KEY` is not set.

Only repository rulesets can be read this way. Classic branch protection
patterns need admin rights to read, so `preflight` cannot check them: make
sure none of them blocks `bump/*` branches.

### Generated files

`Formula/t/tmq.rb` and `Casks/tflint.rb` are generated from the templates in
`packaging/homebrew/*.rb.in`. Each generated file starts with a header saying
so. Do not edit them by hand: edit the template, then render it again:

```bash
mise run homebrew:render <tool> [version]   # tool: tmq | tflint
```

The version defaults to the latest upstream release. The task needs `gh` and
network access, because it downloads every release asset to hash it.

- `tmq`: upstream publishes no checksums, so the hashes are computed from the
  downloaded binaries (trust on first download). The bump pull request warns
  about this; verify the hashes before merging.
- `tflint`: the hashes are cross-checked against the upstream release's
  `checksums.txt`.
- The offline check (`mise run homebrew:check`, run by the `generated-files`
  job of the `tests` workflow and by `mise run lint`) fails when a generated
  file differs from its template. It reads the version and the sha256 values
  from the generated file itself, so it catches any other hand edit but not a
  changed hash or version.
- The online check (`mise run homebrew:check --online`) also catches those. It
  takes the version of the generated file, downloads and hashes exactly that
  release (for `tflint` the hashes must equal upstream's `checksums.txt`),
  re-renders from what upstream publishes and fails on any difference. That
  includes an upstream re-upload of an already released asset.
- The `verify-generated` workflow runs the online check on pull requests and
  pushes to `main` that touch the generated files, the templates or the render
  script, weekly (Mondays, 06:00 UTC) and on manual dispatch. The weekly run
  is the one that catches a re-upload.
- Hashes and versions are what a bump rewrites, so `homebrew:render` is the
  only way to change them.
- `tgenv-manager` is not generated; `brew bump` updates it directly.

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
