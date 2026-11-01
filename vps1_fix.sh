#!/bin/bash
# VPS1 一键诊断 + 安全修复（不写死任何用户IP白名单）
# 策略：仅密钥 + fail2ban(aggressive) 把暴破者挡在防火墙外层，合法密钥用户不会被误封
set -u

echo "===== [1/6] sshd 监听 & 服务状态 ====="
ss -tlnp 2>/dev/null | grep -E ':22 ' || echo "!! 22 端口没人监听"
systemctl is-active ssh 2>/dev/null && echo "ssh service: active" || echo "ssh service: NOT active"

echo "===== [2/6] sshd 关键配置 ====="
sshd -T 2>/dev/null | grep -iE '^(maxstartups|maxauthtries|passwordauthentication|pubkeyauthentication|permitrootlogin)'

echo "===== [3/6] 22端口连接数（判断是否被暴破挤满）====="
echo -n "ESTAB(已建连): "; ss -tn 2>/dev/null | grep -c ':22 '
echo -n "SYN_RECV(半开/暴破特征): "; ss -tn state syn-recv 2>/dev/null | grep -c ':22 '

echo "===== [4/6] fail2ban 当前状态 & 被封IP ====="
fail2ban-client status 2>/dev/null || echo "fail2ban 未运行"
echo "--- sshd 监狱 ---"
fail2ban-client status sshd 2>/dev/null
echo "--- recidive 监狱 ---"
fail2ban-client status recidive 2>/dev/null
echo "--- iptables f2b 链(DROP规则) ---"
iptables -L -n -v 2>/dev/null | grep -E 'f2b|DROP|REJECT' | head -30

echo "===== [5/6] 磁盘 & 最近日志 ====="
df -h / 2>/dev/null | tail -2
echo "--- auth.log tail ---"
tail -12 /var/log/auth.log 2>/dev/null
echo "--- fail2ban journal tail ---"
journalctl -u fail2ban -n 12 --no-pager 2>/dev/null

echo "===== [6/6] 安全修复 ====="
# 6.1 解封所有（放宽操作，不会把人锁外面；同时清掉可能误封的合法IP）
fail2ban-client unban --all 2>/dev/null && echo "已 unban --all" || echo "unban 跳过"
# 6.2 升级 fail2ban：aggressive 封“连上就关”的扫描 + recidive 累犯永封；仅保留本地回环白名单
CONF=/etc/fail2ban/jail.local
cat > "$CONF" <<'EOF'
[DEFAULT]
banaction = iptables-multiport
bantime = 1h
findtime = 10m
maxretry = 5
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled = true
port = 22
filter = sshd
maxretry = 5
bantime = 1h
mode = aggressive

[recidive]
enabled = true
logpath = /var/log/fail2ban.log
bantime = -1
findtime = 1d
maxretry = 10
EOF
echo "已写入 $CONF"
# 6.3 确保 sshd 在跑 + 抗压参数已存在则不动
SD=/etc/ssh/sshd_config.d/00-hardening.conf
if [ -f "$SD" ]; then
  grep -q '^MaxStartups' "$SD" || echo 'MaxStartups 50:30:100' >> "$SD"
  grep -q '^MaxAuthTries' "$SD" || echo 'MaxAuthTries 3' >> "$SD"
  grep -q '^LoginGraceTime' "$SD" || echo 'LoginGraceTime 20' >> "$SD"
  echo "已确保 sshd 抗压参数"
else
  cat > "$SD" <<'EOF'
PubkeyAuthentication yes
PasswordAuthentication no
PermitRootLogin prohibit-password
MaxStartups 50:30:100
MaxAuthTries 3
LoginGraceTime 20
EOF
  echo "已新建 $SD"
fi
# 6.4 重启服务
systemctl restart fail2ban 2>/dev/null && echo "fail2ban restarted" || echo "fail2ban 重启失败"
systemctl restart ssh 2>/dev/null && echo "ssh restarted" || echo "ssh 重启失败(勿慌，可能socket模式)"

sleep 3
echo "===== 修复后复查 ====="
ss -tlnp 2>/dev/null | grep -E ':22 ' || echo "!! 22 仍无监听"
fail2ban-client status sshd 2>/dev/null
echo "VPS1_FIX_DONE"
