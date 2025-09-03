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
    max-cache-size 0;               // Unlimited cache sesuai RAM
    max-ncache-ttl 1w;
    max-cache-ttl 1w;
    recursive-clients 100000;       // Sangat tinggi, dibatasi hardware
    max-udp-size 65535;             // Maksimal UDP packet
    minimal-responses yes;
    version none;
    dnssec-validation auto;
    auth-nxdomain no;
    allow-transfer { none; };
    notify no;
    querylog no;
};
EOF

    # Tingkatkan limit OS untuk BIND
    echo_info "Meningkatkan limit file descriptor..."
    echo "bind hard nofile 65536" >> /etc/security/limits.conf
    echo "bind soft nofile 65536" >> /etc/security/limits.conf

    # Optimasi kernel UDP/TCP stack
    echo_info "Mengoptimalkan kernel networking..."
    sysctl -w net.core.somaxconn=65535
    sysctl -w net.core.netdev_max_backlog=65535
    sysctl -w net.ipv4.udp_mem="65536 131072 262144"
    sysctl -w net.ipv4.udp_rmem_min=8192
    sysctl -w net.ipv4.udp_wmem_min=8192
    sysctl -w net.ipv4.tcp_max_syn_backlog=65535

    echo_status "BIND ultra-high perf siap, hardware server jadi batas utama"
}

# Jalankan ultra-perf setelah konfigurasi RPZ
utama_ultra() {
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
