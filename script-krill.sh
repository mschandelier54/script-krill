#!/bin/bash


# Verifica se foi fornecido modo de uso
if [ -z "$1" ]; then
        echo "\n\n\n            Utilize \"script-krill.sh -h\" para obter ajuda.\n\n"
        exit 1
fi


# Define variavel token e asn

asn=$2
as=AS$asn


# Funcao instalar
instalar() {
        # Adiciona repositorio de pacotes da NLnet Labs, importa chave do repositorio e instala Krill
        apt update -y
        apt install ca-certificates curl gnupg lsb-release wget curl net-tools -y
        curl -fsSL https://packages.nlnetlabs.nl/aptkey.asc | gpg --dearmor -o /usr/share/keyrings/nlnetlabs-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/nlnetlabs-archive-keyring.gpg] https://packages.nlnetlabs.nl/linux/debian $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/nlnetlabs.list > /dev/null
        apt update -y
        apt install -y krill
        echo 'ip = "0.0.0.0"' >> /etc/krill.conf

        # Habilita e inicia o Krill
        systemctl enable krill
        sleep 1
        systemctl start krill
        sleep 3

        # Valida se o servico esta escutando
        verifica_status

        # Define Cron para restartar servico 1 vez por dia
        (crontab -l ; echo "0 8 * * * systemctl restart krill") | crontab -
        (crontab -l ; echo "0 8 * * * systemctl restart krillc") | crontab -
}


# Funcao cria_ca
criar_ca() {
        token=$(cat /etc/krill.conf |grep "token =" | cut -d'"' -s -f 2)
        
        krillc add --server https://localhost:3000/ --token $token --ca $as
}


# Funcao child_request
child_request() {
        token=$(cat /etc/krill.conf |grep "token =" | cut -d'"' -s -f 2)
        
        echo "  -> Acesse o Registro.br > Titularidade > ASN > RPKI > Configurar RPKI.\n\n      -> Copie o conteúdo abaixo e cole no campo do registro.br chamado 'Child request'\n\n"
        krillc parents request --server https://localhost:3000/ --token $token --ca $as
        echo "\n\n\n"
        sleep 6

        # Aguarda finalizar passo anterior
        echo "          Pressione [ENTER] quando inserir a Child Request no registro.br e mantenha ele aberto.\n\n\n\n\n"
        read ler

        # Salvar Parent Response
        echo '\n\n\n            Baixe na sua maquina o arquivo com a Parent Response fornecido pelo registro.br.\n\n'
        sleep 6

        echo "          Pressione [ENTER] quando salvar o arquivo com o Parent Response. Mantenha o registro.br aberto.\n\n\n\n\n"
        read ler2

        # Publisher Request
        echo ' -> No registro.br, copie o conteúdo abaixo, cole no campo aberto ao clicar em ">>Configurar publicacao remota" e clique em "HABILITAR PUBLICACAO REMOTA"\n\n'
        krillc repo request --server https://localhost:3000/ --token $token --ca $as
        echo "\n\n\n"
        sleep 6

        # Aguarda finalizar passo anterior
        echo "          Pressione [ENTER] quando inserir a Publisher Request no Registro.br e mantenha ele aberto.\n\n\n\n\n"
        read ler3

        # Repository  Response
        echo '\n\n\n            Baixe na sua maquina o arquivo com a Repository Response fornecida pelo registro.br'

        # Instruções para o segundo uso
        echo "\n\n\n\n           Abra os arquivos XML com um editor de texto e no servidor RPKI crie os arquivos /root/parent-response.xml e /root/repository-response.xml com todo o conteúdo do arquivo"
        sleep 4
        echo "\n\n\n           Com os arquivos já criados, execute novamente o script no modo '--repository-response' fornecendo o ASN como segundo argumento.  Em seguida, use o modo --parent-response fornecendo tambem ASN como segundo argumento.\n\n\n              Ex.:\n          $(whoami)@rpki:~# sh script-krill.sh --repository-response 64496\n          $(whoami)@rpki:~# sh script-krill.sh --parent-response 64496"
        
        # Cria arquivo exemplo de ROAs
        echo "2001:db8::/32-32 => 64496" > /root/roas.txt
        echo "192.168.0.0/22-22 => 64496" >> /root/roas.txt
        echo "192.168.0.0/23-23 => 64496" >> /root/roas.txt
        echo "192.168.0.0/24-24 => 64496" >> /root/roas.txt
        echo "192.168.1.0/24-24 => 64496" >> /root/roas.txt
        echo "192.168.2.0/23-23 => 64496" >> /root/roas.txt
}


# Funcao para adicionar o Repository Response
repository_response() {
        token=$(cat /etc/krill.conf |grep "token =" | cut -d'"' -s -f 2)
        
        krillc repo configure --response /root/repository-response.xml --server https://localhost:3000/ --token $token --ca $as
}


# Funcao que adiciona o Parent Response
parent_response() {
        token=$(cat /etc/krill.conf |grep "token =" | cut -d'"' -s -f 2)
        
        krillc parents add --response /root/parent-response.xml --parent nicbr_ca --server https://localhost:3000/ --token $token --ca $as
}


# Verificar se servico esta escutando
verifica_status() {
        status_krill=$(netstat -putan | grep krill | cut -d "/" -f 2)
        
        if [ $status_krill = "krill" ]; then
                echo "\n\n\n\n          :D              \o/\n\n\n       -> Servico Krill UP!\n\n"
                exit 0
        else
                echo "\n\n\n\n          :0              ;(\n\n\n        -> Servico do Krill nao esta escutando...\n\n\n"
                echo "$status_krill"
                sleep 4
                systemctl status krill
        fi
}


# Adiciona uma entrada ROA
add_roa() {
        token=$(cat /etc/krill.conf |grep "token =" | cut -d'"' -s -f 2)
        arg_roa=$3
        
        krillc roas update --add "$arg_roa" --ca $as --token $token
}


# Remove ROA
remove_roa() {
        token=$(cat /etc/krill.conf |grep "token =" | cut -d'"' -s -f 2)
        arg_roa=$3
        
        krillc roas update --remove "$arg_roa" --ca $as --token $token
}


# Sugere ROAs
sug_roa() {
        token=$(cat /etc/krill.conf |grep "token =" | cut -d'"' -s -f 2)
        
        krillc roas bgp suggest --ca $as --token $token
        echo '\n\n\n          /--/--/--/--/--/--/--/--/--/--/--/--/--/--/--/--/--/--/--/--/--/--/--/--/--/--/--/--/--/--/--/--/--/--/--/--/'
        echo '\n\n\n            Para criar os ROAS conforme sugestão, substitua o arquivo /root/roas.txt com as ROAS apresentadas acima.'
        echo '\n            O conteúdo inicial do arquivo é um exemplo e deve ser substituído.'
}


# Cria ROAs Sugeridos
cria_sug_roas() {
        token=$(cat /etc/krill.conf |grep "token =" | cut -d'"' -s -f 2)
        arquivo_roas="/root/roas.txt"
        
        while read roa
        do
                krillc roas update --add "$roa" --token $token --ca $as
        done < "$arquivo_roas"
}


help_menu() {
        echo "\nModo de utilizacao\n"
        echo "script-krill.sh [MODO] [ARGUMENTO]\n"
        echo "-i,       --instalar,             Adiciona o repositório da NLnet Labs, baixa pacote do Krill e outros necessarios. Instala o serviço e configura restart na CRON."
        echo "-c,       --criar-ca,             Cria a CA do AS. Segundo argumento deve ser o numero ASN. Ex.: $(whoami)@rpki:~# sh script-krill.sh --criar-ca 64496"
        echo "-r,       --child-request,        Gera o Child Request para inserir no registro.br. Segundo argumento deve ser o numero ASN. Ex.: $(whoami)@rpki:~# sh script-krill.sh --child-request 64496"
        echo "-y,       --repository-response,  Pre requisito: arquivo /root/repository-response.xml criado. Adiciona o Repository Response gerado no Registro.br após inserir a Child Request. Recebe como segundo argumento o numero do ASN. Ex.: $(whoami)@rpki:~# sh script-krill.sh --repository-response 64496\n"
        echo "-p,       --parent-response,      Pre requisito: arquivo /root/parent-response.xml criado. Adiciona o Parent Response gerado no Registro.br após inserir a Child Request. Recebe como segundo argumento o numero do ASN. Ex.: $(whoami)@rpki:~# sh script-krill.sh --parent-response 64496\n"
        echo "-a,       --add-roa,              Adiciona ROA informado como terceiro argumento. Segundo argumento deve ser o numero do ASN. Ex.: $(whoami)@rpki:~# sh script-krill.sh --add-roa \"192.168.0.0/22-22 => 64496\""
        echo "-d,       --remove-roa,           Remove ROA informado como terceiro argumento. Segundo argumento deve ser o numero do ASN. Ex.: $(whoami)@rpki:~# sh script-krill.sh --remove-roa \"2001:db8::/32-32 => 64496\""
        echo "-s,       --sugere-roas,          Sugere as ROAs para o ASN utilizando o proprio Krill. Sugestoes sao baseadas nos anuncios atuais. Segundo argumento deve ser o número do ASN."
        echo '-o,       --cria-roas,            Cria ROAs baseado no arquivo "/root/roas.txt". Segundo argumento deve ser o número do ASN.'
        echo "-t,       --token,                Exibe o admin_token do Krill"
        echo "-u        --status,               Verifica se o servico do Krill está escutando"
        echo "-h,       --help,                 Mostra esse menu de ajuda"
        echo "\nPara configurar um RPKI do zero, deve-se: criar a CA, gerar a Child Request, inserir ela no registro.br, salvar o Repository e Parent Response e inserir no Krill e criar os ROAS.\n\nPortanto, em uma primeira configuração utilize os módulos um de cada vez nessa ordem: -i, -c, -r, -y, -p e depois criar as ROAS manualmente ou automaticamente com -s seguido de -o.\n\n"
}


# Define os parametros do script
case $1 in
        -h)
        help_menu
        exit 0
        ;;

        --help)
        help_menu
        exit 0
        ;;

        -t)
        echo "$token"
        exit 0
        ;;

        --token)
        echo "$token"
        exit 0
        ;;

        -i)
        instalar
        exit 0
        ;;

        --instalar)
        instalar
        exit 0
        ;;

        -c)
        criar_ca
        exit 0
        ;;

        --criar-ca)
        criar_ca
        exit 0
        ;;

        -r)
        child_request
        exit 0
        ;;

        --child-request)
        child_request
        exit 0
        ;;

        -p)
        parent_response
        exit 0
        ;;

        --parent-response)
        parent_response
        exit 0
        ;;

        -y)
        repository_response
        exit 0
        ;;

        --repository-response)
        repository_response
        exit 0
        ;;

        -a)
        add_roa
        exit 0
        ;;

        --add-roa)
        add_roa
        exit 0
        ;;

        -d)
        remove_roa
        exit 0
        ;;

        --remove-roa)
        remove_roa
        exit 0
        ;;

        -s)
        sug_roa
        exit 0
        ;;

        --sugere-roas)
        sug_roa
        exit 0
        ;;

        -o)
        cria_sug_roas
        exit 0
        ;;

        --cria-roas)
        cria_sug_roas
        exit 0
        ;;

        -b)
        file_roas
        exit 0
        ;;

        --arquivo-roas)
        file_roas
        exit 0
        ;;

        -u)
        verifica_status
        exit 0
        ;;
        
        --status)
        verifica_status
        exit 0
        ;;

        -d)
        purgar
        exit 0
        ;;

        --purge)
        purgar
        exit 0
esac
