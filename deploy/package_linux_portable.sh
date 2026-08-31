#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${1:-${ROOT}/build-release}"
OUT_DIR="${2:-${ROOT}/release}"
APP="QGroundControl-linux-x86_64"
PKG_DIR="${OUT_DIR}/${APP}"
QT_DIR="${QT_DIR:-${HOME}/Qt/5.15.2/gcc_64}"

test -x "${BUILD_DIR}/QGroundControl" || { echo "Missing ${BUILD_DIR}/QGroundControl" >&2; exit 1; }
test -d "${QT_DIR}/lib" || { echo "Missing Qt directory: ${QT_DIR}" >&2; exit 1; }

rm -rf "${PKG_DIR}"
mkdir -p "${PKG_DIR}/lib" "${PKG_DIR}/plugins" "${PKG_DIR}/qml" "${PKG_DIR}/share" "${PKG_DIR}/bin"
cp "${BUILD_DIR}/QGroundControl" "${PKG_DIR}/bin/"
cp "${BUILD_DIR}/libs/shapelib/libshp.so"* "${PKG_DIR}/lib/"
cp "${BUILD_DIR}/libs/qmlglsink/libqmlglsink.so" "${PKG_DIR}/lib/"

# Qt shared libraries used by QGC (copying all Qt 5 libraries keeps plugin loading robust).
cp -a "${QT_DIR}/lib/"libQt5*.so* "${PKG_DIR}/lib/"
# Qt 5.15.2 from the official installer links against ICU 56.
cp -a "${QT_DIR}/lib/"libicu*.so* "${PKG_DIR}/lib/"
cp -a "${QT_DIR}/plugins/"* "${PKG_DIR}/plugins/"
cp -a "${QT_DIR}/qml/"* "${PKG_DIR}/qml/"

cp "${ROOT}/resources/icons/qgroundcontrol.png" "${PKG_DIR}/share/"
cp "${ROOT}/QGC_CUSTOM_MODIFICATIONS.md" "${PKG_DIR}/share/" 2>/dev/null || true

cat > "${PKG_DIR}/QGroundControl" <<'EOF'
#!/usr/bin/env bash
set -e
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LD_LIBRARY_PATH="${HERE}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
export QT_PLUGIN_PATH="${HERE}/plugins"
export QML2_IMPORT_PATH="${HERE}/qml"
exec "${HERE}/bin/QGroundControl" "$@"
EOF
chmod +x "${PKG_DIR}/QGroundControl" "${PKG_DIR}/bin/QGroundControl"

mkdir -p "${OUT_DIR}"
tar -C "${OUT_DIR}" -czf "${OUT_DIR}/${APP}.tar.gz" "${APP}"
sha256sum "${OUT_DIR}/${APP}.tar.gz" > "${OUT_DIR}/${APP}.tar.gz.sha256"
echo "Created: ${OUT_DIR}/${APP}.tar.gz"
