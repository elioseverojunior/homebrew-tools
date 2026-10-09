#!/usr/bin/env bash
# Build deb, rpm, apk and Arch packages of a tap tool with nfpm.
# Usage: scripts/package.sh <formula> <arch>   (arch: amd64 | arm64)
#        scripts/package.sh version <formula>  (print the version, no network)
# The upstream release asset is downloaded into a temporary directory, its
# sha256 is verified against the formula, and it is only ever copied or
# unzipped, never executed.
set -Eeuo pipefail

readonly PACKAGE_FORMATS=(deb rpm apk archlinux)

# Global so the EXIT trap can still see it after main returns.
work_dir=""

die() {
  echo "package.sh: $*" >&2
  exit 1
}

# Print the file that defines <formula>: a formula first, then a cask.
find_definition() {
  local formula="$1" candidate
  for candidate in "Formula/${formula:0:1}/${formula}.rb" "Casks/${formula}.rb"
  do
    if [[ -f "${candidate}" ]]
    then
      echo "${candidate}"
      return 0
    fi
  done
  die "no Formula/${formula:0:1}/${formula}.rb or Casks/${formula}.rb found"
}

# Print the first top-level `<key> "value"` of the definition.
read_field() {
  local file="$1" key="$2" value
  value="$(sed -n -E "s/^[[:space:]]*${key}[[:space:]]+\"([^\"]*)\".*/\1/p" "${file}" | head -n 1)"
  [[ -n "${value}" ]] || die "no '${key}' in ${file}"
  echo "${value}"
}

# Print the version: the `version` stanza, else the one Homebrew scans from the
# first release url (a formula must omit `version` when the url carries it).
read_version() {
  local file="$1" value
  value="$(sed -n -E 's/^[[:space:]]*version[[:space:]]+"([^"]*)".*/\1/p' "${file}" | head -n 1)"
  if [[ -z "${value}" ]]
  then
    value="$(sed -n -E 's|^[[:space:]]*url[[:space:]]+"[^"]*/releases/download/v?([0-9][^/"]*)/.*|\1|p' "${file}" | head -n 1)"
  fi
  [[ -n "${value}" ]] || die "no version in ${file}"
  echo "${value}"
}

# Print "<url> <sha256>" from the on_linux > <block> section, where <block> is
# on_intel or on_arm. Pairing happens inside the block, so the order of url and
# sha256 does not matter; anything but exactly one of each is fatal.
read_linux_asset() {
  local file="$1" block="$2" version="$3" found url sha count
  # No awk line may start with "if ": Homebrew's shfmt wrapper mistakes it for a
  # shell `if` and re-indents everything after it.
  found="$(awk -v block="${block}" '
    /^[[:space:]]*on_linux[[:space:]]+do/ { in_linux = 1; depth = 1; next }
    in_linux && /^[[:space:]]*on_(arm|intel)[[:space:]]+do/ { in_block = ($1 == block); depth++; next }
    in_linux && /[[:space:]]do[[:space:]]*$/ { depth++ }
    in_linux && /^[[:space:]]*end[[:space:]]*$/ { depth--; in_block = 0; if (depth == 0) in_linux = 0; next }
    in_block && /^[[:space:]]*url[[:space:]]+"[^"]*"/ { print "url " $2 }
    in_block && /^[[:space:]]*sha256[[:space:]]+"[^"]*"/ { print "sha " $2 }
  ' "${file}" | tr -d '"')"
  count="$(grep -c '^url ' <<<"${found}" || true)"
  [[ "${count}" -eq 1 ]] || die "need exactly one url in on_linux > ${block} of ${file}"
  count="$(grep -c '^sha ' <<<"${found}" || true)"
  [[ "${count}" -eq 1 ]] || die "need exactly one sha256 in on_linux > ${block} of ${file}"
  url="$(sed -n 's/^url //p' <<<"${found}")"
  sha="$(sed -n 's/^sha //p' <<<"${found}")"
  [[ "${sha}" =~ ^[0-9a-f]{64}$ ]] || die "malformed sha256 '${sha}' in ${file}"
  echo "${url//\#\{version\}/${version}} ${sha}"
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1
  then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# Download <url> into <directory> and abort unless it matches <expected>.
download_verified() {
  local url="$1" expected="$2" directory="$3" target actual
  [[ "${url}" == https://* ]] || die "refusing non-https url ${url}"
  target="${directory}/$(basename "${url}")"
  curl --fail --silent --show-error --location --proto '=https' --output "${target}" "${url}"
  actual="$(sha256_of "${target}")"
  [[ "${actual}" = "${expected}" ]] || die "sha256 mismatch for ${url}: expected ${expected}, got ${actual}"
  echo "${target}"
}

# Stage the binary as <directory>/<formula> (mode 0755) from a zip or bare file.
stage_binary() {
  local download="$1" formula="$2" directory="$3"
  case "${download}" in
    *.zip) unzip -q -j -o "${download}" "${formula}" -d "${directory}" ;;
    *) cp "${download}" "${directory}/${formula}" ;;
  esac
  [[ -f "${directory}/${formula}" ]] || die "no regular file ${formula} after unpacking ${download}"
  [[ ! -L "${directory}/${formula}" ]] || die "${formula} in ${download} is a symlink"
  chmod 0755 "${directory}/${formula}"
}

export_metadata() {
  case "$1" in
    tmq) PKG_HOMEPAGE="https://tomlq.ir" PKG_LICENSE="MIT" ;;
    tflint) PKG_HOMEPAGE="https://github.com/terraform-linters/tflint" PKG_LICENSE="MPL-2.0" ;;
    *) die "no packaging metadata for '$1'" ;;
  esac
  export PKG_HOMEPAGE PKG_LICENSE
}

# nfpm expands ${VAR} in name and description but not in license (verified with
# a real build), so the config is rendered with envsubst first. The variable
# list is explicit so only the PKG_* and NFPM_* contract is touched.
require_metadata() {
  : "${PKG_NAME:?PKG_NAME is required}" "${PKG_VERSION:?PKG_VERSION is required}"
  : "${PKG_DESCRIPTION:?PKG_DESCRIPTION is required}" "${PKG_HOMEPAGE:?PKG_HOMEPAGE is required}"
  : "${PKG_LICENSE:?PKG_LICENSE is required}" "${PKG_BIN_DIR:?PKG_BIN_DIR is required}"
  : "${NFPM_ARCH:?NFPM_ARCH is required}"
  local name value
  for name in PKG_NAME PKG_VERSION PKG_DESCRIPTION PKG_HOMEPAGE PKG_LICENSE PKG_BIN_DIR NFPM_ARCH
  do
    value="${!name}"
    case "${value}" in
      *"'"* | *$'\n'*) die "${name} must not contain a single quote or newline" ;;
      *) ;;
    esac
  done
}

render_config() {
  local rendered="$1"
  require_metadata
  # shellcheck disable=SC2016 # the literal ${VAR} names are envsubst's argument
  envsubst '${PKG_NAME} ${PKG_VERSION} ${PKG_DESCRIPTION} ${PKG_HOMEPAGE} ${PKG_LICENSE} ${PKG_BIN_DIR} ${NFPM_ARCH}' \
    <nfpm.yaml >"${rendered}"
  ! grep -qE '\$\{(PKG|NFPM)_' "${rendered}" || die "unresolved variable in rendered nfpm config"
}

build_packages() {
  local rendered="$1" format
  render_config "${rendered}"
  mkdir -p dist
  for format in "${PACKAGE_FORMATS[@]}"
  do
    nfpm package --config "${rendered}" --packager "${format}" --target dist/
  done
}

# `package.sh version <formula>` prints the version from the definition file.
print_version() {
  local formula="$1" definition
  [[ "${formula}" =~ ^[a-z0-9-]+$ ]] || die "invalid formula name '${formula}'"
  cd "$(dirname "${BASH_SOURCE[0]}")/.."
  definition="$(find_definition "${formula}")"
  read_version "${definition}"
}

block_for_arch() {
  case "$1" in
    amd64) echo on_intel ;;
    arm64) echo on_arm ;;
    *) die "arch must be amd64 or arm64, got '$1'" ;;
  esac
}

main() {
  if [[ "$#" -eq 2 ]] && [[ "$1" = "version" ]]
  then
    print_version "$2"
    return
  fi
  [[ "$#" -eq 2 ]] || die "usage: package.sh <formula> <arch: amd64|arm64>"
  local formula="$1" arch="$2" definition block version asset url sha download
  [[ "${formula}" =~ ^[a-z0-9-]+$ ]] || die "invalid formula name '${formula}'"
  block="$(block_for_arch "${arch}")"
  cd "$(dirname "${BASH_SOURCE[0]}")/.."
  definition="$(find_definition "${formula}")"
  version="$(read_version "${definition}")"
  asset="$(read_linux_asset "${definition}" "${block}" "${version}")"
  url="${asset% *}"
  sha="${asset#* }"
  work_dir="$(mktemp -d)"
  trap '[ -z "${work_dir}" ] || rm -rf "${work_dir}"' EXIT
  download="$(download_verified "${url}" "${sha}" "${work_dir}")"
  mkdir "${work_dir}/bin"
  stage_binary "${download}" "${formula}" "${work_dir}/bin"
  export PKG_NAME="${formula}" PKG_VERSION="${version}" NFPM_ARCH="${arch}"
  PKG_DESCRIPTION="$(read_field "${definition}" desc)"
  export PKG_DESCRIPTION PKG_BIN_DIR="${work_dir}/bin"
  export_metadata "${formula}"
  build_packages "${work_dir}/nfpm.yaml"
}

main "$@"
