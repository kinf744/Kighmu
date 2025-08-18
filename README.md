# Kighmu Manager

**Kighmu Manager** est un panneau de contrôle pour VPS permettant de gérer des utilisateurs SSH, SOCKS/Python, Dropbear, SlowDNS, BadVPN, SSL/TLS, UDP-Custom et plus encore.  
Il offre une interface simple et des scripts automatisés pour créer, supprimer et surveiller les utilisateurs.

---

## Fonctionnalités principales

- Création d’utilisateurs avec durée limitée (jours ou minutes)
- Affichage des utilisateurs connectés et nombre de connexions par utilisateur
- Gestion des modules : OpenSSH, Dropbear, SOCKS/Python, SlowDNS, BadVPN, SSL/TLS, UDP-Custom
- Statistiques du VPS : IP, RAM, CPU
- Installation et désinstallation simplifiées
- Affichage de configurations pour applications comme HTTP Injector, SSH Custom, etc.

---

## Installation rapide

Pour installer Kighmu Manager automatiquement sur votre VPS :

```bash
apt-get update -y && apt-get upgrade -y && wget https://raw.githubusercontent.com/kinf744/Kighmu/main/install_kighmu.sh -O install_kighmu.sh && chmod +x install_kighmu.sh && bash install_kighmu.sh

Maintenant exécuter cette commande pour que l'alias soit pris en compte:

```bash
source ~/.bashrc

Tu es ainsi prêt à utiliser Kighmu avec la commande :

```bash
kighmu
