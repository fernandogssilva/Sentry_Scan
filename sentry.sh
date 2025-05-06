#!/usr/bin/env bash
set -euo pipefail

# Configurações
MYSQL_ROOT_PASS="rootpassword"
DVWA_DB="dvwa"
DVWA_DB_USER="dvwa_user"
DVWA_DB_PASS="dvwa_pass"
DEFECTDOJO_DIR="/opt/defectdojo"
ZABBIX_DIR="/opt/zabbix"

# Registro de status
declare -A STATUS

install_pkg() {
  local pkg=$1
  echo "Instalando $pkg..."
  for i in {1..3}; do
    if dnf install -y "$pkg"; then
      STATUS["$pkg"]="Sucesso"
      return 0
    else
      echo "  Falha ao instalar $pkg (tentativa $i)"
      sleep 3
    fi
  done
  STATUS["$pkg"]="Falha"
  return 1
}

check_service() {
  local svc=$1
  if systemctl is-active --quiet "$svc"; then
    STATUS["$svc"]="Sucesso"
  else
    STATUS["$svc"]="Falha"
  fi
}

echo "=== Preparando o sistema CentOS 9 ==="
dnf update -y
dnf install -y epel-release yum-utils curl git

# 2. Jenkins
dnf install -y java-11-openjdk-devel
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io.key
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
dnf clean all
dnf config-manager --add-repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
install_pkg jenkins
systemctl enable --now jenkins
check_service jenkins

# 3. Apache, PHP e MariaDB (DVWA)
install_pkg httpd
install_pkg php
install_pkg php-mysqli
install_pkg mariadb-server
systemctl enable --now mariadb
mysql_secure_installation <<EOF

y
$MYSQL_ROOT_PASS
$MYSQL_ROOT_PASS
y
y
y
y
EOF

mysql -uroot -p"$MYSQL_ROOT_PASS" <<EOSQL
CREATE DATABASE IF NOT EXISTS $DVWA_DB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DVWA_DB_USER'@'localhost' IDENTIFIED BY '$DVWA_DB_PASS';
GRANT ALL ON $DVWA_DB.* TO '$DVWA_DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOSQL

# 4. ClamAV
install_pkg clamav
install_pkg clamav-update
install_pkg clamav-server
install_pkg clamav-server-systemd
sed -i "s/^Example/#Example/" /etc/clamd.d/scan.conf
sed -i "s/^#LocalSocket /LocalSocket /" /etc/clamd.d/scan.conf
sed -i "s/^Example/#Example/" /etc/freshclam.conf
freshclam || true
systemctl daemon-reload
systemctl enable --now clamd@scan
check_service clamd@scan

# 5. OWASP ZAP via Docker (sem UI)
echo "=== 5. Instalando OWASP ZAP via Docker ==="

# Verifica Docker
if ! command -v docker &>/dev/null; then
  echo "Docker não encontrado. Abortando ZAP inst."
  STATUS["OWASP ZAP"]="Falha"
else
  docker pull zaproxy/zap-stable && echo "Imagem ZAP baixada" || STATUS["OWASP ZAP"]="Falha"

  # Cria script de menu em /usr/local/bin
  cat > /usr/local/bin/zap-menu <<'EOF'
#!/usr/bin/env bash
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
echo -e "${YELLOW}Menu OWASP ZAP${NC}"
echo "1) Daemon"
echo "2) Baseline scan"
echo "3) Full scan"
echo "4) Interactive"
echo "5) Exit"
read -p "Opção: " opt
case $opt in
  1)
    API_KEY=$(openssl rand -hex 16)
    echo -e "${GREEN}API_KEY=$API_KEY${NC}"
    docker run -d --name zap-daemon -p 8080:8080 \
      zaproxy/zap-stable zap.sh -daemon -host 0.0.0.0 -port 8080 \
      -config api.addrs.addr.name=.* -config api.addrs.addr.regex=true \
      -config api.key=$API_KEY
    ;;
  2)
    read -p "URL alvo: " TARGET
    mkdir -p zap-reports
    docker run --rm -v "$(pwd)/zap-reports":/zap/wrk:rw \
      zaproxy/zap-stable zap-baseline.py -t "$TARGET" -r baseline.html
    ;;
  3)
    read -p "URL alvo: " TARGET
    mkdir -p zap-reports
    docker run --rm -v "$(pwd)/zap-reports":/zap/wrk:rw \
      zaproxy/zap-stable zap-full-scan.py -t "$TARGET" -r full.html
    ;;
  4)
    docker run --rm -it zaproxy/zap-stable bash
    ;;
  5) exit 0 ;;
  *) echo "Opção inválida" ;;
esac
EOF
  chmod +x /usr/local/bin/zap-menu

  # Executa em modo daemon por padrão
  /usr/local/bin/zap-menu <<<"1"
  check_service docker && STATUS["OWASP ZAP"]="Sucesso" || STATUS["OWASP ZAP"]="Falha"
fi

# 6. Docker, DefectDojo e Zabbix
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
install_pkg docker-ce
install_pkg docker-ce-cli
install_pkg containerd.io
install_pkg docker-compose-plugin
systemctl enable --now docker
check_service docker

# DefectDojo
install_pkg git
if [ ! -d "$DEFECTDOJO_DIR" ]; then
  git clone https://github.com/DefectDojo/django-DefectDojo.git "$DEFECTDOJO_DIR"
fi
cat > "$DEFECTDOJO_DIR/docker-compose.yml" <<EOF
version: '3'
services:
  defectdojo:
    image: defectdojo/defectdojo-django
    restart: always
    ports:
      - "8000:8000"
EOF
cd "$DEFECTDOJO_DIR"
docker compose pull && docker compose up -d
docker ps --filter name=defectdojo | grep -q Up && STATUS["DefectDojo"]="Sucesso" || STATUS["DefectDojo"]="Falha"

# Zabbix
mkdir -p "$ZABBIX_DIR" && cd "$ZABBIX_DIR"
curl -sL -o docker-compose.yml \
  https://raw.githubusercontent.com/zabbix/zabbix-docker/master/examples/compose/docker-compose_v3_ubuntu_mysql_latest.yaml
sed -i '/restart:/c\    restart: always' docker-compose.yml
docker compose pull && docker compose up -d
docker compose ps | grep -E "zabbix-server|zabbix-web" | grep -q Up \
  && STATUS["Zabbix"]="Sucesso" || STATUS["Zabbix"]="Falha"

# 7. Final: DVWA em Apache
if [ ! -d /var/www/html/DVWA ]; then
  git clone https://github.com/digininja/DVWA.git /var/www/html/DVWA
fi
cp /var/www/html/DVWA/config/config.inc.php.dist /var/www/html/DVWA/config/config.inc.php
sed -i "s/\('db_user'\).*/\1'] = '$DVWA_DB_USER';/" /var/www/html/DVWA/config/config.inc.php
sed -i "s/\('db_password'\).*/\1'] = '$DVWA_DB_PASS';/" /var/www/html/DVWA/config/config.inc.php
sed -i "s/\('db_database'\).*/\1'] = '$DVWA_DB';/" /var/www/html/DVWA/config/config.inc.php
setsebool -P httpd_can_network_connect on
systemctl enable --now httpd
check_service httpd

# 8. Criar arquivo de acessos
mkdir -p /opt/cicd
HOST_IP=$(hostname -I|awk '{print $1}')
cat > /opt/cicd/acessos_cicd.txt <<EOF
=== URLs e Credenciais ===

Jenkins: http://$HOST_IP:8080
Usuário: admin
Senha: $(cat /var/lib/jenkins/secrets/initialAdminPassword)

DVWA: http://$HOST_IP/DVWA
Usuário: $DVWA_DB_USER
Senha: $DVWA_DB_PASS

DefectDojo: http://$HOST_IP:8000
Usuário: admin
Senha: defectdojo

Zabbix: http://$HOST_IP/zabbix
Usuário: Admin
Senha: zabbix

OWASP ZAP (daemon): http://$HOST_IP:8080
Arquivo de menu: /usr/local/bin/zap-menu

ClamAV: logs em /var/log/clamav/
EOF
chmod 600 /opt/cicd/acessos_cicd.txt
restorecon -Rv /opt/cicd

# 9. Sumário de status
echo -e "\n===== STATUS FINAL ====="
for item in "${!STATUS[@]}"; do
  printf "%-15s: %s\n" "$item" "${STATUS[$item]}"
done

echo -e "\nArquivo de acesso: /opt/cicd/acessos_cicd.txt"
echo "Revise itens com ‘Falha’ conforme logs."
