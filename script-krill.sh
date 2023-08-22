#!/bin/bash


# Verifica se foi fornecido modo de uso
if [ -z "$1" ]; then
        echo "\n\n\n            Utilize \"script-krill.sh -h\" para obter ajuda.\n\n"
        exit 1
fi


# Define variavel token e asn
token=$(cat /etc/krill.conf |grep "token =" | cut -d'"' -s -f 2)
asn=$2
as=AS$asn


# Funcao instalar
instalar() {
        # Adiciona repositorio de pacotes da NLnet Labs, importa chave do repositorio e instala Krill
        apt update -y
        apt install ca-certificates curl gnupg lsb-release wget curl -y
        curl -fsSL https://packages.nlnetlabs.nl/aptkey.asc | gpg --dearmor -o /usr/share/keyrings/nlnetlabs-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/nlnetlabs-archive-keyring.gpg] https://packages.nlnetlabs.nl/linux/debian $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/nlnetlabs.list > /dev/null
        apt update -y
        apt install -y krill
        echo 'ip = "0.0.0.0"' >> /etc/krill.conf

        # Habilita e inicia o Krill
        systemctl enable krill
        systemctl start krill

        # Valida se o servico esta escutando
        verifica_status
}


# Funcao cria_ca
cria_ca() {
        krillc add --server https://localhost:3000/ --token $token --ca $as
}


# Funcao child_request
child_request() {
        echo "  -> Acesse o Registro.br > Titularidade > ASN > RPKI > Configurar RPKI.\n\n      -> Copie o conteúdo abaixo e cole no campo do registro.br chamado 'Child request'\n\n"
        krillc parents request --server https://localhost:3000/ --token $token --ca $as
        echo "\n\n\n"
        sleep 6

        # Aguarda finalizar passo anterior
        echo "          Pressione [ENTER] quando inserir a Child Request no registro.br e mantenha ele aberto.\n\n\n\n\n"
        read ler

        # Salvar Parent Response
        echo '\n\n\n            Crie o arquivo "/root/parent-response.xml" e adicione o conteudo do Parent Response fornecido pelo registro.br.\n\n'
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
        echo '\n\n\n            Crie o arquivo "/root/repository-response.xml"  e adicione o conteudo da "Repository Response" fornecida pelo registro.br'

        # Instruções para o segundo uso
        echo "\n\n\n\n           Execute novamente o script no modo '--repository-response' fornecendo o ASN como segundo argumento.  Em seguida, use o modo --parent-response fornecendo tambem ASN como segundo argumento.\n\n\n              Ex.:\n          $(whoami)@rpki:~# sh script-krill.sh --repository-response 61598\n          $(whoami)@rpki:~# sh script-krill.sh --parent-response 61598"
}


# Funcao para adicionar o Repository Response
repository_response() {
        repository_response_file=$3
        krillc repo configure --response /root/repository-response.xml --server https://localhost:3000/ --token $token --ca $as
}


# Funcao que adiciona o Parent Response
parent_response() {
        parent_response_file=$3
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
        arg_roa=$3
        krillc roas update --add "$arg_roa" --ca $as --token $token
}


# Remove ROA
remove_roa() {
        arg_roa=$3
        krillc roas update --remove "$arg_roa" --ca $as --token $token
}


# Sugere ROAs
sug_roa() {
        krillc roas bgp suggest --ca $as --token $token
}


# Cria ROAs Sugeridos
#cria_sug_roa() {
#
#}


# Cria ROAs baseado em arquivo
file_roas() {
        file_roas=$3
        krillc roas update --server https://localhost:3000/ --token $token --ca $as --delta $file_roas
}


# # [!perigo!] Funcao remover tudo (purgar) do Krill. Arquivos, path, etc.
purgar() {
        systemctl stop krill
        systemctl stop krill.service
        systemctl disable krill
        systemctl disable krill.service
        rm -rf $krill_path
        rm -rf /usr/bin/*krill*
        rm /etc/systemd/system/krill*
        systemctl daemon-reload
}


# Define os parametros do script
case $1 in
        -h)
        echo "\nModo de utilizacao\n"
        echo "script-krill.sh [MODO] [ARGUMENTO]\n"
        echo "-i,       --instalar,             Adiciona o repositório da NLnet Labs, baixa pacote do Krill e outros necessarios"
        echo "-c,       --criar-ca,             Cria a CA do AS. Segundo argumento deve ser o ASN. Ex.: $(whoami)@rpki:~# sh script-krill.sh --criar-ca 61598"
        echo "-r,       --child-request,        Gera o Child Request para inserir no registro.br. Segundo argumento deve ser o numero ASN. Ex.: $(whoami)@rpki:~# sh script-krill.sh --child-request 61598"
        echo "-p,       --parent-response,      Adiciona o Parent Response gerado no Registro.br após inserir a Child Request. Recebe como segundo argumento o ASN e terceiro argumento o Path do arquivo XML com o Parent Response como conteúdo. Ex.: $(whoami)@rpki:~# sh script-krill.sh --parent-response 61598 /tmp/response.xml\n"
        echo "-p,       --repository-response,  Adiciona o Repository Response gerado no Registro.br após inserir a Child Request. Recebe como segundo argumento o ASN e terceiro argumento o Path do arquivo XML com o Repository Response como conteúdo. Ex.: $(whoami)@rpki:~# sh script-krill.sh --repository-response 61598 /tmp/repo-response.xml\n"
        echo "-a,       --add-roa,              Adiciona ROA informado como terceiro argumento. Segundo argumento deve ser o numero do ASN. Ex.: $(whoami)@rpki:~# sh script-krill.sh --add-roa \"192.168.0.0/16 => 61598\""
        echo "-r,       --remove-roa,           Remove ROA informado como terceiro argumento. Segundo argumento deve ser o numero do ASN. Ex.: $(whoami)@rpki:~# sh script-krill.sh --remove-roa \"2a04:b900::/29 => 61598\""
        echo "-s,       --sugere-roas,          Sugere as ROAs para o ASN. Segundo argumento deve ser o número do ASN."
        echo "-o,       --add-sugestoes,        Cria ROAs baseado na sugestao. Segundo argumento deve ser o número do ASN."
        echo "-b,       --arquivo-roas,         Cria ROAS baseado em arquivo."
        echo "-t,       --token,                Exibe o admin_token do Krill"
        echo "-u        --status,               Verifica se o servico do Krill está escutando"
        echo "-d,       --purge,                Purga (deleta) todos diretorios, arquivos, links simbolicos e servicos do Krill"
        echo "-h,       --help,                 Mostra esse menu de ajuda"
        echo "\nPara configurar um RPKI do zero, deve-se: criar a CA, gerar a Child Request, inserir ela no registro.br, salvar o Parent Response e inserir no Krill e criar os ROAS.\n\nPortanto, em uma primeira configuração utilize os módulos um de cada vez nessa ordem: -i, -c, -r, -p e depois criar as ROAS manualmente ou automaticamente com -o.\n\n"
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
        cria_ca
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

        -r)
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

        --add-sugestoes)
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
