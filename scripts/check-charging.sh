#!/bin/bash
echo "=== Charging Monitor ==="
echo ""

echo "--- Module Check ---"
printf "  %-20s %s\n" "pd_current_limit_ua:" "$(cat /sys/module/qcom_battmgr/parameters/pd_current_limit_ua 2>/dev/null || echo 'NOT FOUND (stock module?)')"

echo ""
echo "--- UCSI PD Status ---"
printf "  %-20s %s\n" "current_now:" "$(cat /sys/class/power_supply/ucsi-source-psy-pmic_glink.ucsi.01/current_now 2>/dev/null || echo N/A) uA"
printf "  %-20s %s\n" "usb_type:" "$(grep -o '\[.*\]' /sys/class/power_supply/ucsi-source-psy-pmic_glink.ucsi.01/usb_type 2>/dev/null || echo N/A)"
printf "  %-20s %s\n" "charge_type:" "$(cat /sys/class/power_supply/ucsi-source-psy-pmic_glink.ucsi.01/charge_type 2>/dev/null || echo N/A)"
printf "  %-20s %s\n" "power_op_mode:" "$(cat /sys/class/typec/port0/power_operation_mode 2>/dev/null || echo N/A)"

echo ""
echo "--- Power (3 readings, 10s apart) ---"
for i in 1 2 3; do
    pnow=$(cat /sys/class/power_supply/qcom-battmgr-bat/power_now 2>/dev/null || echo 0)
    vnow=$(cat /sys/class/power_supply/qcom-battmgr-bat/voltage_now 2>/dev/null || echo 0)
    pct=$(cat /sys/class/power_supply/qcom-battmgr-bat/capacity 2>/dev/null || echo "?")
    watts=$(echo "scale=1; $pnow / 1000000" | bc 2>/dev/null || echo "?")
    volts=$(echo "scale=2; $vnow / 1000000" | bc 2>/dev/null || echo "?")
    echo "  [$(date +%H:%M:%S)] ${watts}W @ ${volts}V  (${pct}%)"
    [ "$i" -lt 3 ] && sleep 10
done

echo ""
echo "--- Kernel log (battmgr) ---"
journalctl -k --no-pager -b 0 2>/dev/null | grep -iE "battmgr|current limit|USB PD|ADAP" | tail -10 || echo "  (none)"
