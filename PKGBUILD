# Maintainer: Feasuro <feasuro at pm dot me>
pkgname=keybuilder
pkgver=0.2
pkgrel=1
pkgdesc='Text-based wizard for creating multi boot pendrive.'
arch=(any)
url="https://github.com/Feasuro/${pkgname}"
license=('GPL-3.0-or-later')
depends=(
  'dialog'
  'util-linux'
  'udev'
  'exfatprogs'
  'dosfstools'
  'e2fsprogs'
  'grub'
  )
makedepends=('git')
source=("${pkgname}::git+${url}.git")
backup=("etc/${pkgname}.conf")
sha256sums=('SKIP')

pkgver() {
  cd "${pkgname}"
  ( set -o pipefail
    git describe --tags 2>/dev/null | sed 's/^v//;s/-/.r/;s/-/./' ||
    printf "0.r%s.%s" "$(git rev-list --count HEAD)" "$(git rev-parse --short=7 HEAD)"
  )
}

package() {
  cd "${srcdir}/${pkgname}"

  install -Dm0644 -t "${pkgdir}/usr/lib/${pkgname}/modules/" src/modules/*
  install -Dm0644 -t "${pkgdir}/usr/lib/${pkgname}/" src/main.sh
  install -Dm0644 "src/config.sh" "${pkgdir}/etc/${pkgname}.conf"
  install -Dm0644 "resources/pendrive.png" "${pkgdir}/usr/share/icons/hicolor/512x512/apps/${pkgname}.png"
  install -Dm0755 -t "${pkgdir}/usr/share/applications/" "${pkgname}.desktop"

  mkdir -p "${pkgdir}/usr/bin"
  cat > "${pkgdir}/usr/bin/${pkgname}" << EOF
#!/bin/bash

source /usr/lib/${pkgname}/main.sh
EOF
  chmod +x "${pkgdir}/usr/bin/${pkgname}"

  mkdir -p "${pkgdir}/usr/share/${pkgname}"
  cp -r grub "${pkgdir}" "${pkgdir}/usr/share/${pkgname}/"
}
