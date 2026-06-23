# 🚀 MTProxy Auto Setup

A one-command script to install, configure, and run a **Telegram MTProto Proxy** on your Ubuntu/Debian server.

---

## ✨ Features

- ✅ Installs all dependencies automatically
- ✅ Clones and builds [official MTProxy](https://github.com/TelegramMessenger/MTProxy) from source
- ✅ Generates a random secret key
- ✅ Creates a `systemd` service (auto-start on reboot)
- ✅ Configures UFW firewall (port 443)
- ✅ Sets up a cron job to refresh Telegram config every 6 hours
- ✅ Installs `proxy-stats` CLI tool for live monitoring
- ✅ Optional sponsored channel support via `@MTProxybot`

---

## 📋 Requirements

- Ubuntu 20.04 / 22.04 / 24.04 (or Debian equivalent)
- Root access
- Open port **443** on your server/firewall

---

## ⚡ Quick Install

```bash
bash <(curl -s https://raw.githubusercontent.com/amir-rxx/mtproxy-setup/main/install.sh)
```

> The script will download the setup file to `/root/mtproxy-setup.sh` and run it automatically.

---

## 🔧 What It Does (Step by Step)

| Step | Action |
|------|--------|
| 1 | Updates system and installs dependencies |
| 2 | Clones and builds MTProxy from source |
| 3 | Fetches Telegram's official proxy config |
| 4 | Generates a random 16-byte secret |
| 5 | Detects your server's public IP |
| 6 | Optionally registers with `@MTProxybot` for sponsored channel |
| 7 | Creates and starts a `systemd` service |
| 8 | Opens port 443 via UFW |
| 9 | Sets up auto-update cron (every 6 hours) |
| 10 | Installs the `proxy-stats` monitoring tool |

---

## 📡 Proxy Link

After installation, you'll see output like:

```
==============================
     Setup Complete
==============================
  Secret:   a1b2c3d4e5f6...
  IP:       1.2.3.4
  Port:     443

  Proxy Link:
  https://t.me/proxy?server=1.2.3.4&port=443&secret=a1b2c3d4e5f6...
```

Share the proxy link with your users to connect directly via Telegram.

---

## 📊 Monitoring

After installation, run this command anytime to check live stats:

```bash
proxy-stats
```

Sample output:

```
==============================
     MTProxy Quick Stats
==============================
🟢 Active Users:      42
🔄 Total Connections: 150
------------------------------
⬇️  Session Download: 120.50 MB
⬆️  Session Upload:   85.30 MB
------------------------------
📅 Month Download:    2.10 GiB
📅 Month Upload:      1.80 GiB
📊 Month Total:       3.90 GiB
------------------------------
⏱️  Uptime:           12.5 hrs
💾 RAM Usage:         18.20 MB
==============================
```

---

## 🔁 Service Management

```bash
# Check status
systemctl status mtproxy

# Restart
systemctl restart mtproxy

# Stop
systemctl stop mtproxy

# View logs
journalctl -u mtproxy -f
```

---

## 💰 Sponsored Channel (Optional)

To monetize your proxy and support a Telegram channel:

1. Open Telegram and message [@MTProxybot](https://t.me/MTProxybot)
2. Send `/newproxy`
3. Enter your server IP and port `443`
4. Enter your generated secret
5. Copy the **proxy tag** and paste it during setup

---

## 🛡️ Security Notes

- The script opens **only port 443** (TCP + UDP) and **22** (SSH) via UFW
- The proxy runs under the `nobody` user for isolation
- Supports up to **5000 concurrent connections** by default
- Worker count is auto-set based on your CPU core count

---

## 📁 File Locations

| File | Path |
|------|------|
| MTProxy binary | `/opt/MTProxy/objs/bin/mtproto-proxy` |
| Systemd service | `/etc/systemd/system/mtproxy.service` |
| Proxy secret | `/opt/MTProxy/proxy-secret` |
| Telegram config | `/opt/MTProxy/proxy-multi.conf` |
| Stats tool | `/usr/local/bin/proxy-stats` |

---

## 📄 License

MIT License — free to use and modify.
