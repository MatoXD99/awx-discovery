#!/bin/bash

# Colors
BLUE="\e[94m"
BOLD="\e[1m"
RESET="\e[0m"

# Output files
LOG="debug.log"
TMP_CURRENT="current.tmp"
TMP_UNIQUE="unique.tmp"
TEMP_DATA="temp_data.log"

# Init unique tracker
touch "$TMP_UNIQUE"
> "$TEMP_DATA"  # Clear the temp_data.log before starting

declare -A section_data
declare -a section_list

store_section_data() {
    local section="$1"
    local content="$2"
    section_list+=("$section")
    section_data["$section"]="$content"
}

print_header() {
    echo -e "${BLUE}\n========================================="
    echo -e "      ${BOLD}$1${RESET}${BLUE}"
    echo -e "=========================================${RESET}"
}

# Short info
kernel=$(uname -r)
distro=$(lsb_release -ds 2>/dev/null || grep -w NAME /etc/*release | head -n1 | cut -d= -f2 | tr -d '"')
selinux=$(getenforce 2>/dev/null || echo "N/A")
users=$(cut -d: -f1 /etc/passwd | sort | paste -sd ", " -)
groups=$(cut -d: -f1 /etc/group | sort | paste -sd ", " -)
hostname=$(hostname | awk '{print $1}')
ip=$(hostname -I | awk '{print $1}')
dns=$(grep nameserver /etc/resolv.conf | awk '{print $2}' | paste -sd ", " -)
mem=$(free -h | awk '/Mem:/ {print $2}')
cpu=$(lscpu | grep 'Model name' | sed 's/Model name:[ \t]*//')

# 1) HOSTNAME
section="HOSTNAME"
print_header "$section"
host="$hostname"
echo "$host"
store_section_data "$section" "$host"

# 2) IP
section="IP"
print_header "$section"
ipaddr="$ip"
echo "$ipaddr"
store_section_data "$section" "$ipaddr"

# 3) SYSTEM INFO
section="SYSTEM INFO"
print_header "$section"
sysinfo=$(cat <<EOF
Kernel: $kernel
Distribution: $distro
DNS Servers: $dns
CPU: $cpu
Memory: $mem
SELinux: $selinux
EOF
)
echo "$sysinfo"
store_section_data "$section" "$sysinfo"

# 4) USERS
section="USERS"
print_header "$section"
echo "$users"
store_section_data "$section" "$users"

# 5) GROUPS
section="GROUPS"
print_header "$section"
echo "$groups"
store_section_data "$section" "$groups"

# 6) MOUNTED DISKS
section="MOUNTED DISKS"
print_header "$section"
mounted=$(df -hT | grep -v tmpfs)
echo "$mounted"
store_section_data "$section" "$mounted"

# 7) HOME DIR PERMISSIONS
section="PERMISSIONS OF HOME DIRS"
print_header "$section"
home_perms=$(ls -ld /home/* 2>/dev/null)
echo "$home_perms"
store_section_data "$section" "$home_perms"

# 8) AUTHENTICATION
section="AUTHENTICATION (nsswitch.conf)"
print_header "$section"
auth=$(grep -E 'passwd|shadow|group' /etc/nsswitch.conf)
echo "$auth"
store_section_data "$section" "$auth"

# 9) INSTALLED PACKAGES
section="INSTALLED PACKAGES"
print_header "$section"
if command -v dpkg &>/dev/null; then
    pkgs=$(dpkg -l | awk 'NR>5 {print NR-5 ". " $2}')
elif command -v rpm &>/dev/null; then
    pkgs=$(rpm -qa | nl -ba)
else
    pkgs="Unknown package manager"
fi
echo "$pkgs"
store_section_data "$section" "$pkgs"

# 10) DEPENDENCIES FOR BASH
section="DEPENDENCIES FOR BASH"
print_header "$section"
if command -v apt-cache &>/dev/null; then
    deps=$(apt-cache depends bash | grep "Depends:" | awk '{print NR ". " $2}')
elif command -v rpm &>/dev/null; then
    deps=$(rpm -q --requires bash | nl -ba)
else
    deps="Unknown package manager"
fi
echo "$deps"
store_section_data "$section" "$deps"

# 11) REPOSITORIES
section="REPOSITORIES"
print_header "$section"
repos=$(grep -rh ^deb /etc/apt/sources.list* 2>/dev/null || grep ^name /etc/yum.repos.d/*.repo 2>/dev/null)
echo "$repos"
store_section_data "$section" "$repos"

# 12) IPTABLES
section="IPTABLES"
print_header "$section"
iptables_out=$(iptables -L -n -v)
echo "$iptables_out"
store_section_data "$section" "$iptables_out"

# 13) SUDOERS
section="SUDOERS"
print_header "$section"
sudoers=$(grep -vE '^#|^$' /etc/sudoers)
[ -d /etc/sudoers.d ] && sudoers="$sudoers"$'\n'"$(cat /etc/sudoers.d/* 2>/dev/null)"
echo "$sudoers"
store_section_data "$section" "$sudoers"

# 14) SSSD CONFIG
section="SSSD CONFIG"
print_header "$section"
if [ -f /etc/sssd/sssd.conf ]; then
    sssd_conf=$(cat /etc/sssd/sssd.conf)
else
    sssd_conf="SSSD not configured"
fi
echo "$sssd_conf"
store_section_data "$section" "$sssd_conf"

# 15) RSYSLOG EXPORT
section="RSYSLOG"
print_header "$section"
if [ -f /etc/rsyslog.conf ]; then
    rsyslog_conf=$(cat /etc/rsyslog.conf)
else
    rsyslog_conf="RSYSLOG not configured"
fi
echo "$rsyslog_conf"
store_section_data "$section" "$rsyslog_conf"

# 16) FIREWALLD
section="FIREWALLD"
print_header "$section"
if command -v firewall-cmd &>/dev/null; then
    firewalld_out=$(firewall-cmd --list-all 2>/dev/null || echo "Firewalld running but no output")
else
    firewalld_out="Firewalld not installed"
fi
echo "$firewalld_out"
store_section_data "$section" "$firewalld_out"

# 17) RUNNING SERVICES
section="RUNNING SERVICES"
print_header "$section"
running_services=$(systemctl list-units --type=service --state=running)
echo "$running_services"
store_section_data "$section" "$running_services"

# 18) SCHEDULED TASKS (CRON)
section="SCHEDULED TASKS"
print_header "$section"
cron_output=""
cron_output+="System-wide crontab:\n"
cron_output+="$(cat /etc/crontab 2>/dev/null)\n\n"
cron_output+="Cron.d:\n"
cron_output+="$(cat /etc/cron.d/* 2>/dev/null)\n\n"
cron_output+="User crontabs:\n"
for user in $(cut -f1 -d: /etc/passwd); do
    crontab -l -u "$user" 2>/dev/null && echo "--- $user ---"
done | tac
store_section_data "$section" "$cron_output"

# ----------------------------- 19) COLLECT DATA FOR XYNIL SECONDS ------------------------------ #
section="CONNECTIONS"
print_header "$section"
start_time=$(date +%s)
end_time=$((start_time + 10)) # Time here

while [ "$(date +%s)" -lt "$end_time" ]; do
    ts=$(date '+%Y-%m-%d %H:%M:%S')

    # Get current connections
    ss -tunap | awk 'NR>1 {
        gsub(",", "", $0);
        proto=$1; local=$5; remote=$6; proc=$7;
        print proto "," local "," remote "," proc
    }' | sort > "$TMP_CURRENT"

    added=0

    # Append only new unique connections
    while IFS= read -r full_line; do
        match_key=$(echo "$full_line" | cut -d',' -f1-3)
        if ! grep -Fqx "$match_key" "$TMP_UNIQUE"; then
            echo "$match_key" >> "$TMP_UNIQUE"
            echo "$ts,$full_line" >> "$TEMP_DATA"
            added=$((added + 1))
        fi
    done < "$TMP_CURRENT"

    echo "[$ts] Lap done. Added $added new connection(s)." | tee -a "$LOG"
    sleep 5
done

data=$(cat "$TEMP_DATA" 2>/dev/null | awk '{printf "%s\n", $0}' | sed 's/"/""/g')
store_section_data "$section" "$data"

# ----------------------------------------------------------------------------------- #

# Generate CSV file with IP address-based name
output_csv="./$(echo "$ip" | tr '.' '_')_info.csv"
> "$output_csv"

header_row=""
value_row=""

for s in "${section_list[@]}"; do
    header_row="$header_row\"$s\","
    value=$(echo "${section_data[$s]}" | sed 's/"/""/g')
    value_row="$value_row\"$value\","
done

echo "${header_row%,}" > "$output_csv"
echo "${value_row%,}" >> "$output_csv"

# Clean up the CSV file and the script itself
rm "$LOG"
rm "$TMP_CURRENT"
rm "$TMP_UNIQUE"
rm "$TEMP_DATA"
rm -- "$0" # Delete this script
