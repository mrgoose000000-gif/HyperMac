#!/bin/bash
# ─────────────────────────────────────────────────────────────
#  setup-signing-identity.sh
#
#  Tạo chứng chỉ code-signing self-signed CỐ ĐỊNH cho HyperMac.
#
#  Vì sao cần? App ký ad-hoc (`codesign -s -`) sinh ra cdhash mới sau
#  MỖI lần build, nên macOS coi đó là app khác và thu hồi quyền
#  Accessibility → phím tắt (⌘Tab, ⌘⇧C) chết cho tới khi cấp lại tay.
#  Ký bằng một identity cố định giữ nguyên Designated Requirement,
#  nên quyền TCC được giữ qua mọi lần rebuild.
#
#  Chạy 1 lần:  ./scripts/setup-signing-identity.sh
#  Sau đó build.sh tự dùng identity này nếu có.
# ─────────────────────────────────────────────────────────────
set -euo pipefail

IDENTITY_NAME="${HYPERMAC_SIGN_IDENTITY:-HyperMac Self-Signed}"
WORK_DIR="${HOME}/.hypermac-signing"
P12_PASS="hypermac-local"
LOGIN_KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

mkdir -p "${WORK_DIR}"
chmod 700 "${WORK_DIR}"

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║   HyperMac — Tạo chứng chỉ ký cố định (local)    ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ── 1. Đã có identity chưa? ──
if security find-identity -v -p codesigning 2>/dev/null | grep -qF "${IDENTITY_NAME}"; then
    echo "✅ Đã có identity: ${IDENTITY_NAME}"
    echo "   Không cần tạo lại."
    exit 0
fi

# ── 2. Sinh key + self-signed cert (codeSigning EKU) ──
echo "🔑 Đang tạo key + chứng chỉ self-signed..."

cat > "${WORK_DIR}/codesign.cnf" <<'CNF'
[req]
prompt             = no
distinguished_name = dn
x509_extensions    = v3_codesign
[dn]
CN = HyperMac Self-Signed
O  = HyperMac Local Signing
[v3_codesign]
basicConstraints       = critical, CA:false
keyUsage               = critical, digitalSignature
extendedKeyUsage       = critical, codeSigning
subjectKeyIdentifier   = hash
CNF

openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "${WORK_DIR}/key.pem" \
    -out "${WORK_DIR}/cert.pem" \
    -days 3650 \
    -config "${WORK_DIR}/codesign.cnf" >/dev/null 2>&1

openssl pkcs12 -export -legacy \
    -inkey "${WORK_DIR}/key.pem" \
    -in "${WORK_DIR}/cert.pem" \
    -name "${IDENTITY_NAME}" \
    -out "${WORK_DIR}/identity.p12" \
    -passout "pass:${P12_PASS}" >/dev/null 2>&1

chmod 600 "${WORK_DIR}/key.pem" "${WORK_DIR}/identity.p12"

# ── 3. Import vào login keychain, cấp quyền cho codesign ──
echo "🔐 Đang import vào login keychain..."
# -T: cho phép codesign/security dùng key; -A: không hỏi từng app
security import "${WORK_DIR}/identity.p12" \
    -k "${LOGIN_KEYCHAIN}" \
    -P "${P12_PASS}" \
    -T /usr/bin/codesign \
    -T /usr/bin/security \
    -A >/dev/null

# macOS có thể vẫn hỏi "codesign wants to sign..." lần đầu → luôn chọn Always Allow.
security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s -k "" "${LOGIN_KEYCHAIN}" >/dev/null 2>&1 || true

# ── 4. Trust cho code signing (user domain, không cần sudo) ──
# Chưa trust thì identity vẫn ký được nhưng hiện "CSSMERR_TP_NOT_TRUSTED".
if ! security find-identity -v -p codesigning 2>/dev/null | grep -qF "${IDENTITY_NAME}"; then
    echo "🛡  Đang thêm trust cho chứng chỉ (policy: Code Signing)..."
    security add-trusted-cert -r trustRoot -p codeSign \
        -k "${LOGIN_KEYCHAIN}" "${WORK_DIR}/cert.pem" >/dev/null 2>&1 || true
fi

# ── 5. Kiểm tra ──
if security find-identity -v -p codesigning 2>/dev/null | grep -qF "${IDENTITY_NAME}"; then
    echo ""
    echo "✅ Thành công! Identity đã sẵn sàng:"
    security find-identity -v -p codesigning | grep -F "${IDENTITY_NAME}"
    echo ""
    echo "   Thư mục lưu key: ${WORK_DIR} (chỉ bạn đọc được)"
    echo "   Giờ chạy: ./build.sh"
    echo ""
    echo "ℹ️  Từ nay quyền Accessibility được giữ qua mọi lần rebuild."
    echo "    Chỉ cần cấp quyền MỘT lần cho chữ ký mới này."
else
    echo "❌ Không tạo được identity. Kiểm tra lại login keychain."
    exit 1
fi
