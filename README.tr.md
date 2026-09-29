# NetRadar - Omarchy Linux İçin Yerel Ağ Tarayıcısı ve Cihaz Radarı

[![Omarchy Verified Plugin](https://img.shields.io/badge/Omarchy-Verified_Plugin-22c55e?style=for-the-badge&logo=omarchy)](https://github.com/ozdil)

[![Buy Me A Coffee](https://img.shields.io/badge/Buy_Me_A_Coffee-Support_Development-FFDD00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black)](https://buymeacoffee.com/ozdil)

> **Omarchy Linux masaüstü ortamı için ultra hızlı, minimalist ve güvenli yerel ağ tarayıcısı ve cihaz radarı.**

Yerel **Quickshell (QML)** ve sertleştirilmiş **Rust Motoru (`netradar-engine`)** ile geliştirilen NetRadar; root yetkisine ihtiyaç duymadan, donanım üreticisi tespiti ve tam Wayland/Omarchy tema uyumuyla yerel Wi-Fi ve Ethernet ağınızdaki cihazları izler.

---

## Yetenekler ve Özellikler

- **Root Yetkisi Olmadan Hızlı Keşif (Zero Root / No Setuid):**
  - Linux `/proc/net/arp`, çekirdek komşuluk tablosu (`ip -j neigh`) ve güvenli mDNS / ters DNS çözümlemesi ile tamamen kullanıcı yetkileriyle çalışır.
  - Tehlikeli raw paket sürücüsü veya setuid yetki yükseltmesi gerektirmez.
- **Anında Donanım Üreticisi (OUI) Tespiti:**
  - Gömülü yüksek hızlı MAC ön eki arama tablosu.
  - Apple, Samsung, Intel, Google, Xiaomi, Huawei, Amazon, Raspberry Pi, Espressif (IoT), TP-Link, MikroTik, Cisco vb. cihazları otomatik sınıflandırır.
- **Wayland Pano Entegrasyonu:**
  - IP ve MAC adresleri için tek tıkla kopyalama hapları ve anlık görsel geri bildirim banner'ı.
- **Güvenli SSH ve Web Başlatıcıları:**
  - Tespit edilen cihazların web arayüzlerine (`--web`) veya SSH oturumlarına (`--ssh`) doğrudan güvenli terminal/tarayıcı fallback zinciri (`xdg-terminal-exec`, `foot`, `alacritty`, `kitty`) üzerinden bağlanma.
- **Klavye Odaklı Navigasyon:**
  - Ok tuşlarıyla seçim, p (ping), w (web arayüzü), h (ssh), c (ip kopyala), r / s (ağ tara) ve a (künye overlay) kısayolları.
- **Omarchy Dinamik OLED Tema Desteği:**
  - Omarchy sistem renkleri ve `JetBrainsMono Nerd Font` tipografi standardı ile kusursuz uyum.
- **Çift Modlu Çalışma:**
  - **Quickshell Panel Widget'ı (`Panel.qml`)**: Üst bar bildirim rozeti ve kompakt radar açılır menüsü.
  - **Bağımsız Masaüstü Uygulaması (`netradar`, `shell.qml`)**: Genişletilmiş kontrol paneli ve teşhis görünümü.

---

## Kurulum ve Derleme

### Omarchy Eklentisini Ekleme
```bash
omarchy plugin add https://github.com/ozdil/omarchy-netradar.git
```

### Motoru Kaynaktan Derleme
```bash
cd ~/.config/omarchy/plugins/ozdil.netradar
cargo build --release
install -m 755 target/release/netradar-engine ./netradar-engine
```

### Omarchy Shell Yapılandırması
`~/.config/omarchy/shell.json` dosyasında `bar.layout.right` altına ekleyin:
```json
{
  "id": "ozdil.netradar"
}
```

Kabuğu yeniden başlatın:
```bash
omarchy-restart-shell
```

---

## Güvenlik Standartları (Zero-Trust)

- Sadece RFC 1918 ve yerel IPv4 blokları taranır; harici ağlara yönelik taramalar engellenir.
- 0600 dosya ve 0700 dizin izinleriyle atomik dosya depolama.
- Tüm süreçler sınırlandırılmış tamponlar ve zaman aşımları ile çalıştırılır.

---

## Lisans

MIT Lisansı. Ayrıntılar için [LICENSE](LICENSE) dosyasına bakınız.
