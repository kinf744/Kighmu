#!/bin/bash
set -e

echo "[*] Mise à jour des paquets..."
sudo apt update -y

echo "[*] Installation de Nginx..."
if ! sudo apt install -y nginx; then
    echo "[Erreur] Échec de l'installation de Nginx."
    exit 1
fi

# Créer fichier nginx.conf localement
cat > ./nginx.conf << 'EOF'
events {}

http {
    map $http_upgrade $connection_upgrade {
        default upgrade;
        '' close;
    }

    server {
        listen 80;
        server_name kiaje.kighmuop.dpdns.org;

        location / {
            proxy_pass http://127.0.0.1:22;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;
        }
    }
}
EOF

echo "[*] Copie de la configuration nginx.conf..."
if ! sudo cp ./nginx.conf /etc/nginx/nginx.conf; then
    echo "[Erreur] Échec de la copie de nginx.conf."
    exit 1
fi

echo "[*] Test de la configuration Nginx..."
if ! sudo nginx -t; then
    echo "[Erreur] La configuration Nginx est invalide."
    exit 1
fi

echo "[*] Recharge du service Nginx..."
if ! sudo systemctl reload nginx; then
    echo "[Erreur] Impossible de recharger Nginx."
    exit 1
fi

echo "[*] Installation et configuration Nginx terminées avec succès."
