cat > /root/mtproxy-setup.sh << 'EOF'
#!/bin/bash

# ==============================
#   MTProxy Auto Setup Script
#   github.com/TelegramMessenger
# ==============================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()     { echo -e "${GREEN}[+]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }
section() { echo -e "\n${BLUE}==============================${NC}\n    $1\n${BLUE}==============================${NC}"; }

# ==============================
# 1. Update & Install Dependencies
# ==============================
section "Installing Dependencies"
apt update -y && apt upgrade -y || error "apt update failed"
apt install -y git build-essential libssl-dev zlib1g-dev xxd curl bc vnstat || error "apt install failed"
log "Dependencies installed"

# ==============================
# 2. Clone & Build MTProxy
# ==============================
section "Building MTProxy"
if [ -d /opt/MTProxy ]; then
    warn "MTProxy already exists, pulling latest..."
    cd /opt/MTProxy && git pull
else
    git clone https://github.com/TelegramMessenger/MTProxy /opt/MTProxy || error "git clone failed"
fi
cd /opt/MTProxy
make clean && make || error "Build failed"
log "MTProxy built successfully"

# ==============================
# 3. Fetch Telegram Config
# ==============================
section "Fetching Telegram Config"
curl -s https://core.telegram.org/getProxySecret -o /opt/MTProxy/proxy-secret || error "Failed to fetch proxy-secret"
curl -s https://core.telegram.org/getProxyConfig -o /opt/MTProxy/proxy-multi.conf || error "Failed to fetch proxy-multi.conf"
log "Telegram config fetched"

# ==============================
# 4. Generate Secret
# ==============================
section "Generating Secret"
SECRET=$(head -c 16 /dev/urandom | xxd -ps)
log "Secret generated: $SECRET"

# ==============================
# 5. Get Server IP
# ==============================
SERVER_IP=$(curl -s https://api.ipify.org)
log "Server IP: $SERVER_IP"

# ==============================
# 6. Get Proxy Tag
# ==============================
section "Proxy Tag Setup"
echo ""
warn "To enable sponsored channel, follow these steps:"
echo "  1. Open Telegram and message @MTProxybot"
echo "  2. Send /newproxy"
echo "  3. Enter IP: $SERVER_IP"
echo "  4. Enter Port: 443"
echo "  5. Enter Secret: $SECRET"
echo "  6. Copy the proxy tag you receive"
echo ""
read -p "Enter your proxy tag (or press Enter to skip): " PROXY_TAG

# ==============================
# 7. Create systemd Service
# ==============================
section "Creating systemd Service"

PROXY_TAG_FLAG=""
if [ -n "$PROXY_TAG" ]; then
    PROXY_TAG_FLAG="--proxy-tag $PROXY_TAG \\"
    log "Proxy tag will be included"
else
    warn "No proxy tag provided, skipping sponsored channel"
fi

cat > /etc/systemd/system/mtproxy.service << SERVICE
[Unit]
Description=MTProxy Telegram
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/MTProxy
ExecStart=/opt/MTProxy/objs/bin/mtproto-proxy \\
  -u nobody \\
  -p 8888 \\
  -H 443 \\
  -S $SECRET \\
  --aes-pwd /opt/MTProxy/proxy-secret /opt/MTProxy/proxy-multi.conf \\
  $([ -n "$PROXY_TAG" ] && echo "--proxy-tag $PROXY_TAG \\")
  --http-stats \\
  --max-special-connections 5000 \\
  -M $(nproc)
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable mtproxy
systemctl start mtproxy
sleep 2
systemctl is-active --quiet mtproxy && log "MTProxy service started" || error "MTProxy service failed to start"

# ==============================
# 8. Firewall
# ==============================
section "Configuring Firewall"
ufw allow 443/tcp
ufw allow 443/udp
ufw allow 22/tcp
ufw --force enable
log "Firewall configured"

# ==============================
# 9. Cron for Auto-Update Config
# ==============================
section "Setting up Auto-Update"
(crontab -l 2>/dev/null; echo "0 */6 * * * curl -s https://core.telegram.org/getProxyConfig -o /opt/MTProxy/proxy-multi.conf") | crontab -
log "Cron job added (every 6 hours)"

# ==============================
# 10. Install proxy-stats
# ==============================
section "Installing proxy-stats"
cat > /usr/local/bin/proxy-stats << 'STATS'
#!/bin/bash
STATS=$(curl -s http://localhost:8888/stats)

to_mb() { echo "scale=2; $1/1048576" | bc; }

RX=$(echo "$STATS" | grep '^tcp_readv_bytes' | awk '{print $2}')
TX=$(echo "$STATS" | grep '^tcp_writev_bytes' | awk '{print $2}')
UPTIME=$(echo "$STATS" | grep '^uptime' | awk '{print $2}')
UPTIME_H=$(echo "scale=1; $UPTIME/3600" | bc)
RAM=$(echo "$STATS" | grep '^vmrss_bytes' | awk '{print $2}')
IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
MONTH=$(vnstat -i $IFACE --oneline 2>/dev/null | awk -F';' '{print $9}')
MONTH_TX=$(vnstat -i $IFACE --oneline 2>/dev/null | awk -F';' '{print $10}')
TOTAL=$(vnstat -i $IFACE --oneline 2>/dev/null | awk -F';' '{print $11}')

echo "=============================="
echo "     MTProxy Quick Stats      "
echo "=============================="
echo "🟢 Active Users:      $(echo "$STATS" | grep '^total_encrypted_connections' | awk '{print $2}')"
echo "🔄 Total Connections: $(echo "$STATS" | grep '^total_allocated_connections' | awk '{print $2}')"
echo "------------------------------"
echo "⬇️  Session Download: $(to_mb $RX) MB"
echo "⬆️  Session Upload:   $(to_mb $TX) MB"
echo "------------------------------"
echo "📅 Month Download:    $MONTH"
echo "📅 Month Upload:      $MONTH_TX"
echo "📊 Month Total:       $TOTAL"
echo "------------------------------"
echo "⏱️  Uptime:           ${UPTIME_H} hrs"
echo "❌ Errors:            $(echo "$STATS" | grep '^mtproto_proxy_errors' | awk '{print $2}')"
echo "🚫 LRU Drops:         $(echo "$STATS" | grep '^connections_failed_lru' | awk '{print $2}')"
echo "🌊 Flood Blocks:      $(echo "$STATS" | grep '^connections_failed_flood' | awk '{print $2}')"
echo "------------------------------"
echo "📡 Sponsor Tag:       $(echo "$STATS" | grep '^proxy_tag_set' | awk '{print $2}')"
echo "⚙️  Workers:          $(echo "$STATS" | grep '^workers' | awk '{print $2}')"
echo "💾 RAM Usage:         $(to_mb $RAM) MB"
echo "=============================="
STATS
chmod +x /usr/local/bin/proxy-stats
log "proxy-stats installed"

# ==============================
# Done
# ==============================
section "Setup Complete"
echo ""
echo -e "  ${GREEN}Secret:${NC}   $SECRET"
echo -e "  ${GREEN}IP:${NC}       $SERVER_IP"
echo -e "  ${GREEN}Port:${NC}     443"
echo ""
echo -e "  ${GREEN}Proxy Link:${NC}"
echo "  https://t.me/proxy?server=$SERVER_IP&port=443&secret=$SECRET"
echo ""
echo -e "  Run ${YELLOW}proxy-stats${NC} anytime to check status"
echo ""
EOF
chmod +x /root/mtproxy-setup.sh
echo "Done! Run with: bash /root/mtproxy-setup.sh"
