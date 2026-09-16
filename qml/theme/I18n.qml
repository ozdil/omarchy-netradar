pragma Singleton
import QtQuick

QtObject {
    id: root

    // Default language: English as requested
    property string lang: "en"

    readonly property var translations: ({
        "en": {
            "app_title": "NetRadar",
            "devices": "Devices",
            "interface": "Interface",
            "gateway": "Gateway",
            "duration": "Duration",
            "scan_network": "Scan Network",
            "scanning": "Scanning...",
            "search_placeholder": "Search IP, MAC, Nickname, Hostname or Vendor...",
            "cat_all": "All",
            "cat_router": "Routers",
            "cat_pc": "Computers",
            "cat_phone": "Phones",
            "cat_iot": "IoT",
            "badge_gateway": "GATEWAY",
            "badge_this_pc": "THIS PC",
            "badge_new": "NEW DEVICE",
            "unknown_vendor": "Unknown Vendor",
            "btn_scan_ports": "Scan Ports",
            "btn_services": "Services",
            "btn_web_ui": "Web UI",
            "btn_ssh": "SSH Connect",
            "btn_ping": "Ping",
            "arp_warning": "SECURITY ALERT: Gateway MAC address changed! Possible ARP Spoofing / Rogue Router!",
            "footer_security": "Omarchy Linux Security Standards (CONTRIBUTING.md) • White Hat Defensive Radar",
            "copied": "copied",
            "opening_web": "Opening in browser: ",
            "opening_ssh": "Launching SSH terminal: ",
            "services_found": "service(s) found"
        },
        "tr": {
            "app_title": "NetRadar",
            "devices": "Cihaz",
            "interface": "Arayüz",
            "gateway": "Ağ Geçidi",
            "duration": "Süre",
            "scan_network": "Ağı Tara",
            "scanning": "Taranıyor...",
            "search_placeholder": "IP, MAC, Takma Ad, Hostname veya Üretici Ara...",
            "cat_all": "Tümü",
            "cat_router": "Yönlendirici",
            "cat_pc": "Bilgisayar",
            "cat_phone": "Telefon",
            "cat_iot": "IoT",
            "badge_gateway": "AĞ GEÇİDİ",
            "badge_this_pc": "BU BİLGİSAYAR",
            "badge_new": "YENİ CİHAZ",
            "unknown_vendor": "Bilinmeyen Üretici",
            "btn_scan_ports": "Portları Tara",
            "btn_services": "Servisler",
            "btn_web_ui": "Web Arayüzü",
            "btn_ssh": "SSH Bağlan",
            "btn_ping": "Ping",
            "arp_warning": "GÜVENLİK UYARISI: Ağ Geçidi MAC adresi değişti! Olası ARP Zehirlenmesi / Sahte Yönlendirici!",
            "footer_security": "Omarchy Linux Güvenlik Standartları (CONTRIBUTING.md) • Beyaz Şapka Savunmacı Radar",
            "copied": "kopyalandı",
            "opening_web": "Tarayıcıda açılıyor: ",
            "opening_ssh": "SSH Terminali Başlatıldı: ",
            "services_found": "servis bulundu"
        }
    })

    function t(key) {
        var dict = translations[lang] || translations["en"]
        return dict[key] || key
    }

    function toggleLang() {
        lang = (lang === "en") ? "tr" : "en"
    }
}
