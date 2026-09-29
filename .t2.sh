echo "=== 深度清理 /root 下垃圾目录 ==="
find /root -maxdepth 1 -name '*选择*' -print0 2>/dev/null | xargs -0 -r rm -rf
find / -maxdepth 2 -name '*选择*' -print0 2>/dev/null | xargs -0 -r rm -rf
ls -A /root | sed 's/^/  /' | head -20
echo
echo "=== 复现旧 bug 是否已修（提示不得进入目录名）==="
cd /tmp && bash <<'INNER'
set -e
c(){ printf '\033[%sm%s\033[0m\n' "$1" "$2"; }
ok(){ c '32' "  [+] $1"; }
AUTO=0
ask(){
  local label="$1" default="$2" v=""
  if [ "$AUTO" = "1" ]; then printf '%s' "$default"; return 0; fi
  if [ -t 0 ] || [ -r /dev/tty ]; then
    { printf '%s\n' "$label"; printf '    default [%s]\n' "$default"; printf '    input (Enter = default): '; } >&2
    read -r v </dev/tty 2>/dev/null || v=""
  fi
  v="$(printf '%s' "$v" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [ -z "$v" ] && v="$default"
  printf '%s' "$v"
}
D="$(printf '/tmp/asktest' )"
rm -rf "$D"; mkdir -p "$D"
R="$(ask '选择安装目录（程序与数据都放这里，长期保留）' "$D")"
ok "安装目录: $R"
[ "$R" = "$D" ] && echo "  ✅ 返回值干净，无提示文字混入" || { echo "  ❌ 仍被污染: [$R]"; exit 1; }
rm -rf "$D"
INNER
