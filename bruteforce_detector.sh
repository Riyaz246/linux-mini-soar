#!/bin/bash

# --- Configuration ---
# The script will run every 1 minute (via cron)
# and check logs from the "last 1 minute".
TIME_WINDOW="1 minute ago"

# Threshold for detection: 20 failed attempts in 1 minute
THRESHOLD=20

# Log file for our script's actions
LOG_FILE="/home/victim_admin/detector.log"

# --- 1. ALERT (Hunt for threats) ---
echo "[$(date)] Running detection..." | tee -a $LOG_FILE

# This is the core logic:
# 1. journalctl...: Get all sshd logs from the last minute
# 2. grep -E...: Find only the failed login lines (we look for both patterns)
# 3. grep -E -o...: Extract only the IP addresses
# 4. cut...: Clean up the "from " part, leaving just the IP
# 5. sort | uniq -c: Count how many times each unique IP appears
# 6. awk...: Find IPs where the count ($1) is > threshold ($THRESHOLD)

ATTACKING_IPS=$(journalctl -u ssh.service --since "$TIME_WINDOW" \
  | grep -E "Failed password|maximum authentication" \
  | grep -E -o "from [0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" \
  | cut -d " " -f 2 \
  | sort \
  | uniq -c \
  | awk -v t="$THRESHOLD" '$1 > t {print $2}')

# Check if any IPs were found
if [ -z "$ATTACKING_IPS" ]; then
  echo "[$(date)] No attacks found." | tee -a $LOG_FILE
  exit 0
fi

# --- 2. VALIDATE & 3. REMEDIATE (The "SOAR" part) ---
echo "[$(date)] BRUTE-FORCE ATTACK DETECTED!" | tee -a $LOG_FILE

# Loop over every IP we found
for IP in $ATTACKING_IPS
do
  # Log the action
  echo "[$(date)] ALERT: Blocking offending IP: $IP" | tee -a $LOG_FILE
  
  # The remediation: Add the firewall rule (no sudo needed)
  ufw deny from $IP to any port 22
  
  echo "[$(date)] REMEDIATION: IP $IP blocked." | tee -a $LOG_FILE
done
