# install.fish — catpm installer for the fish shell
# Usage:  fish install.fish
# Override target:  set -x CATPM_INSTALL_DIR /some/dir; fish install.fish
#
# Equivalent of install.sh (POSIX); fish-native syntax throughout.

set REPO monikalnbo/catpm
set RAW "https://raw.githubusercontent.com/$REPO/main"
set VERSION catpm54             # binary name in the repo (v0.5.4, self-update capable)

if set -q CATPM_INSTALL_DIR
    set DEST $CATPM_INSTALL_DIR
else
    set DEST ~/.local/bin
end

# ---------------------------------------------------------------- checks
if not type -q curl
    echo "catpm-install: ERROR: 'curl' not found (required)" >&2
    exit 1
end
if not type -q tar
    echo "catpm-install: ERROR: 'tar' not found (required)" >&2
    exit 1
end

# ---------------------------------------------------------------- download
mkdir -p $DEST
set TMP (mktemp -d)

echo "catpm-install: downloading catpm ($VERSION) + package.where"
if not curl -fsSL -o $TMP/catpm $RAW/catpm/$VERSION
    echo "catpm-install: ERROR: download binary failed" >&2
    exit 1
end
if not curl -fsSL -o $TMP/package.where $RAW/catpm/package.where
    echo "catpm-install: ERROR: download package.where failed" >&2
    exit 1
end

# ---------------------------------------------------------------- install
cp $TMP/catpm $DEST/catpm
chmod 0755 $DEST/catpm
# package.where lives NEXT TO the binary (that's where catpm looks first)
cp $TMP/package.where $DEST/package.where
chmod 0644 $DEST/package.where
rm -rf $TMP

echo "catpm-install: installed: $DEST/catpm"
echo "catpm-install:         +  $DEST/package.where  (default source: catpm-registry)"

# ---------------------------------------------------------------- PATH help
if not contains -- $DEST $PATH
    echo ""
    echo "catpm-install: '$DEST' is not in your PATH yet. Add this to ~/.config/fish/config.fish:"
    echo ""
    echo "    fish_add_path $DEST"
    echo ""
    echo "catpm-install: then restart fish and run: catpm --version"
else
    echo ""
    echo "catpm-install: already on PATH. verify with: catpm --version"
end

$DEST/catpm --version
