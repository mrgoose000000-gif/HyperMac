#!/bin/bash
# Cài helper khóa sạc / quạt. Chạy bằng root qua "do shell script … with administrator privileges".
#   $1 = smc (trong app bundle)   $2 = displaycontrol-power (trong app bundle)   $3 = tên user được dùng helper
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

SRC_SMC="${1:-}"
SRC_HELPER="${2:-}"
TARGET_USER="${3:-}"

DIR=/Library/PrivilegedHelperTools
POWER="$DIR/com.opensource.hypermac.power"
SMC="$DIR/com.opensource.hypermac.smc"
SUDOERS=/etc/sudoers.d/hypermac_power

if [ -z "$SRC_SMC" ] || [ -z "$SRC_HELPER" ] || [ -z "$TARGET_USER" ]; then
    echo "Error: Missing arguments"
    exit 1
fi
# Tên user đi vào rule sudoers: chỉ nhận ký tự an toàn, và phải là user có thật.
case "$TARGET_USER" in
    *[!A-Za-z0-9._-]*|-*) echo "Error: invalid user name"; exit 1 ;;
esac
id -u "$TARGET_USER" >/dev/null 2>&1 || { echo "Error: unknown user"; exit 1; }

mkdir -p "$DIR"
chown root:wheel "$DIR"
chmod 755 "$DIR"

install -o root -g wheel -m 755 "$SRC_SMC" "$SMC"
install -o root -g wheel -m 755 "$SRC_HELPER" "$POWER"

# Chỉ đúng user này, chỉ đúng helper này. Helper tự kiểm tra từng tham số.
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
echo "$TARGET_USER ALL=(root) NOPASSWD: $POWER" > "$TMP"
# Rule sai cú pháp có thể làm hỏng sudo cả máy — kiểm tra trước khi đặt vào.
visudo -cf "$TMP" >/dev/null
install -o root -g wheel -m 440 "$TMP" "$SUDOERS"

# Gỡ bản cũ: sudoers "ALL ALL NOPASSWD" và helper trong /usr/local/bin.
rm -f /etc/sudoers.d/displaycontrol_power
rm -f /usr/local/bin/displaycontrol-power /usr/local/bin/displaycontrol-smc

echo "SUCCESS"
