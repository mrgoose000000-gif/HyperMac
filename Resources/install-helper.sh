#!/bin/bash
# Cài helper khóa sạc / quạt. Chạy bằng root qua "do shell script ... with administrator privileges".
#   $1 = smc   $2 = displaycontrol-power   $3 = tên user được phép chạy helper
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

if [ ! -f "$SRC_SMC" ] || [ -L "$SRC_SMC" ] || [ ! -f "$SRC_HELPER" ] || [ -L "$SRC_HELPER" ]; then
    echo "Error: Invalid source files"
    exit 1
fi

# Tên user đi vào rule sudoers: chỉ nhận ký tự an toàn, không nhận từ khóa đặc biệt hoặc bắt đầu bằng '-'.
case "$TARGET_USER" in
    *[!A-Za-z0-9._-]*|-*|.|..|ALL|root) echo "Error: invalid user name"; exit 1 ;;
esac
id -u "$TARGET_USER" >/dev/null 2>&1 || { echo "Error: unknown user"; exit 1; }

mkdir -p "$DIR" /etc/sudoers.d
chown root:wheel "$DIR"
chmod 755 "$DIR"

install -o root -g wheel -m 755 "$SRC_SMC" "$SMC"
install -o root -g wheel -m 755 "$SRC_HELPER" "$POWER"

# Chỉ đúng user cài, chỉ đúng helper v3. Helper tự kiểm tra mọi tham số trước khi xử lý.
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
echo "$TARGET_USER ALL=(root) NOPASSWD: $POWER" > "$TMP"
visudo -cf "$TMP" >/dev/null
install -o root -g wheel -m 440 "$TMP" "$SUDOERS"

# Gỡ helper & sudoers cũ (<= v2 ở /usr/local/bin)
rm -f /etc/sudoers.d/displaycontrol_power
rm -f /usr/local/bin/displaycontrol-power /usr/local/bin/displaycontrol-smc

echo "SUCCESS"
