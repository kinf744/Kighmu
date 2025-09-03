<p align="center">
  <img src="PAGE%20KIGHMU.jpg" alt="Page Kighmu" width="600">
</p>

<p align="center">
  <img src="KIGHMU%20MANAGER.jpg" alt="Kighmu Manager" width="600">
</p>

# Kighmu Manager

<h2 align="center">Distribution Linux compatible</h2>

<p align="center"><img src="https://img.shields.io/static/v1?style=for-the-badge&logo=debian&label=Debian%209 & 2010&message=Stretch&color=red"> <img src="https://img.shields.io/static/v1?style=for-the-badge&logo=debian&label=Debian%2010&message=Buster&color=red"> <img src="https://img.shields.io/static/v1?style=for-the-badge&logo=ubuntu&label=Ubuntu%2018&message=18.04 LTS&color=red"> <img src="https://img.shields.io/static/v1?style=for-the-badge&logo=ubuntu&label=Ubuntu%2020&message=20.04 LTS&color=red"></p>

<p align="center"><img src="https://img.shields.io/badge/Service-OpenSSH-success.svg">  <img src="https://img.shields.io/badge/Service-Dropbear-success.svg">  <img src="https://img.shields.io/badge/Service-BadVPN-success.svg">  <img src="https://img.shields.io/badge/Service-Stunnel-success.svg">  <img src="https://img.shields.io/badge/Service-OpenVPN-success.svg">  <img src="https://img.shields.io/badge/Service-Squid3-success.svg">  <img   src="https://img.shields.io/badge/Service-Webmin-success.svg">  <img src="https://img.shields.io/badge/Service-Privoxy-green.svg">   <img
src="https://img.shields.io/badge/Service-V2ray-success.svg">  <img src= "https://img.shields.io/badge/Service-SSR-success.svg">  <img src="https://img.shields.io/badge/Service-Trojan-success.svg">  <img src="https://img.shields.io/badge/Service-WireGuard-success.svg">


## Installation

<img src="https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=Shell&message=Bash%20Script&color=lightgray"></img>
- Commmand :

<img src="https://img.shields.io/badge/Service-Update%20First-green"></img>
 ```html
 apt-get update && apt-get upgrade -y && update-grub && reboot
  ```
 <img src="https://img.shields.io/badge/Install All-VPN%20Batch-green"></img>
 ```html
 wget https://raw.githubusercontent.com/syapik96/aws/main/setup.sh 
 chmod +x setup.sh 
 ./setup.sh

**Kighmu Manager** est un panneau de contrôle pour VPS permettant de gérer des utilisateurs SSH, SOCKS/Python, Dropbear, SlowDNS, BadVPN, SSL/TLS, UDP-Custom et plus encore.  
Il offre une interface simple et des scripts automatisés pour créer, supprimer et surveiller les utilisateurs.

---

## Fonctionnalités principales

- Création d’utilisateurs avec durée limitée (jours ou minutes)
- Affichage des utilisateurs connectés et nombre de connexions par utilisateur
- Gestion des modules : OpenSSH,
- Dropbear,
- SOCKS/Python,
- DNSTT, BadVPN,
- SSL/TLS,
- UDP-Custom
- Statistiques du VPS : IP, RAM, CPU
- Installation et désinstallation simplifiées
- Affichage de configurations pour applications comme HTTP Injector, SSH Custom, etc.

---

## Installation rapide

Pour installer Kighmu Manager automatiquement sur votre VPS :

```bash
apt-get update -y && apt-get upgrade -y && wget https://raw.githubusercontent.com/kinf744/Kighmu/main/install_kighmu.sh -O install_kighmu.sh && chmod +x install_kighmu.sh && bash install_kighmu.sh
