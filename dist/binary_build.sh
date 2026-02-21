#!/bin/bash
set -e

# === CONFIG ===
PKG_NAME="bal-helper-bin"
PKG_VER="1.0.2"
PKG_REL="1"
BIN_NAME="bal_helper"
# =================

# 1. Go to project root
ROOT_DIR="$(dirname "$(realpath "$0")")/.."
cd "$ROOT_DIR"

echo "[1/4] Building Flutter app..."

if [[ ! -f pubspec.yaml ]]; then
    echo "❌ pubspec.yaml not found"
    exit 1
fi

flutter pub get
flutter build linux --release

BUILD_OUTPUT="build/linux/x64/release/bundle"

if [[ ! -d "$BUILD_OUTPUT" ]]; then
    echo "❌ Build output missing: $BUILD_OUTPUT"
    exit 1
fi

if [[ ! -f "$BUILD_OUTPUT/$BIN_NAME" ]]; then
    echo "❌ Binary not found: $BIN_NAME"
    ls -l "$BUILD_OUTPUT"
    exit 1
fi

echo "[2/4] Preparing dist directory..."
cd dist

# clean old junk
rm -rf src pkg *.pkg.tar.zst PKGBUILD

mkdir -p src/bundle

echo "-> Copying build output..."
cp -a "../$BUILD_OUTPUT/"* src/bundle/

# sanity check
if [[ ! -f "src/bundle/$BIN_NAME" ]]; then
    echo "❌ CRITICAL: binary missing in staging!"
    ls -l src/bundle
    exit 1
fi

echo "[3/4] Generating PKGBUILD..."
cat > PKGBUILD <<EOF
# Maintainer: minhmc2007 <quangminh21072010@gmail.com>
pkgname=$PKG_NAME
pkgver=$PKG_VER
pkgrel=$PKG_REL
pkgdesc="Blue Archive Linux Helper App (Binary)"
arch=('x86_64')
url="https://github.com/minhmc2007/bal-helper"
license=('GPL3')
depends=('gtk3' 'mpv' 'libappindicator-gtk3')
provides=('bal-helper')
conflicts=('bal-helper')
options=('!strip')

package() {
    install -d "\$pkgdir/opt/bal-helper"
    install -d "\$pkgdir/usr/bin"

    cp -a "\$srcdir/bundle/"* "\$pkgdir/opt/bal-helper/"

    chmod 755 "\$pkgdir/opt/bal-helper/$BIN_NAME"

    ln -s "/opt/bal-helper/$BIN_NAME" "\$pkgdir/usr/bin/bal-helper"
}
EOF

echo "[4/4] Building package..."
makepkg -ef

echo "✅ Done!"
ls -lh *.pkg.tar.zst
