# Maintainer: Ozan Özdil <ozan@pm.me>
pkgname=omarchy-netradar
pkgver=1.0.0
pkgrel=1
pkgdesc="Ultra-fast, secure local network scanner & device radar for Omarchy Linux"
arch=('x86_64')
url="https://github.com/ozdil/omarchy-netradar"
license=('MIT')
depends=('glibc' 'gcc-libs' 'quickshell' 'iproute2')
optdepends=('wl-clipboard: for Wayland clipboard 1-click IP/MAC copy')
makedepends=('cargo' 'rust')

build() {
    cd "${startdir}"
    cargo build --release --locked
}

package() {
    cd "${startdir}"
    install -Dm755 "target/release/netradar-engine" "${pkgdir}/usr/bin/netradar-engine"
    install -Dm755 "netradar" "${pkgdir}/usr/bin/netradar"
    install -Dm755 "netradar-dashboard" "${pkgdir}/usr/bin/netradar-dashboard"
    install -Dm755 "netradar-status" "${pkgdir}/usr/bin/netradar-status"
    install -Dm644 "netradar.desktop" "${pkgdir}/usr/share/applications/netradar.desktop"
    install -Dm644 "manifest.json" "${pkgdir}/usr/share/omarchy/plugins/ozdil.netradar/manifest.json"
    install -Dm644 "Panel.qml" "${pkgdir}/usr/share/omarchy/plugins/ozdil.netradar/Panel.qml"
    install -Dm644 "preview.png" "${pkgdir}/usr/share/omarchy/plugins/ozdil.netradar/preview.png"
    install -Dm644 "README.md" "${pkgdir}/usr/share/doc/${pkgname}/README.md"
    install -Dm644 "LICENSE" "${pkgdir}/usr/share/licenses/${pkgname}/LICENSE"
}
