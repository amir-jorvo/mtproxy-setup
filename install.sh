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
# 0. Root Check
# ==============================
if [ "$EUID" -ne 0 ]; then
    error "Please run as root (use sudo)"
fi

# ==============================
# 1. Port Configuration & Check
# ==============================
section "Port Configuration"
read -p "Enter MTProxy port (Default: 443): " PORT
PORT=${PORT:-443}

if command -v ss >/dev/null 2>&1; then
    if ss -tuln | grep -qE ":${PORT}\b"; then
        error "Port $PORT is already in use! Please stop the conflicting service or choose another port."
    fi
fi
log "Using Port: $PORT"

# ==============================
# 2. Update & Install Dependencies
# ==============================
section "Installing Dependencies"
apt update || error "apt update failed"
apt install -y git build-essential libssl-dev zlib1g-dev xxd curl bc vnstat dos2unix || error "apt install failed"
log "Dependencies installed"

# ==============================
# 3. Clone & Build MTProxy
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
# 4. Fetch Telegram Config
# ==============================
section "Fetching Telegram Config"
curl -s https://core.telegram.org/getProxySecret -o /opt/MTProxy/proxy-secret || error "Failed to fetch proxy-secret"
curl -s https://core.telegram.org/getProxyConfig -o /opt/MTProxy/proxy-multi.conf || error "Failed to fetch proxy-multi.conf"
log "Telegram config fetched"

# ==============================
# 5. Generate Secret
# ==============================
section "Generating Secret"
SECRET=$(head -c 16 /dev/urandom | xxd -ps)
log "Secret generated: $SECRET"

# ==============================
# 6. Get Server IP
# ==============================
SERVER_IP=$(curl -s https://api.ipify.org)
log "Server IP: $SERVER_IP"

# ==============================
# 7. Get Proxy Tag
# ==============================
section "Proxy Tag Setup"
echo ""
warn "To enable sponsored channel, follow these steps:"
echo "  1. Open Telegram and message @MTProxybot"
echo "  2. Send /newproxy"
echo "  3. Enter IP: $SERVER_IP"
echo "  4. Enter Port: $PORT"
echo "  5. Enter Secret: $SECRET"
echo "  6. Copy the proxy tag you receive"
echo ""
read -p "Enter your proxy tag (or press Enter to skip): " PROXY_TAG

# ==============================
# 8. Create systemd Service
# ==============================
section "Creating systemd Service"

if [ -n "$PROXY_TAG" ]; then
    log "Proxy tag will be included"
else
    warn "No proxy tag provided, skipping sponsored channel"
fi

# گرفتن تعداد هسته های سرور برای جایگذاری دقیق
CORES=$(nproc)

cat > /etc/systemd/system/mtproxy.service << SERVICE
[Unit]
Description=MTProxy Telegram
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/MTProxy
ExecStart=/opt/MTProxy/objs/bin/mtproto-proxy \
  -u nobody \
  -p 8888 \
  -H $PORT \
  -S $SECRET \
  --aes-pwd /opt/MTProxy/proxy-secret /opt/MTProxy/proxy-multi.conf \
SERVICE

if [ -n "$PROXY_TAG" ]; then
    echo "  --proxy-tag $PROXY_TAG \\" >> /etc/systemd/system/mtproxy.service
fi

cat >> /etc/systemd/system/mtproxy.service << SERVICE
  --http-stats \
  --max-special-connections 5000 \
  -M $CORES
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
# 9. Firewall
# ==============================
section "Configuring Firewall"
ufw allow $PORT/tcp
ufw allow $PORT/udp
ufw allow 22/tcp
ufw --force enable
log "Firewall configured"

# ==============================
# 10. Cron for Auto-Update Config
# ==============================
section "Setting up Auto-Update"
(crontab -l 2>/dev/null | grep -v "getProxyConfig"; echo "0 */6 * * * curl -s https://core.telegram.org/getProxyConfig -o /opt/MTProxy/proxy-multi.conf") | crontab -
log "Cron job added (every 6 hours)"

# ==============================
# 11. Install proxy-stats
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
echo "🟢 Active Users:      $(echo "$STATS" | grep '^active_inbound_connections' | awk '{print $2}')"
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
echo -e "  ${GREEN}Port:${NC}     $PORT"
echo ""
echo -e "  ${GREEN}Proxy Link:${NC}"
echo "  https://t.me/proxy?server=$SERVER_IP&port=$PORT&secret=$SECRET"
echo ""
echo -e "  Run ${YELLOW}proxy-stats${NC} anytime to check status"
echo ""
