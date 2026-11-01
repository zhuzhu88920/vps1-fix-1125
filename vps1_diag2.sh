#!/bin/bash
# VPS1 诊断 + 清卡死连接（VNC 手动运行）
echo "=== [A] 22端口各状态连接数（判断是否被暴破挤满）==="
ss -tan 2>/dev/null | grep ':22 ' | awk '{print $1}' | sort | uniq -c
echo "含TIME_WAIT总数:"; ss -tan 2>/dev/null | grep -c ':22 '
echo "=== [B] fail2ban 当前封禁（判断是否在封你的xterminal IP）==="
fail2ban-client status sshd 2>/dev/null
echo "--- banned IP 列表 ---"
fail2ban-client get sshd banned 2>/dev/null
fail2ban-client get recidive banned 2>/dev/null
echo "=== [C] 最近 auth.log（暴破频率 + 你的失败来源）==="
tail -20 /var/log/auth.log 2>/dev/null
echo "--- 失败来源IP Top10 ---"
grep -oE 'from [0-9.]+' /var/log/auth.log 2>/dev/null | sort | uniq -c | sort -rn | head -10
echo "=== [D] 强制清卡死 + 解封 ==="
fail2ban-client unban --all 2>/dev/null && echo "已 unban --all"
systemctl restart ssh.socket 2>/dev/null; systemctl restart ssh 2>/dev/null && echo "ssh 已重启(清空卡死连接)"
sleep 2
echo "=== [E] 修复后监听 ==="
ss -tlnp 2>/dev/null | grep ':22 '
echo "DIAG2_DONE"
