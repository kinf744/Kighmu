#!/bin/bash

# Directorio destino
DIR=/var/www/html

# Nombre de archivo HTML a generar
ARCHIVO=monitor.html

# Fecha actual
FECHA=$(date +'%d/%m/%Y %H:%M:%S')

USER_FILE="/etc/kighmu/users.list"
AUTH_LOG="/var/log/auth.log"
OPENVPN_STATUS="/etc/openvpn/openvpn-status.log"

# Declaración de la función
EstadoServicio () {
    systemctl --quiet is-active $1
    if [ $? -eq 0 ]; then
        echo "<p>Service status $1 is || <span class='encendido'> ACTIVE</span>.</p>" >> $DIR/$ARCHIVO
    else
        echo "<p>Service status $1 is || <span class='detenido'> OFF | REBOOTING</span>.</p>" >> $DIR/$ARCHIVO
        service $1 restart &
        NOM=`less /etc/VPS-AGN/controller/nombre.log` > /dev/null 2>&1
        NOM1=`echo $NOM` > /dev/null 2>&1
        IDB=`less /etc/VPS-AGN/controller/IDT.log` > /dev/null 2>&1
        IDB1=`echo $IDB` > /dev/null 2>&1
        KEY="862633455:AAEgkSywlAHQQOMXzGHJ13gctV6wO1hm25Y"
        URL="https://api.telegram.org/bot$KEY/sendMessage"
        MSG="⚠️ _VPS NOTICE:_ *$NOM1* ⚠️
❗️ _Protocol_ *[ $1 ]* _with Fail_ ❗️ 
🛠 _-- Restarting Protocol_ -- 🛠 "
        curl -s --max-time 10 -d "chat_id=$IDB1&disable_web_page_preview=true&parse_mode=markdown&text=$MSG" $URL		                  
    fi
}

# Comienzo de la generación del archivo HTML
echo "
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
" > $DIR/$ARCHIVO

# Servicios a chequear
EstadoServicio v2ray
EstadoServicio ssh
EstadoServicio dropbear
EstadoServicio stunnel4
[[ $(EstadoServicio squid) ]] && EstadoServicio squid3
EstadoServicio apache2

on="<span class='encendido'> ACTIVE " && off="<span class='detenido'> OFF | REBOOTING "
[[ $(ps x | grep badvpn | grep -v grep | awk '{print $1}') ]] && badvpn=$on || badvpn=$off
echo "<p>Badvpn service status is ||  $badvpn </span>.</p> " >> $DIR/$ARCHIVO

PIDVRF3="$(ps aux|grep badvpn |grep -v grep|awk '{print $2}')"
if [[ -z $PIDVRF3 ]]; then
    screen -dmS badvpn2 /bin/badvpn-udpgw --listen-addr 127.0.0.1:7300 --max-clients 1000 --max-connections-for-client 10
    NOM=`less /etc/VPS-AGN/controller/nombre.log` > /dev/null 2>&1
    NOM1=`echo $NOM` > /dev/null 2>&1
    IDB=`less /etc/VPS-AGN/controller/IDT.log` > /dev/null 2>&1
    IDB1=`echo $IDB` > /dev/null 2>&1
    KEY="862633455:AAEgkSywlAHQQOMXzGHJ13gctV6wO1hm25Y"
    URL="https://api.telegram.org/bot$KEY/sendMessage"
    MSG="⚠️ _VPS VIEW:_ *$NOM1* ⚠️
❗️ _Protocol_ *[ BADVPN ]* _with Fail_ ❗️ 
🛠 _-- Restarting Protocol_ -- 🛠 "
    curl -s --max-time 10 -d "chat_id=$IDB1&disable_web_page_preview=true&parse_mode=markdown&text=$MSG" $URL
fi

# Fonction pour les services python (PDirect et pyssl)
ureset_python () {
    for port in $(cat /etc/VPS-AGN/PortPD.log| grep -v "nobody" |cut -d' ' -f1)
    do
        PIDVRF3="$(ps aux|grep pydic-"$port" |grep -v grep|awk '{print $2}')"
        if [[ -z $PIDVRF3 ]]; then
            screen -dmS pydic-"$port" python /etc/VPS-AGN/protocolos/PDirect.py "$port"
            NOM=`less /etc/VPS-AGN/controller/nombre.log` > /dev/null 2>&1
            NOM1=`echo $NOM` > /dev/null 2>&1
            IDB=`less /etc/VPS-AGN/controller/IDT.log` > /dev/null 2>&1
            IDB1=`echo $IDB` > /dev/null 2>&1
            KEY="862633455:AAEgkSywlAHQQOMXzGHJ13gctV6wO1hm25Y"
            URL="https://api.telegram.org/bot$KEY/sendMessage"
            MSG="⚠️ _VPS VIEW:_ *$NOM1* ⚠️
❗️ _Protocol_ *[ PyDirec: $port ]* _with Fail_ ❗️ 
🛠 _-- Restarting Protocol_ -- 🛠 "
            curl -s --max-time 10 -d "chat_id=$IDB1&disable_web_page_preview=true&parse_mode=markdown&text=$MSG" $URL
        fi
    done
}

ureset_pyssl () {
    for port in $(cat /etc/VPS-AGN/PySSL.log| grep -v "nobody" |cut -d' ' -f1)
    do
        PIDVRF3="$(ps aux|grep pyssl-"$port" |grep -v grep|awk '{print $2}')"
        if [[ -z $PIDVRF3 ]]; then
            screen -dmS pyssl-"$port" python /etc/VPS-AGN/protocolos/python.py "$port"
            NOM=`less /etc/VPS-AGN/controller/nombre.log` > /dev/null 2>&1
            NOM1=`echo $NOM` > /dev/null 2>&1
            IDB=`less /etc/VPS-AGN/controller/IDT.log` > /dev/null 2>&1
            IDB1=`echo $IDB` > /dev/null 2>&1
            KEY="862633455:AAEgkSywlAHQQOMXzGHJ13gctV6wO1hm25Y"
            URL="https://api.telegram.org/bot$KEY/sendMessage"
            MSG="⚠️ _VPS VIEW:_ *$NOM1* ⚠️
❗️ _Protocol_ *[ PyDirec: $port ]* _with Fail_ ❗️ 
🛠 _-- Restarting Protocol_ -- 🛠 "
            curl -s --max-time 10 -d "chat_id=$IDB1&disable_web_page_preview=true&parse_mode=markdown&text=$MSG" $URL
        fi
    done
}

ureset_python
ureset_pyssl

pidproxy3=$(ps x | grep -w  "PDirect.py" | grep -v "grep" | awk -F "pts" '{print $1}') && [[ ! -z $pidproxy3 ]] && P3="<span class='encendido'> ACTIVO " || P3="<span class='detenido'> DESACTIVADO | REINICIANDO "
echo "<p>PythonDirec service status is ||  $P3 </span>.</p> " >> $DIR/$ARCHIVO

# Nouveau bloc pour afficher appareils connectés par utilisateur
echo "<h2>Appareils connectés par utilisateur</h2>" >> $DIR/$ARCHIVO
echo "<table border='1' cellpadding='5' cellspacing='0'>" >> $DIR/$ARCHIVO
echo "<tr><th>Utilisateur</th><th>Limite</th><th>Connexions</th><th>Appareils</th><th>OpenVPN Connexions</th></tr>" >> $DIR/$ARCHIVO

while IFS="|" read -r username password limite expire_date hostip domain slowdns_ns; do

    # Connexions SSHD actives (sessions)
    ssh_connexions=$(ps aux | grep "sshd: $username@" | grep -v grep | wc -l)
    # IPs uniques de connexions SSHD
    ssh_unique_ips=$(ss -tnp | grep sshd | grep ESTAB | grep "$username@" | awk '{print $5}' | cut -d':' -f1 | sort | uniq | wc -l)

    # Connexions Dropbear actives (sessions)
    drop_connexions=$(pgrep -u $username dropbear | wc -l)
    # IPs uniques Dropbear (via auth.log)
    drop_unique_ips=$(grep "dropbear.*Password auth succeeded" $AUTH_LOG | grep "for $username" | awk '{print $(NF-3)}' | sort | uniq | wc -l)
    if ! pgrep dropbear > /dev/null; then
        drop_connexions=0
        drop_unique_ips=0
    fi

    # Connexions OpenVPN
    if [ -f "$OPENVPN_STATUS" ]; then
        openvpn_connexions=$(grep -w "$username" "$OPENVPN_STATUS" | wc -l)
    else
        openvpn_connexions=0
    fi

    total_connexions=$((ssh_connexions + drop_connexions))
    total_unique_ips=$((ssh_unique_ips + drop_unique_ips))

    echo "<tr><td>$username</td><td>$limite</td><td>$total_connexions</td><td>$total_unique_ips</td><td>$openvpn_connexions</td></tr>" >> $DIR/$ARCHIVO

done < "$USER_FILE"

echo "</table>" >> $DIR/$ARCHIVO

# FIN du fichier HTML
echo "
</body>
</html>" >> $DIR/$ARCHIVO
