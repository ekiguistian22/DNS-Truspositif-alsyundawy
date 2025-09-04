#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ===== Warna =====
MERAH="\033[1;31m"
HIJAU="\033[1;32m"
KUNING="\033[1;33m"
CYAN="\033[1;36m"
BIRU_TUA="\033[1;94m"
HIJAU_TUA="\033[1;92m"
RESET="\033[0m"

cetak_pesan() { echo -e "$1$2${RESET}"; }
echo_error() { cetak_pesan "$MERAH" "[KESALAHAN] $*" >&2; exit 1; }
echo_status() { cetak_pesan "$HIJAU" "[OK] $*"; }
echo_info() { cetak_pesan "$CYAN" "[INFO] $*"; }

# ===== Default Path & URL =====
BIND_DIR="/etc/bind"
ZONES_DIR="$BIND_DIR/zones"
RPZ_BINARY="/usr/local/bin/rpz"
RPZ_URL="https://raw.githubusercontent.com/alsyundawy/TrustPositif-To-RPZ-Binary/main/rpz"
BLOCKLIST_URL="https://raw.githubusercontent.com/alsyundawy/TrustPositif-To-RPZ-Binary/refs/heads/main/alsyundawy-blocklist/alsyundawy_blacklist.txt"
TRUST_FILE="$ZONES_DIR/trustpositif.zones"
TIMEZONE="Asia/Jakarta"

declare -A CONFIG_URLS=(
  ["named.conf.local"]="https://raw.githubusercontent.com/alsyundawy/TrustPositif-To-RPZ-Binary/main/bind/named.conf.local"
  ["named.conf.options"]="https://raw.githubusercontent.com/alsyundawy/TrustPositif-To-RPZ-Binary/main/bind/named.conf.options"
  ["safesearch.zones"]="https://raw.githubusercontent.com/alsyundawy/TrustPositif-To-RPZ-Binary/main/bind/zones/safesearch.zones"
  ["whitelist.zones"]="https://raw.githubusercontent.com/alsyundawy/TrustPositif-To-RPZ-Binary/main/bind/zones/whitelist.zones"
)

# ===== Pastikan root =====
[[ $EUID -ne 0 ]] && echo_error "Harus dijalankan sebagai root."

# ===== Fungsi validasi IP =====
valid_ip() {
    local ip=$1
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        for octet in $(echo $ip | tr '.' ' '); do
            (( octet >= 0 && octet <= 255 )) || return 1
        done
        return 0
    elif [[ $ip =~ ^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$ ]]; then
        return 0
    fi
    return 1
}

# ===== Fungsi input interaktif =====
input_variable() {
    local prompt="$1"
    local default="$2"
    read -rp "$prompt [$default]: " val
    echo "${val:-$default}"
}

# ===== Banner =====
cetak_pesan "$BIRU_TUA" "========================================"
cetak_pesan "$BIRU_TUA" "  Memulai Skrip Pengaturan DNS+RPZ"
cetak_pesan "$BIRU_TUA" "========================================"

# ===== Input Nameserver (maks 10) =====
declare -a NAMESERVERS
echo_info "Masukkan nameserver (maks 10). Tekan Enter untuk skip."
for i in $(seq 1 10); do
    while true; do
        read -rp "Nameserver #$i: " ns
        [[ -z "$ns" ]] && break 2
        valid_ip "$ns" && { NAMESERVERS+=("$ns"); break; } || echo "IP tidak valid. Masukkan IPv4 atau IPv6."
    done
done
[[ ${#NAMESERVERS[@]} -eq 0 ]] && echo_info "Tidak ada nameserver ditambahkan, skip."

# ===== Input CNAME RPZ =====
CNAME_TRUST=$(input_variable "Masukkan CNAME redirect RPZ" "lamanlabuh.resolver.id.")

# ===== Input Cron RPZ =====
CRON_INTERVAL=$(input_variable "Masukkan interval cron update RPZ (misal: 0 */12 * * *)" "0 */12 * * *")

# ===== Konfirmasi =====
cetak_pesan "$HIJAU_TUA" "=== Ringkasan Konfigurasi ==="
echo "Nameserver: ${NAMESERVERS[*]}"
echo "CNAME RPZ: $CNAME_TRUST"
echo "Cron interval RPZ: $CRON_INTERVAL"
echo "Zona waktu: $TIMEZONE"
echo "RPZ URL: $RPZ_URL"
echo "Blocklist URL: $BLOCKLIST_URL"
echo "File zona: $TRUST_FILE"
read -rp "Lanjutkan instalasi? (yes/y) " confirm
[[ "$confirm" =~ ^[Yy](es)?$ ]] || echo_error "Instalasi dibatalkan."

# ===== Fungsi utama =====
konfigurasi_resolv() {
    echo_info "Menulis /etc/resolv.conf..."
    unlink /etc/resolv.conf 2>/dev/null || true
    {
        echo "search google.com"
        for ns in "${NAMESERVERS[@]}"; do
            echo "nameserver $ns"
        done
    } > /etc/resolv.conf
    echo_status "resolv.conf dikonfigurasi"
}

atur_zona_waktu() {
    echo_info "Mengatur zona waktu ke $TIMEZONE..."
    timedatectl set-timezone "$TIMEZONE"
    echo_status "Zona waktu diatur"
}

nonaktifkan_konflik() {
    echo_info "Menonaktifkan layanan yang konflik..."
    systemctl disable --now systemd-resolved systemd-networkd-wait-online.service 2>/dev/null || true
    echo_status "Layanan yang konflik dinonaktifkan"
}

perbaiki_hosts() {
    echo_info "Memperbarui /etc/hosts..."
    hn=$(hostname)
    grep -qF "$hn" /etc/hosts || echo "127.0.0.1 $hn" >> /etc/hosts
    echo_status "/etc/hosts diperbarui"
}

perbarui_sistem() {
    echo_info "Memperbarui sistem..."
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
    DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y
    apt-get autoremove -y
    apt-get clean
    echo_status "Sistem diperbarui"
}

instal_bind() {
    echo_info "Menginstal bind9 & dnsutils..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y bind9 dnsutils || echo_error "Instalasi Bind9 gagal"
    echo_status "Bind9 diinstal"
}

siapkan_direktori() {
    echo_info "Membuat direktori zona..."
    mkdir -p "$ZONES_DIR"
    chown root:bind "$ZONES_DIR"
    chmod 755 "$ZONES_DIR"
    echo_status "$ZONES_DIR siap"
}

unduh_dan_izin() {
    local url="$1" dest="$2" pemilik="$3" izin="$4"
    echo_info "Mengunduh $url..."
    curl -# -fSL "$url" -o "$dest" || echo_error "Unduhan gagal: $url"
    chown "$pemilik" "$dest" || echo_error "Gagal ubah kepemilikan $dest"
    chmod "$izin" "$dest"
    echo_status "$dest siap"
}

sebarkan_konfigurasi() {
    echo_info "Menyebarkan konfigurasi BIND..."
    for file in "${!CONFIG_URLS[@]}"; do
        if [[ "$file" == *".zones" ]]; then
            dest_dir="$ZONES_DIR"
        else
            dest_dir="$BIND_DIR"
        fi
        unduh_dan_izin "${CONFIG_URLS[$file]}" "$dest_dir/$file" root:bind 644
    done
}

atur_trustpositif() {
    TMP_FILE="/tmp/trustpositif_domains.txt"
    unduh_dan_izin "$BLOCKLIST_URL" "$TMP_FILE" root:root 644
    echo -e "\$TTL 86400\n@ IN SOA ns1.localhost. admin.localhost. ( $(date +%Y%m%d01) 3600 1800 604800 86400 )\n@ IN NS ns1.localhost." > "$TRUST_FILE"
    while IFS= read -r domain; do
        [[ -z "$domain" || "$domain" =~ ^# ]] && continue
        echo "$domain CNAME $CNAME_TRUST" >> "$TRUST_FILE"
    done < "$TMP_FILE"
    chown root:bind "$TRUST_FILE"
    chmod 644 "$TRUST_FILE"
    rm -f "$TMP_FILE"
    echo_status "Zona TrustPositif dikonfigurasi"
}

optimasi_bind_ultra() {
    echo_info "Mengatur BIND untuk performa ultra-high..."
    mkdir -p "$BIND_DIR/options.d"
    cat <<EOF > "$BIND_DIR/named.conf.options"
options {
    directory "/var/cache/bind";
    listen-on port 53 { any; };
    listen-on-v6 port 53 { any; };
    allow-query { any; };
    recursion yes;
    allow-recursion { any; };
    max-cache-size 0;
    max-ncache-ttl 1w;
    max-cache-ttl 1w;
    recursive-clients 100000;
    max-udp-size 65535;
    minimal-responses yes;
    version none;
    dnssec-validation auto;
    auth-nxdomain no;
    allow-transfer { none; };
    notify no;
    querylog no;
};
EOF

    echo_info "Meningkatkan limit file descriptor..."
    echo "bind hard nofile 65536" >> /etc/security/limits.conf
    echo "bind soft nofile 65536" >> /etc/security/limits.conf

    echo_info "Mengoptimalkan kernel networking..."
    sysctl -w net.core.somaxconn=65535
    sysctl -w net.core.netdev_max_backlog=65535
    sysctl -w net.ipv4.udp_mem="65536 131072 262144"
    sysctl -w net.ipv4.udp_rmem_min=8192
    sysctl -w net.ipv4.udp_wmem_min=8192
    sysctl -w net.ipv4.tcp_max_syn_backlog=65535
    echo_status "BIND ultra-high perf siap, dibatasi hardware server"
}

mulai_ulang_bind() {
    echo_info "Memeriksa konfigurasi BIND..."
    named-checkconf || echo_error "Konfigurasi BIND tidak valid"
    systemctl restart bind9 || echo_error "Mulai ulang BIND gagal"
    echo_status "BIND9 berjalan"
}

atur_rpz() {
    unduh_dan_izin "$RPZ_URL" "$RPZ_BINARY" root:root 755
    (crontab -l 2>/dev/null || true; echo "$CRON_INTERVAL $RPZ_BINARY >/dev/null 2>&1") | crontab -
    echo_status "Tugas cron RPZ dijadwalkan"
}

utama() {
    atur_zona_waktu
    konfigurasi_resolv
    nonaktifkan_konflik
    perbaiki_hosts
    perbarui_sistem
    instal_bind
    siapkan_direktori
    sebarkan_konfigurasi
    atur_trustpositif
    optimasi_bind_ultra
    mulai_ulang_bind
    atur_rpz
    cetak_pesan "$HIJAU_TUA" "=== Semua tugas selesai dengan sukses! (Ultra-High Performance) ==="
}

utama
