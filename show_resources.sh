#!/bin/bash

echo "+------------------------+"
echo "| Infos VPS et ressources |"
echo "+------------------------+"

HOST_IP=$(curl -s https://api.ipify.org)
echo "IP publique      : $HOST_IP"

free -h | awk '/^Mem:/ {print "RAM Totale/Utilisée : "$2" / "$3}'

CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}')
echo "Utilisation CPU : $CPU_USAGE"

echo "+------------------------+"
