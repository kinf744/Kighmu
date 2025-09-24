#!/bin/bash
#by @Kighmu (modifié pour Kighmu)
clear
clear

KIGHMU_DIR="${HOME}/Kighmu"
SCPdir="${KIGHMU_DIR}"

# Vérification que le dossier principal existe
if [[ ! -d "$SCPdir" ]]; then
  echo "Erreur : Le dossier $SCPdir n'existe pas. Vérifiez votre installation."
  exit 1
fi

declare -A cor=( [0]="\033[1;37m" [1]="\033[1;34m" [2]="\033[1;31m" [3]="\033[1;33m" [4]="\033[1;32m" )
[[ $(dpkg --get-selections | grep -w "python" | head -1) ]] || apt-get install python -y &>/dev/null

mportas () {
  unset portas
  portas_var=$(lsof -V -i tcp -P -n | grep -v "ESTABLISHED" | grep -v "COMMAND" | grep "LISTEN")
  while read port; do
    var1=$(echo $port | awk '{print $1}')
    var2=$(echo $port | awk '{print $9}' | awk -F ":" '{print $2}')
    [[ "$(echo -e $portas | grep "$var1 $var2")" ]] || portas+="$var1 $var2\n"
  done <<< "$portas_var"
  echo -e "$portas"
}

meu_ip () {
  MEU_IP=$(ip addr | grep 'inet' | grep -v inet6 | grep -vE '127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | grep -o -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
  MEU_IP2=$(wget -qO- ipv4.icanhazip.com)
  [[ "$MEU_IP" != "$MEU_IP2" ]] && echo "$MEU_IP2" || echo "$MEU_IP"
}

tcpbypass_fun () {
  [[ -e $HOME/socks ]] && rm -rf $HOME/socks > /dev/null 2>&1
  [[ -d $HOME/socks ]] && rm -rf $HOME/socks > /dev/null 2>&1
  cd $HOME && mkdir socks > /dev/null 2>&1
  cd socks
  patch="https://raw.githubusercontent.com/khaledagn/VPS-AGN_English_Official/master/LINKS-LIBRARIES/backsocz.zip"
  arq="backsocz.zip"
  wget $patch > /dev/null 2>&1
  unzip $arq > /dev/null 2>&1
  mv -f "$HOME/socks/backsocz/./ssh" /etc/ssh/sshd_config && service ssh restart 1> /dev/null 2>/dev/null
  mv -f "$HOME/socks/backsocz/sckt$(python3 --version | awk '{print $2}' | cut -d'.' -f1,2)" /usr/sbin/sckt
  mv -f "$HOME/socks/backsocz/scktcheck" /bin/scktcheck
  chmod +x /bin/scktcheck
  chmod +x /usr/sbin/sckt
  rm -rf "$HOME/socks"
  cd $HOME
  msg="$2"
  [[ $msg = "" ]] && msg="@KhaledAGN"
  portxz="$1"
  [[ $portxz = "" ]] && portxz="8080"
  screen -dmS sokz scktcheck "$portxz" "$msg" > /dev/null 2>&1
}

gettunel_fun () {
  echo "master=NetVPS" > "${SCPdir}/pwd.pwd"
  while read service; do
    [[ -z $service ]] && break
    echo "127.0.0.1:$(echo $service | cut -d' ' -f2)=$(echo $service | cut -d' ' -f1)" >> "${SCPdir}/pwd.pwd"
  done <<< "$(mportas)"
  screen -dmS getpy python "${SCPdir}/PGet.py" -b "0.0.0.0:$1" -p "${SCPdir}/pwd.pwd"
  if pgrep -f "PGet.py" > /dev/null; then
    echo -e "Gettunel Started with Success"
  else
    echo -e "Gettunnel not started"
  fi
}

PythonDic_fun () {
  echo -e "\033[1;33m  Select Local Port and Header\033[1;37m"
  echo "----------------------------------"
  echo -ne "Enter an active SSH/DROPBEAR port: " && read puetoantla
  echo "----------------------------------"
  echo -ne "Header response (200,101,404,500,etc): " && read rescabeza
  echo "----------------------------------"

  # Installer ufw s'il manque
  if ! command -v ufw &> /dev/null; then
    echo "UFW non installé. Installation en cours..."
    sudo apt-get update -y
    sudo apt-get install -y ufw
  fi

  # Vérifier l’état de ufw et l’activer si inactif
  ufw_status=$(sudo ufw status | head -n 1)
  if [[ "$ufw_status" == "Status: inactive" ]]; then
    echo "Activation de UFW..."
    sudo ufw --force enable
  fi

  # Autoriser le port local choisi dans le firewall
  echo "Autorisation du port $puetoantla/tcp dans le pare-feu UFW..."
  sudo ufw allow "$puetoantla/tcp"

  (
  cat << PYTHON > "${SCPdir}/PDirect.py"
import socket, threading, select, sys, time, getopt

# Listen
LISTENING_ADDR = '0.0.0.0'
LISTENING_PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 80

PASS = ''

BUFLEN = 4096 * 4
TIMEOUT = 60
DEFAULT_HOST = '127.0.0.1:$puetoantla'
RESPONSE = 'HTTP/1.1 $rescabeza Connection established\r\n\r\n'

class Server(threading.Thread):
    def __init__(self, host, port):
        threading.Thread.__init__(self)
        self.running = False
        self.host = host
        self.port = port
        self.threads = []
        self.threadsLock = threading.Lock()
        self.logLock = threading.Lock()

    def run(self):
        self.soc = socket.socket(socket.AF_INET)
        self.soc.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.soc.settimeout(2)
        self.soc.bind((self.host, self.port))
        self.soc.listen(0)
        self.running = True

        try:
            while self.running:
                try:
                    c, addr = self.soc.accept()
                    c.setblocking(1)
                except socket.timeout:
                    continue

                conn = ConnectionHandler(c, self, addr)
                conn.start()
                self.addConn(conn)
        finally:
            self.running = False
            self.soc.close()

    def printLog(self, log):
        self.logLock.acquire()
        print(log)
        self.logLock.release()

    def addConn(self, conn):
        try:
            self.threadsLock.acquire()
            if self.running:
                self.threads.append(conn)
        finally:
            self.threadsLock.release()

    def removeConn(self, conn):
        try:
            self.threadsLock.acquire()
            self.threads.remove(conn)
        finally:
            self.threadsLock.release()

    def close(self):
        try:
            self.running = False
            self.threadsLock.acquire()

            threads = list(self.threads)
            for c in threads:
                c.close()
        finally:
            self.threadsLock.release()

class ConnectionHandler(threading.Thread):
    def __init__(self, socClient, server, addr):
        threading.Thread.__init__(self)
        self.clientClosed = False
        self.targetClosed = True
        self.client = socClient
        self.client_buffer = b""
        self.server = server
        self.log = 'Connection: ' + str(addr)

    def close(self):
        try:
            if not self.clientClosed:
                self.client.shutdown(socket.SHUT_RDWR)
                self.client.close()
        except:
            pass
        finally:
            self.clientClosed = True

        try:
            if not self.targetClosed:
                self.target.shutdown(socket.SHUT_RDWR)
                self.target.close()
        except:
            pass
        finally:
            self.targetClosed = True

    def run(self):
        try:
            self.client_buffer = self.client.recv(BUFLEN)

            hostPort = self.findHeader(self.client_buffer, 'X-Real-Host')

            if hostPort == '':
                hostPort = DEFAULT_HOST

            split = self.findHeader(self.client_buffer, 'X-Split')

            if split != '':
                self.client.recv(BUFLEN)

            if hostPort != '':
                passwd = self.findHeader(self.client_buffer, 'X-Pass')

                if len(PASS) != 0 and passwd == PASS:
                    self.method_CONNECT(hostPort)
                elif len(PASS) != 0 and passwd != PASS:
                    self.client.send(b'HTTP/1.1 400 WrongPass!\r\n\r\n')
                elif hostPort.startswith('127.0.0.1') or hostPort.startswith('localhost'):
                    self.method_CONNECT(hostPort)
                else:
                    self.client.send(b'HTTP/1.1 403 Forbidden!\r\n\r\n')
            else:
                print('- No X-Real-Host!')
                self.client.send(b'HTTP/1.1 400 NoXRealHost!\r\n\r\n')

        except Exception as e:
            self.log += ' - error: ' + str(e)
            self.server.printLog(self.log)
            pass
        finally:
            self.close()
            self.server.removeConn(self)

    def findHeader(self, head, header):
        aux = head.find((header + ': ').encode())

        if aux == -1:
            return ''

        aux = head.find(b':', aux)
        head = head[aux+2:]
        aux = head.find(b'\r\n')

        if aux == -1:
            return ''

        return head[:aux].decode()

    def connect_target(self, host):
        i = host.find(':')
        if i != -1:
            port = int(host[i+1:])
            host = host[:i]
        else:
            port = sys.argv[1]

        (soc_family, soc_type, proto, _, address) = socket.getaddrinfo(host, port)[0]

        self.target = socket.socket(soc_family, soc_type, proto)
        self.targetClosed = False
        self.target.connect(address)

    def method_CONNECT(self, path):
        self.log += ' - CONNECT ' + path

        self.connect_target(path)
        self.client.sendall(RESPONSE.encode())
        self.client_buffer = b''

        self.server.printLog(self.log)
        self.doCONNECT()

    def doCONNECT(self):
        socs = [self.client, self.target]
        count = 0
        error = False
        while True:
            count += 1
            (recv, _, err) = select.select(socs, [], socs, 3)
            if err:
                error = True
            if recv:
                for in_ in recv:
                    try:
                        data = in_.recv(BUFLEN)
                        if data:
                            if in_ is self.target:
                                self.client.send(data)
                            else:
                                while data:
                                    byte = self.target.send(data)
                                    data = data[byte:]

                            count = 0
                        else:
                            break
                    except:
                        error = True
                        break
            if count == TIMEOUT:
                error = True
            if error:
                break

def print_usage():
    print('Usage: proxy.py -p <port>')
    print('       proxy.py -b <bindAddr> -p <port>')
    print('       proxy.py -b 0.0.0.0 -p 80')

def parse_args(argv):
    global LISTENING_ADDR
    global LISTENING_PORT

    try:
        opts, args = getopt.getopt(argv,"hb:p:",["bind=","port="])
    except getopt.GetoptError:
        print_usage()
        sys.exit(2)
    for opt, arg in opts:
        if opt == '-h':
            print_usage()
            sys.exit()
        elif opt in ("-b", "--bind"):
            LISTENING_ADDR = arg
        elif opt in ("-p", "--port"):
            LISTENING_PORT = int(arg)

def main(host=LISTENING_ADDR, port=LISTENING_PORT):
    print("\n:-------PythonProxy-------:\n")
    print("Listening addr: " + LISTENING_ADDR)
    print("Listening port: " + str(LISTENING_PORT) + "\n")
    print(":-------------------------:\n")
    server = Server(LISTENING_ADDR, LISTENING_PORT)
    server.start()
    while True:
        try:
            time.sleep(2)
        except KeyboardInterrupt:
            print('Stopping...')
            server.close()
            break

if __name__ == '__main__':
    main()

PYTHON
  ) > "${SCPdir}/PDirect.py"

  chmod +x "${SCPdir}/PDirect.py"

  screen -dmS pydic-"$puetoantla" python "${SCPdir}/PDirect.py" "$puetoantla" "$rescabeza" && echo "$puetoantla $rescabeza" >> "${SCPdir}/PortPD.log"
}

pid_kill () {
  [[ -z $1 ]] && return 1
  pids="$@"
  for pid in $pids; do
    kill -9 $pid &>/dev/null
  done
}

remove_fun () {
  echo -e "Stopping Socks Python"
  #msg -bar
  pidproxy=$(pgrep -f "PPub.py")
  [[ ! -z $pidproxy ]] && pid_kill $pidproxy
  pidproxy2=$(pgrep -f "PPriv.py")
  [[ ! -z $pidproxy2 ]] && pid_kill $pidproxy2
  pidproxy3=$(pgrep -f "PDirect.py")
  [[ ! -z $pidproxy3 ]] && pid_kill $pidproxy3
  pidproxy4=$(pgrep -f "POpen.py")
  [[ ! -z $pidproxy4 ]] && pid_kill $pidproxy4
  pidproxy5=$(pgrep -f "PGet.py")
  [[ ! -z $pidproxy5 ]] && pid_kill $pidproxy5
  pidproxy6=$(pgrep -f "scktcheck")
  [[ ! -z $pidproxy6 ]] && pid_kill $pidproxy6
  pidproxy7=$(pgrep -f "python.py")
  [[ ! -z $pidproxy7 ]] && pid_kill $pidproxy7
  echo -e "\033[1;91m Socks ARRESTED"
  #msg -bar
  rm -rf "${SCPdir}/PortPD.log"
  echo "" > "${SCPdir}/PortPD.log"
  exit 0
}

iniciarsocks () {
  pidproxy=$(pgrep -f "PPub.py")
  [[ ! -z $pidproxy ]] && P1="\033[1;32m[ON]" || P1="\033[1;31m[OFF]"
  pidproxy2=$(pgrep -f "PPriv.py")
  [[ ! -z $pidproxy2 ]] && P2="\033[1;32m[ON]" || P2="\033[1;31m[OFF]"
  pidproxy3=$(pgrep -f "PDirect.py")
  [[ ! -z $pidproxy3 ]] && P3="\033[1;32m[ON]" || P3="\033[1;31m[OFF]"
  pidproxy4=$(pgrep -f "POpen.py")
  [[ ! -z $pidproxy4 ]] && P4="\033[1;32m[ON]" || P4="\033[1;31m[OFF]"
  pidproxy5=$(pgrep -f "PGet.py")
  [[ ! -z $pidproxy5 ]] && P5="\033[1;32m[ON]" || P5="\033[1;31m[OFF]"
  pidproxy6=$(pgrep -f "scktcheck")
  [[ ! -z $pidproxy6 ]] && P6="\033[1;32m[ON]" || P6="\033[1;31m[OFF]"
  echo "==== INSTALLER OF PROXY'S VPS-AGN By MOD @KhaledAGN ===="
  echo "[3] Proxy Python DIRECT $P3"
  echo "[4] Proxy Python OPENVPN $P4"
  echo "[7] STOP ALL PROXY'S"
  echo "[0] RETURN"

  IP=$(meu_ip)
  while [[ -z $portproxy || $portproxy != @(0|3|4|7) ]]; do
    echo -ne "Type an option: " && read portproxy
    tput cuu1 && tput dl1
  done

  case $portproxy in
    3) PythonDic_fun;;
    4) screen -dmS screen python "${SCPdir}/POpen.py" "$puetoantla" "$rescabeza";;
    7) remove_fun;;
    0) return;;
  esac

  echo -e "\033[1;92mCOMPLETED procedure"
}

iniciarsocks
