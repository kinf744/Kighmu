#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

DIR=/var/www/html
ARCHIVO=monitor.html

# Créer le répertoire si absent
mkdir -p "$DIR"

# Fichiers logs et ressources
USER_FILE="/etc/kighmu/users.list"
AUTH_LOG="/var/log/auth.log"
OPENVPN_STATUS="/etc/openvpn/openvpn-status.log"

FECHA=$(date +'%d/%m/%Y %H:%M:%S')

# Fonction pour valider service existant avant usage
service_exists() {
    systemctl list-unit-files --type=service | grep -q "^$1"
}

# Fonction Etat service assurant redémarrage et notification
EstadoServicio () {
    local service=$1
    if ! service_exists "$service.service"; then
        echo "<p>Service $service non installé ou introuvable.</p>" >> "$DIR/$ARCHIVO"
        return 1
    fi
    if systemctl --quiet is-active "$service"; then
        echo "<p>Service status $service is || <span class='encendido'> ACTIVE</span>.</p>" >> "$DIR/$ARCHIVO"
    else
        echo "<p>Service status $service is || <span class='detenido'> OFF | REBOOTING</span>.</p>" >> "$DIR/$ARCHIVO"
        # essai redémarrage et notification
        if service "$service" restart; then
            echo "<p>$service redémarré avec succès.</p>" >> "$DIR/$ARCHIVO"
        else
            echo "<p>Échec redémarrage $service.</p>" >> "$DIR/$ARCHIVO"
        fi
        # Notification Telegram (ajuster clé/ID)
        NOM=$(< /etc/VPS-AGN/controller/nombre.log || echo "Unknown")
        IDB=$(< /etc/VPS-AGN/controller/IDT.log || echo "")
        KEY="862633455:AAEgkSywlAHQQOMXzGHJ13gctV6wO1hm25Y"
        if [[ -n "$IDB" ]]; then
            URL="https://api.telegram.org/bot$KEY/sendMessage"
            MSG="⚠️ _VPS NOTICE:_ *$NOM* ⚠️
❗️ _Protocol_ *[ $service ]* _with Fail_ ❗️ 
🛠 _-- Restarting Protocol_ -- 🛠 "
            curl -s --max-time 10 -d "chat_id=$IDB&disable_web_page_preview=true&parse_mode=markdown&text=$MSG" "$URL" || echo "Erreur Telegram"
        else
            echo "<p>Chat ID Telegram manquant, notification non envoyée.</p>" >> "$DIR/$ARCHIVO"
        fi
    fi
}

# Début du fichier HTML
cat > "$DIR/$ARCHIVO" <<EOF
<!DOCTYPE html>
<html lang='en'>
<head>
  <meta charset='UTF-8'>
  <meta name='viewport' content='width=device-width, initial-scale=1.0'>
  <meta http-equiv='X-UA-Compatible' content='ie=edge'>
  <title>VPS-AGN Service Monitor</title>
  <link rel='stylesheet' href='estilos.css'>
</head>
<body>
<h1>Monitor Service By @KhaledAGN</h1>
<p id='ultact'>Última actualización: $FECHA</p>
<hr>
EOF

# Liste des services à vérifier
declare -a SERVICES=(v2ray ssh dropbear stunnel4 squid squid3 apache2)

for srv in "${SERVICES[@]}"; do
    EstadoServicio "$srv"
done

# Vérification BADVPN
if pgrep -x badvpn > /dev/null; then
    echo "<p>Badvpn service status is || <span class='encendido'> ACTIVE</span>.</p>" >> "$DIR/$ARCHIVO"
else
    echo "<p>Badvpn service status is || <span class='detenido'> OFF | REBOOTING</span>.</p>" >> "$DIR/$ARCHIVO"
    screen -dmS badvpn2 /bin/badvpn-udpgw --listen-addr 127.0.0.1:7300 --max-clients 1000 --max-connections-for-client 10
    # Notification similaire à ci-dessus peut être ajoutée ici si besoin
fi

# Exemples de vérifications et redémarrages Python selon fichier si présent
if [[ -f /etc/VPS-AGN/PortPD.log ]]; then
    while IFS= read -r port; do
        pgrep -f "pydic-$port" > /dev/null || screen -dmS "pydic-$port" python /etc/VPS-AGN/protocolos/PDirect.py "$port"
    done < <(grep -v nobody /etc/VPS-AGN/PortPD.log | cut -d' ' -f1)
fi
if [[ -f /etc/VPS-AGN/PySSL.log ]]; then
    while IFS= read -r port; do
        pgrep -f "pyssl-$port" > /dev/null || screen -dmS "pyssl-$port" python /etc/VPS-AGN/protocolos/python.py "$port"
    done < <(grep -v nobody /etc/VPS-AGN/PySSL.log | cut -d' ' -f1)
fi

# Statut PythonDirec
if pgrep -f PDirect.py > /dev/null; then
    P3="<span class='encendido'> ACTIVO </span>"
else
    P3="<span class='detenido'> DESACTIVADO | REINICIANDO </span>"
fi
echo "<p>PythonDirec service status is ||  $P3</p>" >> "$DIR/$ARCHIVO"

# Bloc affichage utilisateurs et appareils connectés
if [[ -f "$USER_FILE" ]]; then
    echo "<h2>Appareils connectés par utilisateur</h2>" >> "$DIR/$ARCHIVO"
    echo "<table border='1' cellpadding='5' cellspacing='0'>" >> "$DIR/$ARCHIVO"
    echo "<tr><th>Utilisateur</th><th>Limite</th><th>Connexions</th><th>Appareils</th><th>OpenVPN Connexions</th></tr>" >> "$DIR/$ARCHIVO"
    
    while IFS="|" read -r username password limite expire_date hostip domain slowdns_ns; do
        ssh_connexions=$(ps aux | grep "sshd: $username@" | grep -v grep | wc -l || echo 0)
        ssh_unique_ips=$(ss -tnp 2>/dev/null | grep sshd | grep ESTAB | grep "$username@" | awk '{print $5}' | cut -d':' -f1 | sort | uniq | wc -l || echo 0)
        drop_connexions=$(pgrep -u "$username" dropbear | wc -l || echo 0)
        drop_unique_ips=$(grep "dropbear.*Password auth succeeded" "$AUTH_LOG" 2>/dev/null | grep "for $username" | awk '{print $(NF-3)}' | sort | uniq | wc -l || echo 0)
        if ! pgrep dropbear > /dev/null 2>&1; then
            drop_connexions=0
            drop_unique_ips=0
        fi
        if [[ -f "$OPENVPN_STATUS" ]]; then
            openvpn_connexions=$(grep -w "$username" "$OPENVPN_STATUS" | wc -l || echo 0)
        else
            openvpn_connexions=0
        fi

        total_connexions=$((ssh_connexions + drop_connexions))
        total_unique_ips=$((ssh_unique_ips + drop_unique_ips))

        echo "<tr><td>$username</td><td>$limite</td><td>$total_connexions</td><td>$total_unique_ips</td><td>$openvpn_connexions</td></tr>" >> "$DIR/$ARCHIVO"
    done < "$USER_FILE"

    echo "</table>" >> "$DIR/$ARCHIVO"
else
    echo "<p>Fichier utilisateurs $USER_FILE introuvable.</p>" >> "$DIR/$ARCHIVO"
fi

echo "</body></html>" >> "$DIR/$ARCHIVO"
