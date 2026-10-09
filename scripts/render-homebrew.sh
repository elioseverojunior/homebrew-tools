#!/usr/bin/env bash
# Render the Homebrew formula/cask of a tap tool from packaging/homebrew/.
# Usage: scripts/render-homebrew.sh <tmq|tflint> [<version>]
#        scripts/render-homebrew.sh --check <tmq|tflint>
#        scripts/render-homebrew.sh --verify <tmq|tflint>
# --check is offline and read-only: it re-renders the template with the version
# and sha256 values read from the committed generated file and exits 1 with a
# unified diff when the result differs.
# --verify needs the network and is read-only: it takes the version of the
# committed generated file, downloads and hashes exactly that release (tflint
# hashes must equal upstream's checksums.txt), renders into a temporary file and
# exits 1 with a unified diff when the result differs from the committed file.
# The version defaults to the latest upstream release. Every release asset is
# downloaded into a temporary directory and only ever hashed, never executed or
# unpacked. stdout carries one "<placeholder> <sha256> <source>" line per asset
# and a final "version <v>" line; all progress goes to stderr.
#   source "checksums.txt": the hash was verified against upstream's checksum
#   source "downloaded":    upstream publishes none, so the hash is trust on
#                           first download.
set -Eeuo pipefail

readonly PLATFORMS=(darwin-arm64 darwin-amd64 linux-arm64 linux-amd64)

# Globals so the EXIT trap can still see them after main returns.
work_dir=""
temp_target=""

die() {
  echo "render-homebrew.sh: $*" >&2
  exit 1
}

log() {
  echo "render-homebrew.sh: $*" >&2
}

cleanup() {
  [[ -z "${work_dir}" ]] || rm -rf "${work_dir}"
  [[ -z "${temp_target}" ]] || rm -f "${temp_target}"
}

repo_for() {
  case "$1" in
    tmq) echo "azolfagharj/tmq" ;;
    tflint) echo "terraform-linters/tflint" ;;
    *) die "unknown tool '$1' (expected tmq or tflint)" ;;
  esac
}

# tmq tags carry no "v" prefix, tflint tags do.
tag_for() {
  case "$1" in
    tmq) echo "$2" ;;
    tflint) echo "v$2" ;;
    *) die "unknown tool '$1'" ;;
  esac
}

target_for() {
  case "$1" in
    tmq) echo "Formula/t/tmq.rb" ;;
    tflint) echo "Casks/tflint.rb" ;;
    *) die "unknown tool '$1'" ;;
  esac
}

# Print the release asset file name of <tool> for <platform> (os-arch).
asset_file() {
  local tool="$1" platform="$2"
  case "${tool}" in
    tmq) echo "tmq-${platform}" ;;
    tflint) echo "tflint_${platform/-/_}.zip" ;;
    *) die "unknown tool '${tool}'" ;;
  esac
}

asset_url() {
  local tool="$1" version="$2" file="$3" repo tag
  repo="$(repo_for "${tool}")"
  tag="$(tag_for "${tool}" "${version}")"
  echo "https://github.com/${repo}/releases/download/${tag}/${file}"
}

# Print the latest upstream release version without its leading "v".
latest_version() {
  local repo tag
  repo="$(repo_for "$1")"
  tag="$(gh api "repos/${repo}/releases/latest" --jq .tag_name)"
  [[ -n "${tag}" ]] || die "could not resolve the latest release of $1"
  echo "${tag#v}"
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1
  then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# Download <url> into the work directory and print its path.
download() {
  local url="$1" target
  [[ "${url}" == https://* ]] || die "refusing non-https url ${url}"
  target="${work_dir}/$(basename "${url}")"
  log "downloading ${url}"
  curl --fail --silent --show-error --location --proto '=https' --output "${target}" "${url}" ||
    die "download failed: ${url}"
  echo "${target}"
}

# Print the sha256 listed for <file> in a checksums.txt; exactly one is required.
expected_hash_from_checksums() {
  local checksums="$1" file="$2" matches count
  matches="$(awk -v name="${file}" '$2 == name || $2 == "*" name { print $1 }' "${checksums}")"
  count="$(grep -c . <<<"${matches}" || true)"
  [[ "${count}" -eq 1 ]] || die "need exactly one checksum for ${file}"
  [[ "${matches}" =~ ^[0-9a-f]{64}$ ]] || die "malformed checksum '${matches}' for ${file}"
  echo "${matches}"
}

# Export <placeholder>=<hash> and print the "<placeholder> <hash> <source>" line.
record_hash() {
  local placeholder="$1" hash="$2" source="$3"
  export "${placeholder}=${hash}"
  echo "${placeholder} ${hash} ${source}"
}

# Hash the tmq source tarball (the formula builds from it).
collect_source_hash() {
  local tool="$1" version="$2" repo path hash
  repo="$(repo_for "${tool}")"
  path="$(download "https://github.com/${repo}/archive/refs/tags/${version}.tar.gz")"
  hash="$(sha256_of "${path}")"
  record_hash "SHA256_SOURCE" "${hash}" "downloaded"
}

# Hash every asset; tflint hashes must equal upstream's checksums.txt entry.
collect_hashes() {
  local tool="$1" version="$2" platform file path hash checksums="" name url expected
  if [[ "${tool}" = "tflint" ]]
  then
    url="$(asset_url "${tool}" "${version}" checksums.txt)"
    checksums="$(download "${url}")"
  fi
  for platform in "${PLATFORMS[@]}"
  do
    file="$(asset_file "${tool}" "${platform}")"
    url="$(asset_url "${tool}" "${version}" "${file}")"
    path="$(download "${url}")"
    hash="$(sha256_of "${path}")"
    name="SHA256_$(tr 'a-z-' 'A-Z_' <<<"${platform}")"
    if [[ -n "${checksums}" ]]
    then
      expected="$(expected_hash_from_checksums "${checksums}" "${file}")"
      [[ "${hash}" = "${expected}" ]] ||
        die "sha256 mismatch for ${file}: downloaded ${hash} differs from checksums.txt"
      record_hash "${name}" "${hash}" "checksums.txt"
    else
      record_hash "${name}" "${hash}" "downloaded"
    fi
  done
  if [[ "${tool}" = "tmq" ]]
  then
    collect_source_hash "${tool}" "${version}"
  fi
}

# Print the envsubst variable list of <tool>, as ${NAME} words.
variable_list() {
  # shellcheck disable=SC2016 # literal ${NAME} words are envsubst's argument
  local platform list='${VERSION}'
  for platform in "${PLATFORMS[@]}"
  do
    list+=" \${SHA256_$(tr 'a-z-' 'A-Z_' <<<"${platform}")}"
  done
  # shellcheck disable=SC2016 # literal ${NAME} words are envsubst's argument
  [[ "$1" != "tmq" ]] || list+=' ${SHA256_SOURCE}'
  echo "${list}"
}

require_variables() {
  local word name
  for word in $1
  do
    name="${word#\$\{}"
    name="${name%\}}"
    [[ -n "${!name:-}" ]] || die "${name} is empty"
  done
}

# Render the template of <tool> into <destination> and reject leftovers.
render_to() {
  local tool="$1" destination="$2" template="packaging/homebrew/$1.rb.in" variables target
  [[ -f "${template}" ]] || die "missing template ${template}"
  variables="$(variable_list "${tool}")"
  require_variables "${variables}"
  envsubst "${variables}" <"${template}" >"${destination}"
  # shellcheck disable=SC2016 # searching for the literal two characters ${
  if grep -qF '${' "${destination}"
  then
    target="$(target_for "${tool}")"
    die "unresolved placeholder left in rendered ${target}"
  fi
  chmod 0644 "${destination}"
}

# Render atomically: write next to the target, check, then mv over it.
render() {
  local tool="$1" target
  target="$(target_for "${tool}")"
  temp_target="$(mktemp "$(dirname "${target}")/.render.XXXXXX")"
  render_to "${tool}" "${temp_target}"
  mv "${temp_target}" "${target}"
  temp_target=""
  log "wrote ${target}"
}

# Print the version recorded in the committed generated file of <tool>.
committed_version() {
  local tool="$1" target="$2" version
  if [[ "${tool}" = "tflint" ]]
  then
    version="$(sed -n 's/^ *version "\([^"]*\)".*/\1/p' "${target}" | head -n 1)"
  else
    version="$(sed -n 's#.*/releases/download/\([^/]*\)/.*#\1#p' "${target}" | head -n 1)"
  fi
  [[ "${version}" =~ ^[0-9]+(\.[0-9]+)*$ ]] || die "no valid version found in ${target} ('${version}')"
  echo "${version}"
}

# Export the sha256 values of the committed file, in template order.
export_committed_hashes() {
  local tool="$1" target="$2" platform name hash index=0 sha_lines
  local -a names=() hashes=()
  for platform in "${PLATFORMS[@]}"
  do
    names+=("SHA256_$(tr 'a-z-' 'A-Z_' <<<"${platform}")")
  done
  [[ "${tool}" != "tmq" ]] || names+=("SHA256_SOURCE")
  sha_lines="$(sed -n 's/^ *sha256 "\([^"]*\)".*/\1/p' "${target}")"
  if [[ -n "${sha_lines}" ]]
  then
    while IFS= read -r hash
    do
      hashes+=("${hash}")
    done <<<"${sha_lines}"
  fi
  [[ "${#hashes[@]}" -eq "${#names[@]}" ]] ||
    die "expected ${#names[@]} sha256 values in ${target}, found ${#hashes[@]}"
  for name in "${names[@]}"
  do
    [[ "${hashes[index]}" =~ ^[0-9a-f]{64}$ ]] || die "malformed sha256 '${hashes[index]}' in ${target}"
    export "${name}=${hashes[index]}"
    index=$((index + 1))
  done
}

# Print a unified diff of <target> against <rendered> and die when they differ.
diff_or_die() {
  local target="$1" rendered="$2" tool="$3"
  if ! diff -u --label "${target} (committed)" --label "${target} (rendered)" "${target}" "${rendered}"
  then
    die "${target} differs from its template; edit packaging/homebrew/${tool}.rb.in and re-render"
  fi
}

# Offline drift check: re-render from the values inside the committed file.
check() {
  local tool="$1" target
  target="$(target_for "${tool}")"
  [[ -f "${target}" ]] || die "missing ${target}"
  VERSION="$(committed_version "${tool}" "${target}")"
  export VERSION
  export_committed_hashes "${tool}" "${target}"
  temp_target="$(mktemp)"
  render_to "${tool}" "${temp_target}"
  diff_or_die "${target}" "${temp_target}" "${tool}"
  log "${target} matches its template (version ${VERSION})"
}

# Download and hash <tool> <version> into the exported placeholder variables.
fetch_hashes() {
  local tool="$1" version="$2"
  [[ "${version}" =~ ^[0-9]+(\.[0-9]+)*$ ]] || die "invalid version '${version}'"
  work_dir="$(mktemp -d)"
  export VERSION="${version}"
  collect_hashes "${tool}" "${version}"
}

# Online drift check: compare the committed file with what upstream publishes.
verify() {
  local tool="$1" target version
  target="$(target_for "${tool}")"
  [[ -f "${target}" ]] || die "missing ${target}"
  version="$(committed_version "${tool}" "${target}")"
  fetch_hashes "${tool}" "${version}"
  temp_target="$(mktemp)"
  render_to "${tool}" "${temp_target}"
  diff_or_die "${target}" "${temp_target}" "${tool}"
  log "${target} matches upstream release ${VERSION}"
}

main() {
  [[ "$#" -ge 1 ]] && [[ "$#" -le 2 ]] || die "usage: render-homebrew.sh [--check|--verify] <tmq|tflint> [<version>]"
  cd "$(dirname "${BASH_SOURCE[0]}")/.."
  trap cleanup EXIT
  case "$1" in
    --check | --verify)
      [[ "$#" -eq 2 ]] || die "usage: render-homebrew.sh $1 <tmq|tflint>"
      repo_for "$2" >/dev/null
      "${1#--}" "$2"
      return
      ;;
    *) ;;
  esac
  local tool="$1" version="${2:-}"
  repo_for "${tool}" >/dev/null
  if [[ -z "${version}" ]]
  then
    version="$(latest_version "${tool}")"
  fi
  fetch_hashes "${tool}" "${version}"
  render "${tool}"
  echo "version ${version}"
}

main "$@"
