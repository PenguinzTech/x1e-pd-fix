# x1e80100 USB PD Charging Fix for Linux

**Fix for extremely slow USB-C Power Delivery charging on Qualcomm Snapdragon X Elite (X1E80100) laptops running Linux.** Increases charging from ~12W to 60W+ (5x improvement).

> Tested on **ASUS Vivobook S 15 / Vivobook S Plus X Elite (S5507QA)** — should work on any X1E80100 laptop including Dell Latitude 7455, Lenovo ThinkPad T14s Gen 6, HP EliteBook Ultra, Samsung Galaxy Book4 Edge, and other Snapdragon X Elite / X Plus devices.

**Keywords:** Snapdragon X Elite, X1E80100, USB-C slow charging, Linux, Ubuntu, qcom_battmgr, PMIC GLINK, power delivery, ASUS Vivobook, Dell Latitude, Lenovo ThinkPad, battery charging fix

## The Problem

On Snapdragon X Elite / X Plus laptops (ASUS Vivobook S 15, Vivobook S Plus X Elite, Dell Latitude 7455, Lenovo ThinkPad T14s Gen 6, etc.), USB-C PD charging under Linux is often limited to ~12W regardless of charger wattage. Windows charges the same hardware at 60W+ with the same charger.

**Symptoms:**
- `power_now` reports only 10-15W while charging
- `qcom-battmgr-ac` shows `ONLINE=0` (system doesn't recognize AC power)
- `qcom-battmgr-usb` shows `ONLINE=1` but with `USB_TYPE=Unknown`
- UCSI layer sees PD (`USB_TYPE=C [PD] PD_PPS`) but battery manager doesn't
- Charging takes 5+ hours on a laptop that should charge in ~1.5 hours

## Root Cause

The upstream `qcom_battmgr` driver maps X1E80100 to the `QCOM_BATTMGR_SC8280XP` variant, which:

1. **Only exposes `ONLINE` for USB** — no voltage, current, or type information
2. **Never queries USB properties** from firmware individually (uses bulk battery status notifications only)
3. **Never sets USB adapter type** — firmware defaults to basic USB classification instead of PD
4. **Never uses `BATTMGR_USB_PROPERTY_SET`** — opcode `0x33` exists but is dead code

The PMIC firmware classifies the charger as basic USB and limits charging current accordingly.

## The Fix

This patch creates a dedicated `QCOM_BATTMGR_X1E80100` variant that:

1. **Separates X1E80100 from SC8280XP** — allows X1E-specific behavior
2. **Hybrid callback routing** — uses SC8280XP-style callbacks for battery status notifications, SM8350-style individual property queries for USB properties
3. **Auto-configures PD on charger detect** — sends `USB_ADAP_TYPE=PD`, `USB_TYPE=PD`, `USB_CURR_MAX`, `USB_INPUT_CURR_LIMIT`, and `USB_VOLT_MAX` to firmware when USB charging is detected
4. **Exposes full USB properties** — voltage, current, type, and writable `input_current_limit` via sysfs
5. **Module parameter** — `pd_current_limit_ua` (default 5A) for tuning

## Results

| | Before | After |
|---|--------|-------|
| Battery charging power | ~12W | ~61W |
| UCSI current draw | 2.5A | 4.3A |
| USB type reported | Unknown | PD |
| Charger input power | ~15W | ~86W (20V × 4.3A) |
| Time to full (70Wh battery) | ~6 hours | ~1.2 hours |

Tested with a 100W USB-C PD charger. The firmware properly renegotiates the PD contract to draw up to 4.3A at 20V after the patch configures adapter type and current limits.

## Tested On

- **Laptop:** ASUS Vivobook S 15 / Vivobook S Plus X Elite (S5507QA / S5507QAD)
- **SoC:** Qualcomm Snapdragon X Elite (X1E80100)
- **OS:** Ubuntu 25.10 (Questing Quokka)
- **Kernel:** 6.17.0-12-generic (aarch64)
- **Charger:** 100W USB-C PD (InMotion) — capped at 60W by laptop's PD sink capability

### Expected Compatible Devices

Any laptop with `qcom,x1e80100-pmic-glink` in its device tree, including:
- ASUS Vivobook S 15 / S Plus X Elite (S5507QA, S5507QAD)
- Dell Latitude 7455
- Dell Inspiron 14 Plus
- Lenovo ThinkPad T14s Gen 6
- HP EliteBook Ultra G1q
- Samsung Galaxy Book4 Edge
- Microsoft Surface Laptop 7
- Acer Swift 14 AI
- Other Snapdragon X Elite / X Plus laptops

**Please report your results** if you test on a different device!

## Installation

### Prerequisites

```bash
sudo apt install build-essential linux-headers-$(uname -r)
```

### Build

```bash
git clone https://github.com/PenguinzTech/x1e-pd-fix.git
cd x1e-pd-fix
make
```

### Install

> **IMPORTANT: A full reboot is REQUIRED after installation.** The PD charging parameters must be configured during a fresh boot — the firmware ignores them if set after the PD session is already established. Hot-reloading the module with `modprobe -r && modprobe` will NOT work. You must reboot (or fully power off and back on) for the fix to take effect.

```bash
# Backup original module
sudo cp /lib/modules/$(uname -r)/kernel/drivers/power/supply/qcom_battmgr.ko.zst \
       /lib/modules/$(uname -r)/kernel/drivers/power/supply/qcom_battmgr.ko.zst.bak

# Install patched module
sudo zstd qcom_battmgr.ko \
     -o /lib/modules/$(uname -r)/kernel/drivers/power/supply/qcom_battmgr.ko.zst --force

# Update module dependencies and initramfs
sudo depmod -a
sudo update-initramfs -u

# REBOOT IS REQUIRED — hot-reload will NOT work
sudo reboot
```

### Verify

```bash
# Check patched module loaded
cat /sys/module/qcom_battmgr/parameters/pd_current_limit_ua
# Should show: 5000000

# Check charging power
cat /sys/class/power_supply/qcom-battmgr-bat/power_now
# Should show ~30000000-40000000 (30-40W)

# Check USB type
grep -o '\[.*\]' /sys/class/power_supply/ucsi-source-psy-pmic_glink.ucsi.*/usb_type
# Should show: [PD]
```

### Revert

```bash
sudo cp /lib/modules/$(uname -r)/kernel/drivers/power/supply/qcom_battmgr.ko.zst.bak \
       /lib/modules/$(uname -r)/kernel/drivers/power/supply/qcom_battmgr.ko.zst
sudo depmod -a
sudo update-initramfs -u
sudo reboot
```

## Module Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `pd_current_limit_ua` | `5000000` (5A) | USB PD input current limit in microamps. The firmware clamps to the actual PD contract. Set to `0` to disable automatic PD configuration. |

Adjust at runtime:
```bash
echo 3000000 | sudo tee /sys/module/qcom_battmgr/parameters/pd_current_limit_ua
```

Or at boot via kernel cmdline:
```
qcom_battmgr.pd_current_limit_ua=3000000
```

## Technical Details

### Architecture

The Qualcomm X1E80100 SoC communicates with its PMIC (including the SMB2360 charger IC) through **PMIC GLINK** — a message-passing interface over shared memory. The `qcom_battmgr` driver sends requests and receives responses through this channel.

```
┌─────────┐    GLINK     ┌──────────┐    SPMI    ┌─────────┐
│  Linux   │◄───────────►│   PMIC   │◄──────────►│ SMB2360 │
│ battmgr  │  messages   │ Firmware │  registers  │ Charger │
└─────────┘              └──────────┘             └─────────┘
                                                       ▲
                                                       │ USB PD
                                                  ┌────┴────┐
                                                  │ Charger  │
                                                  │ (100W)   │
                                                  └──────────┘
```

### What the patch changes

The upstream driver treats X1E80100 identically to SC8280XP, which only reads battery status notifications containing a simple `charging_source` field (AC=1, USB=2, Wireless=3). It never queries or sets individual USB properties.

This patch:
- Adds `QCOM_BATTMGR_X1E80100` as a distinct variant
- Routes USB/WLS property responses to the SM8350 callback (which handles individual property GET/SET)
- Routes battery status responses to the SC8280XP callback (which handles bulk notifications)
- On USB charger detection, sends firmware commands to configure PD charging parameters
- Creates an X1E80100-specific USB power supply descriptor with full property support

### GLINK commands sent on charger detect

| Command | Property | Value | Purpose |
|---------|----------|-------|---------|
| `USB_PROPERTY_SET` (0x33) | `USB_ADAP_TYPE` (7) | 14 (PD) | Reclassify charger as PD |
| `USB_PROPERTY_SET` (0x33) | `USB_TYPE` (6) | 6 (PD) | Set USB type to PD |
| `USB_PROPERTY_SET` (0x33) | `USB_CURR_MAX` (4) | 5000000 | Request 5A max current |
| `USB_PROPERTY_SET` (0x33) | `USB_INPUT_CURR_LIMIT` (5) | 5000000 | Set input current limit to 5A |
| `USB_PROPERTY_SET` (0x33) | `USB_VOLT_MAX` (2) | 20000000 | Set max voltage to 20V |

### Limitations

- **Reboot required**: The PD charging parameters **must** be configured during a fresh boot. The firmware locks its charger classification early in the PD session and ignores changes made after that. Hot-reloading the module with `modprobe -r && modprobe` will **NOT** work — you must do a full reboot (or power off/on). This is the single most important thing to know about this fix.
- **Kernel updates**: The module must be rebuilt after kernel updates. Consider using DKMS for automation.

## Files

| File | Description |
|------|-------------|
| `qcom_battmgr.c` | Patched driver source |
| `qcom_battmgr.c.ubuntu_orig` | Unmodified Ubuntu 6.17.0-12 source |
| `x1e80100-usb-pd-charging-v4.patch` | Unified diff |
| `Makefile` | Out-of-tree module build |

## Contributing

If you test this on a different X1E80100 laptop, please open an issue with:
- Laptop model
- Charger wattage
- `power_now` before and after
- Kernel version
- Output of `./check-charging.sh` (in the scripts/ directory)

## License

GPL-2.0-only (same as the Linux kernel)
