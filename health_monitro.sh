#!/bin/bash

# Linux Server Health Monitoring System
# Project: linux-server-health-monitor

set -u

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$PROJECT_DIR/logs"
REPORT_DIR="$PROJECT_DIR/reports"

CPU_LIMIT=80
RAM_LIMIT=80
DISK_LIMIT=80

mkdir -p "$LOG_DIR" "$REPORT_DIR"

TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
DATE_TIME=$(date '+%Y-%m-%d %H:%M:%S')

CSV_FILE="$LOG_DIR/health_history.csv"
HTML_FILE="$REPORT_DIR/health_report_$TIMESTAMP.html"

# Read CPU counters
read_cpu() {
    read -r cpu user nice system idle iowait irq softirq steal rest < /proc/stat

    CPU_IDLE=$((idle + iowait))
    CPU_TOTAL=$((user + nice + system + idle + iowait + irq + softirq + steal))
}

# Calculate CPU usage over one second
read_cpu
OLD_IDLE=$CPU_IDLE
OLD_TOTAL=$CPU_TOTAL

sleep 1

read_cpu

TOTAL_DIFF=$((CPU_TOTAL - OLD_TOTAL))
IDLE_DIFF=$((CPU_IDLE - OLD_IDLE))

if (( TOTAL_DIFF > 0 )); then
    CPU_USAGE=$(awk -v t="$TOTAL_DIFF" -v i="$IDLE_DIFF" \
        'BEGIN {printf "%.2f", (t-i)*100/t}')
else
    CPU_USAGE="0.00"
fi

# RAM usage
RAM_DATA=$(free -b | awk '/^Mem:/ {
    if ($2 > 0) printf "%.2f,%d,%d", ($3/$2)*100, $3, $2
}')

IFS=',' read -r RAM_USAGE RAM_USED RAM_TOTAL <<< "$RAM_DATA"

# Disk usage of root partition
DISK_USAGE=$(df -P / | awk 'NR==2 {gsub("%","",$5); print $5}')
DISK_TOTAL=$(df -hP / | awk 'NR==2 {print $2}')
DISK_USED=$(df -hP / | awk 'NR==2 {print $3}')
DISK_FREE=$(df -hP / | awk 'NR==2 {print $4}')

# System information
HOSTNAME=$(hostname)
UPTIME=$(uptime -p)

# Alert status
STATUS="HEALTHY"
ALERTS=""

if awk -v x="$CPU_USAGE" -v limit="$CPU_LIMIT" \
    'BEGIN {exit !(x >= limit)}'; then
    STATUS="WARNING"
    ALERTS="${ALERTS}High CPU usage; "
fi

if awk -v x="$RAM_USAGE" -v limit="$RAM_LIMIT" \
    'BEGIN {exit !(x >= limit)}'; then
    STATUS="WARNING"
    ALERTS="${ALERTS}High RAM usage; "
fi

if (( DISK_USAGE >= DISK_LIMIT )); then
    STATUS="WARNING"
    ALERTS="${ALERTS}High disk usage; "
fi

if [[ -z "$ALERTS" ]]; then
    ALERTS="No resource alerts"
fi

# Save CSV history
if [[ ! -f "$CSV_FILE" ]]; then
    echo "Date,Hostname,CPU_Usage,RAM_Usage,Disk_Usage,Status" > "$CSV_FILE"
fi

echo "\"$DATE_TIME\",\"$HOSTNAME\",\"$CPU_USAGE\",\"$RAM_USAGE\",\"$DISK_USAGE\",\"$STATUS\"" >> "$CSV_FILE"

# Generate HTML report
cat > "$HTML_FILE" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Linux Server Health Report</title>
<style>
body {
    font-family: Arial, sans-serif;
    background: #f3f4f6;
    margin: 0;
    padding: 30px;
    color: #222;
}
.container {
    max-width: 850px;
    margin: auto;
    background: white;
    padding: 25px;
    border-radius: 10px;
}
h1 { color: #172554; }
.cards {
    display: grid;
    grid-template-columns: repeat(auto-fit,minmax(180px,1fr));
    gap: 15px;
}
.card {
    background: #eff6ff;
    padding: 18px;
    border-radius: 8px;
}
.value {
    font-size: 28px;
    font-weight: bold;
}
.status {
    padding: 12px;
    background: #dcfce7;
    border-radius: 6px;
}
.warning { background: #fee2e2; }
table { width: 100%; border-collapse: collapse; margin-top: 20px; }
td, th { padding: 12px; border-bottom: 1px solid #ddd; text-align: left; }
</style>
</head>
<body>
<div class="container">
<h1>Linux Server Health Report</h1>

<p><b>Hostname:</b> $HOSTNAME</p>
<p><b>Generated:</b> $DATE_TIME</p>
<p><b>Uptime:</b> $UPTIME</p>

<div class="status $([ "$STATUS" = "WARNING" ] && echo warning)">
<b>System Status: $STATUS</b>
<br>$ALERTS
</div>

<div class="cards">
<div class="card">
<h3>CPU Usage</h3>
<div class="value">$CPU_USAGE%</div>
</div>

<div class="card">
<h3>RAM Usage</h3>
<div class="value">$RAM_USAGE%</div>
</div>

<div class="card">
<h3>Disk Usage</h3>
<div class="value">$DISK_USAGE%</div>
</div>
</div>

<h2>Memory Details</h2>
<p>RAM Used: $RAM_USED bytes</p>
<p>RAM Total: $RAM_TOTAL bytes</p>

<h2>Disk Details</h2>
<p>Total: $DISK_TOTAL</p>
<p>Used: $DISK_USED</p>
<p>Free: $DISK_FREE</p>

<h2>Alerts</h2>
<p>$ALERTS</p>

</div>
</body>
</html>
EOF

echo "======================================"
echo " LINUX SERVER HEALTH MONITOR"
echo "======================================"
echo "Hostname    : $HOSTNAME"
echo "CPU Usage   : $CPU_USAGE%"
echo "RAM Usage   : $RAM_USAGE%"
echo "Disk Usage  : $DISK_USAGE%"
echo "Uptime      : $UPTIME"
echo "Status      : $STATUS"
echo "Alerts      : $ALERTS"
echo "--------------------------------------"
echo "CSV History : $CSV_FILE"
echo "HTML Report : $HTML_FILE"
echo "======================================"
