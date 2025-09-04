#!/bin/bash

# -------- Paramètres --------
UDP_BIN='/usr/bin/udpServer'
UDP_BIN_URL='https://bitbucket.org/iopmx/udprequestserver/downloads/udpServer'
PORT=36712  # Changement ici du port 7400 vers 36712

# -------- Fonction pour tuer les processus UDPserver utilisant le port --------
kill_port_processes() {
  # Récupère les pids qui écoutent sur le port UDP 36712
  pids=$(ss -nlup | grep ":$PORT " | awk '{print $6}' | cut -d',' -f2 | cut -d'=' -f2)
  if [[ -n "$pids" ]]; then
    echo "Suppression des processus utilisant le port UDP $PORT : $pids"
    for pid in $pids; do
      kill -9 $pid && echo "Processus $pid tué" || echo "Échec de tuer $pid"
    done
  else
    echo "Aucun processus sur le port UDP $PORT"
  fi
}

# -------- Ouvrir le port UDP dans UFW --------
open_ufw_port() {
  echo "Configuration du firewall UFW pour autoriser le port UDP $PORT..."
  # Vérifier si ufw est installé
  if ! command -v ufw &> /dev/null; then
    echo "UFW n'est pas installé. Installation en cours..."
    apt-get update && apt-get install -y ufw
  fi
  # Autoriser le port UDP (ajoute la règle si elle n'existe pas déjà)
  ufw status | grep -qw "$PORT/udp"
  if [ $? -ne 0 ]; then
    ufw allow $PORT/udp
    echo "Port UDP $PORT autorisé dans UFW."
  else
    echo "Port UDP $PORT est déjà autorisé dans UFW."
  fi
  # Activer ufw s'il ne l'est pas
  ufw status | grep -qw 'Status: active'
  if [ $? -ne 0 ]; then
    echo "Activation d'UFW..."
    ufw --force enable
  fi
}

# -------- Exécuter l'ouverture du port UFW avant l'installation --------
open_ufw_port

# -------- Arrêt des processus existants --------
kill_port_processes
sleep 1

# -------- Téléchargement et installation du binaire --------
echo "Téléchargement de UDPserver..."
wget -O "$UDP_BIN" "$UDP_BIN_URL" --quiet
chmod +x "$UDP_BIN"

# -------- Détection IP publique et interface réseau --------
IP_PUBLIC=$(wget -qO- https://ipinfo.io/ip)
IFACE=$(ip route get 8.8.8.8 | awk '{print $5}' | head -1)

echo "Interface détectée : $IFACE"
echo "Adresse IP publique : $IP_PUBLIC"

# -------- Lancement automatique en arrière-plan --------
echo "Démarrage du tunnel UDP request sur ${IP_PUBLIC}:$PORT ..."
echo "Commande : $UDP_BIN -ip=$IP_PUBLIC -net=$IFACE -port=$PORT -mode=system"

nohup $UDP_BIN -ip=$IP_PUBLIC -net=$IFACE -port=$PORT -mode=system >/dev/null 2>&1 &

# -------- Message encadré de confirmation --------
msg1="Tunnel UDP request installé avec succès !"
msg2="Fonctionne avec des applications comme SocksIP Tunnel VPN."

max_len=${#msg1}
(( ${#msg2} > max_len )) && max_len=${#msg2}
pad=4
total_width=$((max_len + pad))

border=$(printf '%*s' "$total_width" '' | tr ' ' '=')

echo -e "\n$border"
printf "= %-${max_len}s =\n" "$msg1"
printf "= %-${max_len}s =\n" "$msg2"
echo -e "$border\n"

echo "Serveur public : $IP_PUBLIC:$PORT (UDP)"
echo "Le port UDP $PORT est ouvert dans le firewall UFW."
echo "Pour arrêter le tunnel : pkill -f udpServer"
echo "Le port UDP est toujours forcé à $PORT dans ce script."
