#!/bin/bash
# ─────────────────────────────────────────────────────────────
#  export-ci-signing.sh
#
#  Xuất chứng chỉ ký self-signed của HyperMac thành file .p12 + base64
#  để đưa vào GitHub Actions Secrets. Nhờ đó bản phát hành trên CI
#  được ký bằng CÙNG identity với bản local → Designated Requirement
#  không đổi giữa các phiên bản → quyền Accessibility không bị mất
#  sau mỗi lần update.
#
#  Chạy sau khi đã có ~/.hypermac-signing/{key.pem,cert.pem}
#  (do ./scripts/setup-signing-identity.sh tạo ra).
#
#  Không commit file .p12 / .base64 — chúng chứa private key.
# ─────────────────────────────────────────────────────────────
set -euo pipefail

WORK_DIR="${HOME}/.hypermac-signing"
KEY="${WORK_DIR}/key.pem"
CERT="${WORK_DIR}/cert.pem"
IDENTITY="${HYPERMAC_SIGN_IDENTITY:-HyperMac Self-Signed}"
OUT="${WORK_DIR}/ci-signing.p12"

if [[ ! -f "${KEY}" || ! -f "${CERT}" ]]; then
    echo "❌ Không tìm thấy ${KEY} hoặc ${CERT}."
    echo "   Chạy ./scripts/setup-signing-identity.sh trước."
    exit 1
fi

PASS="${HYPERMAC_CI_P12_PASSWORD:-$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | cut -c1-28)}"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║   HyperMac — Xuất chứng chỉ cho GitHub Actions       ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

chmod 700 "${WORK_DIR}" 2>/dev/null || true
umask 077

# --export: đóng gói cả private key + cert, đặt friendly name = CN để codesign nhận diện
openssl pkcs12 -export \
    -inkey "${KEY}" \
    -in "${CERT}" \
    -name "${IDENTITY}" \
    -out "${OUT}" \
    -passout "pass:${PASS}"

chmod 600 "${OUT}"
base64 -i "${OUT}" -o "${OUT}.base64"
chmod 600 "${OUT}.base64"

# In SHA-1 root hash để đối chiếu với Designated Requirement
ROOT_HASH=$(openssl x509 -in "${CERT}" -noout -fingerprint -sha1 \
    | sed 's/.*=//; s/://g' | tr 'A-F' 'a-f')

echo "✅ Đã tạo:"
echo "   P12      : ${OUT}"
echo "   Base64   : ${OUT}.base64"
echo "   Mật khẩu : ${PASS}"
echo ""
echo "   Certificate root (SHA-1): ${ROOT_HASH}"
echo "   → Designated Requirement phải chứa: certificate root = H\"${ROOT_HASH}\""
echo ""
echo "──────────────────────────────────────────────────────────"
echo "Thêm 2 secret tại:"
echo "  https://github.com/mrgoose000000-gif/HyperMac/settings/secrets/actions"
echo ""
echo "  HYPERMAC_SIGNING_P12_BASE64  = toàn bộ nội dung file .base64"
echo "  HYPERMAC_SIGNING_P12_PASSWORD = mật khẩu ở trên"
echo ""
echo "Gợi ý copy nhanh vào clipboard:"
echo "  pbcopy < \"${OUT}.base64\""
echo "──────────────────────────────────────────────────────────"
echo ""
echo "⚠️  Không commit ${OUT} hoặc ${OUT}.base64."
echo "⚠️  Giữ nguyên key.pem/cert.pem: tạo lại cert = đổi root hash = mất quyền TCC."
