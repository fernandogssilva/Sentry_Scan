# Sentry_Scan
Sentry_Scan
Sentry_Scan é uma esteira CI/CD DevSecOps automatizada para ambientes Linux (CentOS 9), integrando as principais ferramentas de segurança open source: Jenkins, DVWA, OWASP ZAP, DefectDojo, ClamAV e Zabbix. O projeto automatiza a instalação, configuração, validação e disponibiliza um ambiente pronto para testes, análise e monitoramento de segurança de aplicações.

:rocket: Funcionalidades
Instalação automatizada de todas as dependências e ferramentas de segurança

Pipeline CI/CD com análise dinâmica (DAST) e estática (SAST)

Ambiente vulnerável (DVWA) para treinamentos e testes
Gerenciamento centralizado de vulnerabilidades (DefectDojo)
Monitoramento completo dos serviços e aplicações (Zabbix)
Relatórios e logs centralizados
Instalação do OWASP ZAP via Docker, facilitando atualizações e uso headless
Geração de arquivo com URLs e credenciais iniciais para todos os sistemas

:hammer_and_wrench: Ferramentas Integradas
Jenkins – Orquestração de pipelines CI/CD
DVWA – Para testar o projeto após instalação
OWASP ZAP – Scanner DAST (via Docker)
DefectDojo – Plataforma de gestão de vulnerabilidades (via Docker)
ClamAV – Scanner antivírus para análise estática
Zabbix – Monitoramento de infraestrutura e aplicações (via Docker)

:floppy_disk: Instalação
Pré-requisitos:
CentOS 9 Stream
Usuário com privilégios de sudo
Conexão com a internet

#Bash

git clone https://github.com/fernandogssilva/Sentry_Scan.git

cd Sentry_Scan

chmod +x script_centOS9.sh

sudo ./script_centOS9.sh

:closed_lock_with_key: Acesso às Aplicações
Após a instalação, consulte o arquivo /opt/cicd/acessos_cicd.txt para URLs e credenciais iniciais de todos os sistemas:

bash
cat /opt/cicd/acessos_cicd.txt

:bulb: Uso do OWASP ZAP via Docker
Para acessar o menu de operações do ZAP:

bash
zap-menu
Você pode rodar o ZAP em modo daemon, baseline scan, full scan ou interativo.

:warning: Avisos
Utilize este ambiente apenas para fins de testes, treinamentos e validações de segurança.

Não exponha as ferramentas para redes externas sem a devida proteção.

Altere as senhas padrão após a instalação.

:handshake: Contribuição
Pull Requests e sugestões são bem-vindos!
Abra uma issue para reportar bugs ou sugerir melhorias.

:page_facing_up: Licença
Este projeto está licenciado sob a MIT License.

Desenvolvido por [Seu Nome ou Time]
Inspirado pela dificuldade em encontrar ferramentas que auxiliam no processo de correções de falhas de segurança e correções de vulnerabilidades.!
