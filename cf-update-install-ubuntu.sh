#!/usr/bin/env bash

# --- Root permission check ---
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This installer must be run as root or with sudo."
    echo "Please run again using: sudo $0"
    exit 1
fi
# -----------------------------
TARGET_DIR="/opt/cf-update-v2"
TARGET_FILE="${TARGET_DIR}/cf-update-v2.py"
SERVICE_FILE="/etc/systemd/system/cf-update-v2.service"
TIMER_FILE="/etc/systemd/system/cf-update-v2.timer"

# Sample values Cloudflare 
DEF_AUTH_EMAIL="test@test.com"
DEF_AUTH_KEY="API-KEY"
DEF_DOMAIN="test.com"
DEF_HOSTNAME="hostname"

echo "=== Cloudflare Update Script Installer ==="
echo
echo "Please enter values — press Enter to use the default."
echo

read -p "Auth Email (Default: ${DEF_AUTH_EMAIL}): " AUTH_EMAIL
AUTH_EMAIL="${AUTH_EMAIL:-$DEF_AUTH_EMAIL}"

read -p "Auth Key (Default: ${DEF_AUTH_KEY}): " AUTH_KEY
AUTH_KEY="${AUTH_KEY:-$DEF_AUTH_KEY}"

read -p "Domain (Default: ${DEF_DOMAIN}): " DOMAIN
DOMAIN="${DOMAIN:-$DEF_DOMAIN}"

read -p "Hostname (Default: ${DEF_HOSTNAME}): " HOSTNAME
HOSTNAME="${HOSTNAME:-$DEF_HOSTNAME}"

echo
echo "Creating directory ${TARGET_DIR} ..."
mkdir -p "${TARGET_DIR}"

# Backup existing file
if [[ -f "${TARGET_FILE}" ]]; then
    cp "${TARGET_FILE}" "${TARGET_FILE}.bak_$(date +%Y%m%d-%H%M%S)"
    echo "Existing Python file backed up."
fi

echo "Writing Python script to ${TARGET_FILE} ..."
cat <<EOF > "${TARGET_FILE}"
#!/usr/bin/env python3
import requests
import json

def get_headers(auth_email, auth_key):
    return {
        "X-Auth-Email": auth_email,
        "X-Auth-Key": auth_key,
        "Content-Type": "application/json",
    }

def get_zone_id(auth_email, auth_key, domain):
    url = f"https://api.cloudflare.com/client/v4/zones?name={domain}"
    headers = get_headers(auth_email, auth_key)
    response = requests.get(url, headers=headers)
    if response.status_code != 200:
        handle_error(response)
        return None
    else:
        return response.json()["result"][0]["id"]

def get_record_id(auth_email, auth_key, domain, hostname):
    zone_id = get_zone_id(auth_email, auth_key, domain)
    if zone_id is None:
        return None
    url = f"https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records?name={hostname}.{domain}"
    headers = get_headers(auth_email, auth_key)
    response = requests.get(url, headers=headers)
    if response.status_code != 200:
        handle_error(response)
        return None
    else:
        return response.json()["result"][0]["id"]

def update_dns_record(auth_email, auth_key, domain, hostname):
    zone_id = get_zone_id(auth_email, auth_key, domain)
    record_id = get_record_id(auth_email, auth_key, domain, hostname)
    if zone_id is not None and record_id is not None:
        new_ip = requests.get('https://api.ipify.org').text
        url = f"https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records/{record_id}"
        headers = get_headers(auth_email, auth_key)
        data = {
            "type": "A",
            "name": hostname,
            "content": new_ip,
            "ttl": 1,
        }
        response = requests.put(url, headers=headers, data=json.dumps(data))
        if response.status_code != 200:
            handle_error(response)
        else:
            print("DNS record updated successfully")
            print("FQDN:" + hostname + "." + domain)
            print("IP:  "+ new_ip )

def handle_error(response):
    error_message = response.json()['errors'][0]['message']
    print(f"Error: {error_message}")

if __name__ == "__main__":
    # CUSTOMIZE THESE VARIABLES ---  START --- !!!
    auth_email = "${AUTH_EMAIL}"
    auth_key = "${AUTH_KEY}"
    domain = "${DOMAIN}"
    hostname = "${HOSTNAME}"
    # CUSTOMIZE THESE VARIABLES ---  END --- !!!

    print(f"Updating DNS record: {hostname}.{domain}")
    update_dns_record(auth_email, auth_key, domain, hostname)
EOF

chmod +x "${TARGET_FILE}"

echo "Writing systemd service to ${SERVICE_FILE} ..."
cat <<EOF > "${SERVICE_FILE}"
[Unit]
Description=Update CF DNS Record

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 /opt/cf-update-v2/cf-update-v2.py
EOF

echo "Writing systemd timer to ${TIMER_FILE} ..."
cat <<EOF > "${TIMER_FILE}"
[Unit]
Description=Timer for cf-update-v2

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
Unit=cf-update-v2.service

[Install]
WantedBy=timers.target
EOF

echo "Reloading systemd ..."
systemctl daemon-reload

echo "Enabling and starting timer ..."
systemctl enable --now cf-update-v2.timer

echo
echo "Installation complete."
echo "The script will now run every minute."
echo "You can check the status with:"
echo "  systemctl status cf-update-v2.timer"
