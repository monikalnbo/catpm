#!/bin/sh
# install.sh — catpm installer (POSIX sh; runs under sh / bash / zsh)
# Fetches the catpm binary + package.where from GitHub and puts them in
# ~/.local/bin (or $CATPM_INSTALL_DIR). Prints shell PATH setup snippets
# for bash / zsh / fish at the end.
#
# Usage:            sh install.sh
# Override target:  CATPM_INSTALL_DIR=/usr/local/bin sh install.sh
set -eu

REPO="monikalnbo/catpm"
RAW="https://raw.githubusercontent.com/${REPO}/main"
VERSION="catpm55"         # binary name in the repo (v0.5.5, self-update capable)

if [ -n "${CATPM_INSTALL_DIR:-}" ]; then
    DEST="${CATPM_INSTALL_DIR}"
else
    DEST="${HOME}/.local/bin"
fi

# ---------------------------------------------------------------- helpers
say()  { printf '%s\n' "catpm-install: $*"; }
die()  { printf '%s\n' "catpm-install: ERROR: $*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "'$1' not found (required)"; }
need curl
need tar

# ---------------------------------------------------------------- download
mkdir -p "${DEST}"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT INT TERM

say "downloading catpm (${VERSION}) + package.where"
curl -fsSL -o "${TMP}/catpm"     "${RAW}/catpm/${VERSION}"        || die "download binary failed"
curl -fsSL -o "${TMP}/package.where" "${RAW}/catpm/package.where" || die "download package.where failed"

# ---------------------------------------------------------------- install
install -m 0755 "${TMP}/catpm" "${DEST}/catpm" 2>/dev/null \
    || cp "${TMP}/catpm" "${DEST}/catpm" \
    || die "cannot write to ${DEST} (try CATPM_INSTALL_DIR=~/somewhere or sudo)"
chmod 0755 "${DEST}/catpm"

# package.where lives NEXT TO the binary (that's where catpm looks first)
cp "${TMP}/package.where" "${DEST}/package.where"
chmod 0644 "${DEST}/package.where"

say "installed: ${DEST}/catpm"
say "        +  ${DEST}/package.where  (default source: catpm-registry)"

# ---------------------------------------------------------------- PATH help
case ":${PATH}:" in
    *":${DEST}:"*) FOUND=yes ;;
    *) FOUND=no ;;
esac

if [ "${FOUND}" = "no" ]; then
    printf '\n'
    say "'${DEST}' is not in your PATH yet. Add ONE of these to your shell init:"
    printf '\n'
    printf '  bash (~/.bashrc):\n'
    printf '    export PATH="%s:$PATH"\n' "${DEST}"
    printf '\n'
    printf '  zsh (~/.zshrc):\n'
    printf '    export PATH="%s:$PATH"\n' "${DEST}"
    printf '\n'
    printf '  fish (~/.config/fish/config.fish):\n'
    printf '    fish_add_path %s\n' "${DEST}"
    printf '\n'
    say "then restart the shell (or re-source the file) and run: catpm --version"
else
    printf '\n'
    say "already on PATH. verify with: catpm --version"
fi

"${DEST}/catpm" --version
