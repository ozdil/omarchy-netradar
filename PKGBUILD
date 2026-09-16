# Maintainer: Ozan Özdil (ozdil) <ozan@pm.me>
pkgname=omarchy-netradar
pkgver=1.0.0
pkgrel=1
_commit="953ac977c38c20558e07d576d512bf1716db0d77"
pkgdesc="Ultra-fast, secure local network scanner and device radar for Omarchy Linux"
arch=('x86_64')
url="https://github.com/ozdil/omarchy-netradar"
license=('MIT')
depends=('glibc' 'gcc-libs' 'quickshell' 'iproute2')
optdepends=('wl-clipboard: for Wayland clipboard 1-click IP/MAC copy')
makedepends=('cargo' 'rust')
source=("$pkgname-$_commit.tar.gz::$url/archive/$_commit.tar.gz")
sha256sums=('bdbbafe19ebb091d5ae00d420a90f3a30be82b8bb8ddcc65f10fc3e53f48cfb3')

build() {
  cd "$pkgname-$_commit"
  cargo build --release --locked
}

check() {
  cd "$pkgname-$_commit"
  cargo test --release --locked
}

package() {
  cd "$pkgname-$_commit"
  install -Dm755 "target/release/netradar-engine" "${pkgdir}/usr/bin/netradar-engine"
  install -Dm755 "target/release/netradar-engine" "${pkgdir}/usr/lib/omarchy/plugins/ozdil.netradar/netradar-engine"
  install -Dm755 "netradar" "${pkgdir}/usr/bin/netradar"
  install -Dm755 "netradar-dashboard" "${pkgdir}/usr/bin/netradar-dashboard"
  install -Dm755 "netradar-status" "${pkgdir}/usr/bin/netradar-status"
  install -Dm644 "netradar.desktop" "${pkgdir}/usr/share/applications/netradar.desktop"
  install -Dm644 "manifest.json" "${pkgdir}/usr/lib/omarchy/plugins/ozdil.netradar/manifest.json"
  install -Dm644 "Panel.qml" "${pkgdir}/usr/lib/omarchy/plugins/ozdil.netradar/Panel.qml"
  install -Dm644 "preview.png" "${pkgdir}/usr/lib/omarchy/plugins/ozdil.netradar/preview.png"
  install -d "${pkgdir}/usr/share/omarchy-netradar"
  cp -r qml "${pkgdir}/usr/share/omarchy-netradar/"
  install -Dm644 "README.md" "${pkgdir}/usr/share/doc/${pkgname}/README.md"
  install -Dm644 "LICENSE" "${pkgdir}/usr/share/licenses/${pkgname}/LICENSE"
}
