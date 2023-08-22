#!/bin/bash


# Verifica se foi fornecido ASN
if [ -z "$1" ]; then
        echo "\n\n\n            Utilize \"script-krill.sh -h\" para obter ajuda.\n\n"
        exit 1
fi


# Define variavel token e asn
#token=$(cat /etc/krill.conf |grep "token =" | cut -d'"' -s -f 2)
asn=$2
as=AS$asn
token=$(echo -n "clvc"$as"1913" | md5sum | cut -d " " -f1)
krill_path=/etc/krill
krill_conf=$krill_path/krill.conf

# Funcao verifica_status
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
        echo "\n\n\n            Crie um arquivo .xml e adicione o conteudo do Parent Response fornecido pelo registro.br.\n\n"
        sleep 6
        
        # Publisher Request
        echo ' -> No registro.br, copie o conteúdo abaixo, cole no campo aberto ao clicar em ">>Configurar publicacao remota" e clique em "HABILITAR PUBLICACAO REMOTA"\n\n'
        krillc repo request --server https://localhost:3000/ --token $token --ca $as
        echo "\n\n\n"
        sleep 6

        # Aguarda finalizar passo anterior
        echo "          Pressione [ENTER] quando inserir a Publisher Request no Registro.br e mantenha ele aberto.\n\n\n\n\n"
        read ler2

        # Repository  Response
        echo '\n\n\n            Crie um arquivo .xml e adicione o conteudo da "Repository Response" fornecida pelo registro.br'

        # Instruções para o segundo uso
        echo "\n\n\n           Execute novamente o script fornecendo no modo '--parent-response' fornecendo o ASN como segundo argumento. Como Terceiro argumento informe o Path para o arquivo criado com a Repository Response e depois no modo --repository-response fornecendo tambem ASN e agora o arquivo XML com a Parent Response.\n\n              Ex.:\n          $(whoami)@rpki:~# sh script-krill.sh --parent-response 61598 $HOME/parent-response.xml"
}


# Funcao para adicionar o Repository Response
repository_response() {
        repository_response_file=$3
        krillc repo configure --response $repository_response_file --server https://localhost:3000/ --token $token --ca $as
}


# Funcao que adiciona o Parent Response
parent_response() {
        parent_response_file=$3
        krillc parents add --response $parent_response_file --parent nicbr_ca --server https://localhost:3000/ --token $token --ca $as
}


# Funcao instalar
instalar() {
        # Instala pacotes necessarios
        apt install -y build-essential git curl libssl-dev openssl pkg-config
        curl https://sh.rustup.rs -sSf | sh
        source $HOME/.cargo/env
        mkdir $krill_path ; cd $krill_path
        git clone https://github.com/NLnetLabs/krill.git
        cd $krill_path/krill ; cargo build --release
        ln -s $krill_path/krill/target/release/krill /usr/bin; ln -s $krill_path/krill/target/release/krillc /usr/bin
        cd $krill_path ; cp $krill_path/krill/defaults/krill.conf $krill_conf
        mkdir $krill_path/data
        echo 'auth_token = "$token"' >> $krill_conf ; echo 'admin_token = "$token"' >> $krill_conf
        echo 'ip = "0.0.0.0"' >> $krill_conf
        krill -c .$krill_conf



        # Adiciona repositorio de pacotes da NLnet Labs, importa chave do repositorio e instala Krill
#        echo 'deb [arch=amd64] https://packages.nlnetlabs.nl/linux/debian/ bullseye main' >  /etc/apt/sources.list.d/nlnetlabs.list
#        wget -qO- https://packages.nlnetlabs.nl/aptkey.asc | apt-key add -
#        apt update -y
#        apt install -y krill krill-sync krillup krillta

        # Habilita e inicia o Krill
#        systemctl enable krill
#        systemctl start krill

        # Valida se o servico esta escutando
        verifica_status
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


# Funcao cria_ca
cria_ca() {
        krillc add --server https://localhost:3000/ --token $token --ca $as
}


# Sugere ROAs
sug_roa() {
        krillc roas bgp suggest --ca $as --token $token
}


# Cria ROAs Sugeridos
#cria_sug_roa() {

#}


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


# Publica as ROAs
publica_roas() {
        file_roas=$3
        krillc roas update --server https://localhost:3000/ --token $token --ca $as --delta $file_roas
}


# Define os parametros do script
case $1 in
        -t)
        echo "$token"
        exit 0
        ;;

        --token)
        echo "$token"
        exit 0
        ;;

        -h)
        echo "\nModo de utilizacao\n"
        echo "script-krill.sh [MODO] [ARGUMENTO]\n"
        echo "-i,       --instalar,             Adiciona o repositório da NLnet Labs, baixa pacote do Krill e outros necessarios"
        echo "-c,       --criar-ca,             Cria a CA do AS. Segundo argumento deve ser o ASN. Ex.: $(whoami)@rpki:~# sh script-krill.sh --criar-ca 61598"
        echo "-r,       --child-request,        Gera o Child Request para inserir no registro.br. Segundo argumento deve ser o numero ASN. Ex.: $(whoami)@rpki:~# sh script-krill.sh --child-request 61598"
        echo "-p,       --parent-response,      Adiciona o Parent Response gerado no Registro.br após inserir a Child Request. Recebe como segundo argumento o ASN e terceiro argumento o Path do arquivo XML com o Parent Response como conteúdo. Ex.: $(whoami)@rpki:~# sh script-krill.sh --parent-response 61598 /tmp/response.xml\n"
        echo "-a,       --add-roa,              Adiciona ROA informado como terceiro argumento. Segundo argumento deve ser o numero do ASN. Ex.: $(whoami)@rpki:~# sh script-krill.sh --add-roa \"192.168.0.0/16 => 61598\""
        echo "-r,       --remove-roa,           Remove ROA informado como terceiro argumento. Segundo argumento deve ser o numero do ASN. Ex.: $(whoami)@rpki:~# sh script-krill.sh --remove-roa \"2a04:b900::/29 => 61598\""
        echo "-s,       --sugere-roas,          Sugere as ROAs para o ASN. Segundo argumento deve ser o número do ASN."
        echo "-o,       --add-sugestoes,        Cria ROAs baseado na sugestao. Segundo argumento deve ser o número do ASN."
        echo "-b,       --publica-roas,         Publica ROAs. Segundo argumento deve ser o número do ASN. Terceiro argumento deve ser Path do arquivo com os ROAs"
        echo "-t,       --token,                Exibe o admin_token do Krill"
        echo "-u        --status,               Verifica se o servico do Krill está escutando"
        echo "-d,       --purge,                Purga (deleta) todos diretorios, arquivos, links simbolicos e servicos do Krill"
        echo "-h,       --help,                 Mostra esse menu de ajuda"
        echo "\nPara configurar um RPKI do zero, deve-se: criar a CA, gerar a Child Request, inserir ela no registro.br, salvar o Parent Response e inserir no Krill e criar os ROAS.\n\nPortanto, em uma primeira configuração utilize os módulos um de cada vez nessa ordem: -i, -c, -r, -p e depois criar as ROAS manualmente ou automaticamente com -o.\n\n"
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
        publica_roas
        exit 0
        ;;

        --publica-roas)
        publica_roas
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