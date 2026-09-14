//! OUI (Organizationally Unique Identifier) manufacturer database and device classification.

pub struct VendorInfo {
    pub name: &'static str,
    pub category: &'static str, // "router", "phone", "pc", "iot", "tv", "generic"
    pub icon: &'static str,     // Nerd Font or Unicode icon
}

pub fn lookup_vendor(mac: &str) -> VendorInfo {
    let clean = mac.to_uppercase().replace(['-', ':', '.'], "");
    if clean.len() < 6 {
        return VendorInfo {
            name: "Unknown Device",
            category: "generic",
            icon: "󰇄",
        };
    }

    let prefix = &clean[0..6];

    match prefix {
        // Apple
        "000393" | "000A27" | "000A95" | "000D93" | "0010FA" | "001124" | "001451" | "0016CB"
        | "0017F2" | "0019E3" | "001B63" | "001C42" | "001C7B" | "001CB3" | "001D4F" | "001E52"
        | "001EC2" | "001F5B" | "001FF3" | "0021E9" | "002241" | "002312" | "002332" | "002369"
        | "0023DF" | "002436" | "002500" | "00254B" | "002608" | "00264A" | "0026B0" | "0026BB"
        | "102D41" | "1040F3" | "1094BB" | "109ADD" | "14109F" | "147DD7" | "186590" | "18AF61"
        | "28CFE9" | "3C15C2" | "40A6D9" | "685B35" | "703EAC" | "784F43" | "88665A" | "9C207B"
        | "A483E7" | "AC1F74" | "B418D1" | "BC5436" | "C82A14" | "DC2B61" | "E0B9BA" | "F01898" => {
            VendorInfo {
                name: "Apple, Inc.",
                category: "phone",
                icon: "󰀵",
            }
        }

        // Samsung
        "0007AB" | "001247" | "001599" | "00166B" | "0017C9" | "001A8A" | "001BD7" | "001C43"
        | "001DFE" | "002119" | "0023D7" | "002454" | "002637" | "0808C2" | "1489FD" | "24F5AA"
        | "3423BA" | "380195" | "444E1A" | "503123" | "505527" | "5C0A5B" | "608334" | "78471D"
        | "8425DB" | "946372" | "A0B439" | "B0C559" | "CC07AB" | "D059E4" | "E4E0C5" => {
            VendorInfo {
                name: "Samsung Electronics",
                category: "phone",
                icon: "󰏲",
            }
        }

        // Intel (Laptops / PCs / Motherboards)
        "0002B3" | "000347" | "000423" | "0007E9" | "000C76" | "000E0C" | "001302" | "001320"
        | "0013E8" | "001500" | "001517" | "001676" | "0018DE" | "0019D1" | "001B21" | "001C23"
        | "001D09" | "001D6B" | "001E67" | "00216A" | "0022FB" | "002315" | "0024D7" | "0026C7"
        | "3413E8" | "4851B7" | "6805CA" | "7C214A" | "8086F2" | "94E6F7" | "A44CC8" | "D83B22" => {
            VendorInfo {
                name: "Intel Corporation",
                category: "pc",
                icon: "󰌢",
            }
        }

        // Raspberry Pi
        "B827EB" | "DCA632" | "E45F01" | "28CDC1" => VendorInfo {
            name: "Raspberry Pi Foundation",
            category: "iot",
            icon: "󰐿",
        },

        // Espressif (ESP8266 / ESP32 IoT devices)
        "18FE34" | "240AC4" | "246F28" | "24B2DE" | "2C3AE8" | "30AEA4" | "3C71BF" | "40F520"
        | "4C7525" | "545A46" | "600194" | "68C63A" | "807D3A" | "840D8E" | "84F3EB" | "9097D5"
        | "A020A6" | "A4CF12" | "AC67B2" | "B4E62D" | "BCDD22" | "C44F33" | "CC50E3" | "D8A01D" => {
            VendorInfo {
                name: "Espressif Systems (IoT)",
                category: "iot",
                icon: "󱐋",
            }
        }

        // TP-Link
        "0019E0" | "002127" | "0023CD" | "002586" | "14CC20" | "1C3BF3" | "30B5C2" | "50C7BF"
        | "60E327" | "6C198F" | "7405A5" | "8416F9" | "98DEEE" | "A42BB0" | "B04E26" | "C025E9" => {
            VendorInfo {
                name: "TP-Link Technologies",
                category: "router",
                icon: "󰈀",
            }
        }

        // MikroTik
        "000C42" | "488F5A" | "64D154" | "B869F4" | "CC2DE0" | "D4CA6D" | "E48D8C" => {
            VendorInfo {
                name: "MikroTik",
                category: "router",
                icon: "󰈀",
            }
        }

        // Cisco / Linksys
        "00000C" | "000142" | "000163" | "000196" | "0001C7" | "0001C9" | "000216" | "000217"
        | "00024A" | "00027D" | "0002B9" | "0002BA" | "0002FC" | "000331" | "00036B" | "0003E3"
        | "0016B6" | "001839" | "001A70" | "001BD4" | "001C0F" | "001C58" | "001D45" | "001D70" => {
            VendorInfo {
                name: "Cisco Systems",
                category: "router",
                icon: "󰈀",
            }
        }

        // Ruijie / Reyee Networks
        "AC712E" | "001A79" | "14144B" | "345F98" | "702E22" | "88C397" => VendorInfo {
            name: "Ruijie Networks",
            category: "router",
            icon: "󰈀",
        },

        // Xiaomi
        "00EC0A" | "04B167" | "18B79E" | "286C07" | "348062" | "50642B" | "640980" | "7811DC"
        | "7C1DDA" | "8CBEBE" | "C40BCB" | "D4970B" | "F013C3" => VendorInfo {
            name: "Xiaomi Communications",
            category: "phone",
            icon: "󰏲",
        },

        // Huawei
        "001882" | "001E10" | "00259E" | "002E44" | "0425C5" | "08E84F" | "104780" | "145798"
        | "24DF6A" | "346B46" | "404D8E" | "4846FB" | "707B53" | "844bf0" | "A0086F" => {
            VendorInfo {
                name: "Huawei Device Co.",
                category: "phone",
                icon: "󰏲",
            }
        }

        // Google
        "001A11" | "3C5AB4" | "546009" | "94EB2C" | "D83C69" | "F4F5D8" => {
            VendorInfo {
                name: "Google, Inc.",
                category: "phone",
                icon: "󰊭",
            }
        }

        // Amazon (Echo, Kindle, FireTV)
        "00FC8B" | "38F73D" | "40B4CD" | "44650D" | "50F5DA" | "6837E9" | "747548" | "AC63BE" => {
            VendorInfo {
                name: "Amazon Technologies",
                category: "iot",
                icon: "󰒢",
            }
        }

        // Sony (PlayStation / Bravia TV)
        "00014A" | "00041F" | "001315" | "0015C1" | "0019C5" | "001D0D" | "0024BE" | "709E29"
        | "F8461C" => VendorInfo {
            name: "Sony Interactive / TV",
            category: "tv",
            icon: "󰖺",
        },

        // LG Electronics (WebOS TV / Appliances)
        "0005F9" | "001417" | "0019C7" | "001C62" | "001E75" | "002483" | "10683F" | "203DB2" => {
            VendorInfo {
                name: "LG Electronics",
                category: "tv",
                icon: "󰵔",
            }
        }

        // VMware / Virtual Machines
        "005056" | "000C29" | "000569" => VendorInfo {
            name: "VMware Virtual Machine",
            category: "pc",
            icon: "󰢹",
        },

        // Dell
        "00065B" | "000874" | "000BDB" | "000D56" | "001143" | "001372" | "001422" | "0016F0" => {
            VendorInfo {
                name: "Dell Inc.",
                category: "pc",
                icon: "󰌢",
            }
        }

        // HP
        "0001E6" | "0002A5" | "0004EA" | "000802" | "000883" | "000B80" | "000D9D" | "000E7F" => {
            VendorInfo {
                name: "HP Inc.",
                category: "pc",
                icon: "󰌢",
            }
        }

        // Asus
        "000C6E" | "000E8C" | "0011D8" | "0013D4" | "0015F2" | "001731" | "0018F3" | "001A92" => {
            VendorInfo {
                name: "ASUSTeK Computer",
                category: "router",
                icon: "󰈀",
            }
        }

        // Ubiquiti / UniFi
        "00156D" | "002722" | "24A43C" | "687251" | "7483C2" | "802AA8" | "B4FBE4" | "DC9FDB" => {
            VendorInfo {
                name: "Ubiquiti Networks",
                category: "router",
                icon: "󰈀",
            }
        }

        _ => VendorInfo {
            name: "Unknown Vendor",
            category: "generic",
            icon: "󰛳",
        },
    }
}
