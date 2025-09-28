#!/usr/bin/env bash

#-----------------------------------------------------------------------------------------------------------
#	DATA:				07 de Março de 2017
#	SCRIPT:				ShellBot.sh
#	VERSÃO:				6.4.0
#	DESENVOLVIDO POR:	Juliano Santos [SHAMAN]
#	PÁGINA:				http://www.shellscriptx.blogspot.com.br
#	FANPAGE:			https://www.facebook.com/shellscriptx
#	GITHUB:				https://github.com/shellscriptx
# 	CONTATO:			shellscriptx@gmail.com
#
#	DESCRIÇÃO:			ShellBot é uma API não-oficial desenvolvida para facilitar a criação de 
#						bots na plataforma TELEGRAM. Constituída por uma coleção de métodos
#						e funções que permitem ao desenvolvedor:
#
#							* Gerenciar grupos, canais e membros.
#							* Enviar mensagens, documentos, músicas, contatos e etc.
#							* Enviar teclados (KeyboardMarkup e InlineKeyboard).
#							* Obter informações sobre membros, arquivos, grupos e canais.
#							* Para mais informações consulte a documentação:
#							  
#							https://github.com/shellscriptx/ShellBot/wiki
#
#						O ShellBot mantém o padrão da nomenclatura dos métodos registrados da
#						API original (Telegram), assim como seus campos e valores. Os métodos
#						requerem parâmetros e argumentos para a chamada e execução. Parâmetros
#						obrigatórios retornam uma mensagem de erro caso o argumento seja omitido.
#					
#	NOTAS:				Desenvolvida na linguagem Shell Script, utilizando o interpretador de 
#						comandos BASH e explorando ao máximo os recursos built-in do mesmo,
#						reduzindo o nível de dependências de pacotes externos.
#-----------------------------------------------------------------------------------------------------------

[[ $_SHELLBOT_SH_ ]] && return 1

if ! awk 'BEGIN { exit ARGV[1] < 4.3 }' ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}; then
	echo "${BASH_SOURCE:-${0##*/}}: error: requires 'bash 4.3' or higher command interpreter." 1>&2
	exit 1
fi

# Informações
readonly -A _SHELLBOT_=(
[name]='ShellBot'
[keywords]='Shell Script Telegram API'
[description]='Unofficial API for creating bots on the Telegram platform.'
[version]='6.4.0'
[language]='shellscript'
[shell]=${SHELL}
[shell_version]=${BASH_VERSION}
[author]='Juliano Santos [SHAMAN]'
[email]='shellscriptx@gmail.com'
[wiki]='https://github.com/shellscriptx/shellbot/wiki'
[github]='https://github.com/shellscriptx/shellbot'
[packages]='curl 7.0, getopt 2.0, jq 1.5'
)

# Verifica dependências.
while read _pkg_ _ver_; do
	if command -v $_pkg_ &>/dev/null; then
		if [[ $($_pkg_ --version 2>&1) =~ [0-9]+\.[0-9]+ ]]; then
			if ! awk 'BEGIN { exit ARGV[1] < ARGV[2] }' $BASH_REMATCH $_ver_; then
				printf "%s: error: requires package '% s% s' or higher.\n" ${_SHELLBOT_[name]} $_pkg_ $_ver_ 1>&2
				exit 1
			fi
		else
			printf "%s: error: '% s' could not get the version.\n" ${_SHELLBOT_[name]} $_pkg_ 1>&2
			exit 1
		fi
	else
		printf "%s: error: '% s' the required package is missing.\n" ${_SHELLBOT_[name]} $_pkg_ 1>&2
		exit 1
	fi
done <<< "${_SHELLBOT_[packages]//,/$'\n'}"

# bash (opções).
shopt -s	checkwinsize			\
			cmdhist					\
			complete_fullquote		\
			expand_aliases			\
			extglob					\
			extquote				\
			force_fignore			\
			histappend				\
			interactive_comments	\
			progcomp				\
			promptvars				\
			sourcepath

# Desabilita a expansão de nomes de arquivos (globbing).
set -f

readonly _SHELLBOT_SH_=1					# Inicialização
readonly _BOT_SCRIPT_=${0##*/}				# Script
readonly _CURL_OPT_='--silent --request'	# CURL (opções)

# Erros
readonly _ERR_TYPE_BOOL_='incompatible type: only supports "true" or "false".'
readonly _ERR_TYPE_INT_='incompatible type: supports integer only.'
readonly _ERR_TYPE_FLOAT_='incompatible type: only supports float.'
readonly _ERR_PARAM_REQUIRED_='required option: check if the mandatory parameter (s) or argument (s) are present.'
readonly _ERR_TOKEN_UNAUTHORIZED_='unauthorized: check if you have permissions to use the token.'
readonly _ERR_TOKEN_INVALID_='invalid token: check the token number and try again.'
readonly _ERR_BOT_ALREADY_INIT_='action not allowed: the bot has already been initialized.'
readonly _ERR_FILE_NOT_FOUND_='failed to access: the file could not be read.'
readonly _ERR_DIR_WRITE_DENIED_='permission denied: it is not possible to write to the directory.'
readonly _ERR_DIR_NOT_FOUND_='Could not access: directory not found.'
readonly _ERR_FILE_INVALID_ID_='invalid id: file not found.'
readonly _ERR_UNKNOWN_='unknown error: an unexpected failure has occurred. Report the problem to the developer.'
readonly _ERR_SERVICE_NOT_ROOT_='Access Denied: Requires root privileges.'
readonly _ERR_SERVICE_EXISTS_='error creating the service: the service name already exists.'
readonly _ERR_SERVICE_SYSTEMD_NOT_FOUND_='error when activating: the system does not support "systemd" service management.'
readonly _ERR_SERVICE_USER_NOT_FOUND_='user not found: the user account entered is invalid.'
readonly _ERR_VAR_NAME_='variable not found: the identifier is invalid or does not exist.'
readonly _ERR_FUNCTION_NOT_FOUND_='function not found: the specified identifier is invalid or does not exist.'
readonly _ERR_ARG_='invalid argument: the argument is not supported by the specified parameter.'
readonly _ERR_RULE_ALREADY_EXISTS_='failed to define: the name of the rule already exists.'
readonly _ERR_HANDLE_EXISTS_='error when registering: there is already a handle linked to the callback'
readonly _ERR_CONNECTION_='connection failure: connection to Telegram could not be established.'

# Maps
declare -A _BOT_HANDLE_
declare -A _BOT_RULES_
declare -A return

declare -i _BOT_RULES_INDEX_
declare _VAR_INIT_

Json() { local obj=$(jq -Mc "$1" <<< "${*:2}"); obj=${obj#\"}; echo "${obj%\"}"; }

SetDelmValues(){ 
	local obj=$(jq "[..|select(type == \"string\" or type == \"number\" or type == \"boolean\")|tostring]|join(\"${_BOT_DELM_/\"/\\\"}\")" <<< "$1")
	obj=${obj#\"}; echo "${obj%\"}"
}

GetAllValues(){
	jq '[..|select(type == "string" or type == "number" or type == "boolean")|tostring]|.[]' <<< "$1"
}

GetAllKeys(){
	jq -r 'path(..|select(type == "string" or type == "number" or type == "boolean"))|map(if type == "number" then .|tostring|"["+.+"]" else . end)|join(".")|gsub("\\.\\[";"[")' <<< "$1"
}

FlagConv()
{
	local var str=$2

	while [[ $str =~ \$\{([a-z_]+)\} ]]; do
		if [[ ${BASH_REMATCH[1]} == @(${_VAR_INIT_// /|}) ]]; then
			var=${BASH_REMATCH[1]}[$1]
			str=${str//${BASH_REMATCH[0]}/${!var}}
		else
			str=${str//${BASH_REMATCH[0]}}
		fi
	done

	echo "$str"
}

CreateLog()
{
	local fid fbot fname fuser lcode cid ctype 
	local ctitle mid mdate mtext etype
	local i fmt obj oid

	for ((i=0; i < $1; i++)); do
		
		printf -v fmt "$_BOT_LOG_FORMAT_" || MessageError API
		
		# Suprimir erros.
		exec 5<&2
		exec 2<&-

		# Objeto (tipo)
		if 		[[ ${message_contact_phone_number[$i]:-${edited_message_contact_phone_number[$i]}}					]] ||
				[[ ${channel_post_contact_phone_number[$i]:-${edited_channel_post_contact_phone_number[$i]}}		]]; then obj=contact
		elif	[[ ${message_sticker_file_id[$i]:-${edited_message_sticker_file_id[$i]}}							]] ||
				[[ ${channel_post_sticker_file_id[$i]:-${edited_channel_post_sticker_file_id[$i]}}					]]; then obj=sticker
		elif	[[ ${message_animation_file_id[$i]:-${edited_message_animation_file_id[$i]}}						]] ||
				[[ ${channel_post_animation_file_id[$i]:-${edited_channel_post_animation_file_id[$i]}}				]]; then obj=animation
		elif	[[ ${message_photo_file_id[$i]:-${edited_message_photo_file_id[$i]}}								]] ||
				[[ ${channel_post_photo_file_id[$i]:-${edited_channel_post_photo_file_id[$i]}}						]]; then obj=photo
		elif	[[ ${message_audio_file_id[$i]:-${edited_message_audio_file_id[$i]}}								]] ||
				[[ ${channel_post_audio_file_id[$i]:-${edited_channel_post_audio_file_id[$i]}}						]]; then obj=audio
		elif	[[ ${message_video_file_id[$i]:-${edited_message_video_file_id[$i]}}								]] ||
				[[ ${channel_post_video_file_id[$i]:-${edited_channel_post_video_file_id[$i]}}						]]; then obj=video
		elif	[[ ${message_voice_file_id[$i]:-${edited_message_voice_file_id[$i]}}								]] ||
				[[ ${channel_post_voice_file_id[$i]:-${edited_channel_post_voice_file_id[$i]}}						]]; then obj=voice
		elif	[[ ${message_document_file_id[$i]:-${edited_message_document_file_id[$i]}}							]] ||
				[[ ${channel_post_document_file_id[$i]:-${edited_channel_post_document_file_id[$i]}}				]]; then obj=document
		elif	[[ ${message_venue_location_latitude[$i]:-${edited_message_venue_location_latitude[$i]}}			]] ||
				[[ ${channel_post_venue_location_latitude[$i]-${edited_channel_post_venue_location_latitude[$i]}}	]]; then obj=venue
		elif	[[ ${message_location_latitude[$i]:-${edited_message_location_latitude[$i]}}						]] ||
				[[ ${channel_post_location_latitude[$i]:-${edited_channel_post_location_latitude[$i]}}				]]; then obj=location
		elif	[[ ${message_text[$i]:-${edited_message_text[$i]}}													]] ||
				[[ ${channel_post_text[$i]:-${edited_channel_post_text[$i]}}										]]; then obj=text
		elif 	[[ ${callback_query_id[$i]}																			]]; then obj=callback
		elif 	[[ ${inline_query_id[$i]}																			]]; then obj=inline
		elif	[[ ${chosen_inline_result_result_id[$i]}															]]; then obj=chosen
		fi
	
		# Objeto (id)	
		[[ ${oid:=${message_contact_phone_number[$i]}} 				]] ||
		[[ ${oid:=${message_sticker_file_id[$i]}}					]] ||
		[[ ${oid:=${message_animation_file_id[$i]}}					]] ||
		[[ ${oid:=${message_photo_file_id[$i]}}						]] ||
		[[ ${oid:=${message_audio_file_id[$i]}}						]] ||
		[[ ${oid:=${message_video_file_id[$i]}}						]] ||
		[[ ${oid:=${message_voice_file_id[$i]}}						]] ||
		[[ ${oid:=${message_document_file_id[$i]}}					]] ||
		[[ ${oid:=${edited_message_contact_phone_number[$i]}} 		]] ||
		[[ ${oid:=${edited_message_sticker_file_id[$i]}}			]] ||
		[[ ${oid:=${edited_message_animation_file_id[$i]}}			]] ||
		[[ ${oid:=${edited_message_photo_file_id[$i]}}				]] ||
		[[ ${oid:=${edited_message_audio_file_id[$i]}}				]] ||
		[[ ${oid:=${edited_message_video_file_id[$i]}}				]] ||
		[[ ${oid:=${edited_message_voice_file_id[$i]}}				]] ||
		[[ ${oid:=${edited_message_document_file_id[$i]}}			]] ||
		[[ ${oid:=${channel_post_contact_phone_number[$i]}} 		]] ||
		[[ ${oid:=${channel_post_sticker_file_id[$i]}}				]] ||
		[[ ${oid:=${channel_post_animation_file_id[$i]}}			]] ||
		[[ ${oid:=${channel_post_photo_file_id[$i]}}				]] ||
		[[ ${oid:=${channel_post_audio_file_id[$i]}}				]] ||
		[[ ${oid:=${channel_post_video_file_id[$i]}}				]] ||
		[[ ${oid:=${channel_post_voice_file_id[$i]}}				]] ||
		[[ ${oid:=${channel_post_document_file_id[$i]}}				]] ||
		[[ ${oid:=${edited_channel_post_contact_phone_number[$i]}} 	]] ||
		[[ ${oid:=${edited_channel_post_sticker_file_id[$i]}}		]] ||
		[[ ${oid:=${edited_channel_post_animation_file_id[$i]}}		]] ||
		[[ ${oid:=${edited_channel_post_photo_file_id[$i]}}			]] ||
		[[ ${oid:=${edited_channel_post_audio_file_id[$i]}}			]] ||
		[[ ${oid:=${edited_channel_post_video_file_id[$i]}}			]] ||
		[[ ${oid:=${edited_channel_post_voice_file_id[$i]}}			]] ||
		[[ ${oid:=${edited_channel_post_document_file_id[$i]}}		]] ||
		[[ ${oid:=${message_message_id[$i]}}						]] ||
		[[ ${oid:=${edited_message_message_id[$i]}}					]] ||
		[[ ${oid:=${channel_post_message_id[$i]}}					]] ||
		[[ ${oid:=${edited_channel_post_message_id[$i]}}			]] ||
		[[ ${oid:=${callback_query_id[$i]}}							]] ||
		[[ ${oid:=${inline_query_id[$i]}} 							]] ||
		[[ ${oid:=${chosen_inline_result_result_id[$i]}}			]]

		# Remetente (id)
		[[ ${fid:=${message_from_id[$i]}}				]] ||
		[[ ${fid:=${edited_message_from_id[$i]}} 		]] ||
		[[ ${fid:=${callback_query_from_id[$i]}} 		]] ||
		[[ ${fid:=${inline_query_from_id[$i]}} 			]] ||
		[[ ${fid:=${chosen_inline_result_from_id[$i]}} 	]]

		# Bot
		[[ ${fbot:=${message_from_is_bot[$i]}} 				]] ||
		[[ ${fbot:=${edited_message_from_is_bot[$i]}} 		]] ||
		[[ ${fbot:=${callback_query_from_is_bot[$i]}} 		]] ||
		[[ ${fbot:=${inline_query_from_is_bot[$i]}} 		]] ||
		[[ ${fbot:=${chosen_inline_result_from_is_bot[$i]}} ]]

		# Usuário (nome)
		[[ ${fname:=${message_from_first_name[$i]}} 				]] ||
		[[ ${fname:=${edited_message_from_first_name[$i]}}			]] ||
		[[ ${fname:=${callback_query_from_first_name[$i]}} 			]] ||
		[[ ${fname:=${inline_query_from_first_name[$i]}}			]] ||
		[[ ${fname:=${chosen_inline_result_from_first_name[$i]}}	]] ||
		[[ ${fname:=${channel_post_author_signature[$i]}}			]] ||
		[[ ${fname:=${edited_channel_post_author_signature[$i]}}	]]

		# Usuário (conta)
		[[ ${fuser:=${message_from_username[$i]}}				]] ||
		[[ ${fuser:=${edited_message_from_username[$i]}} 		]] ||
		[[ ${fuser:=${callback_query_from_username[$i]}} 		]] ||
		[[ ${fuser:=${inline_query_from_username[$i]}} 			]] ||
		[[ ${fuser:=${chosen_inline_result_from_username[$i]}} 	]]

		# Idioma
		[[ ${lcode:=${message_from_language_code[$i]}} 				]] ||
		[[ ${lcode:=${edited_message_from_language_code[$i]}} 		]] ||
		[[ ${lcode:=${callback_query_from_language_code[$i]}} 		]] ||
		[[ ${lcode:=${inline_query_from_language_code[$i]}} 		]] ||
		[[ ${lcode:=${chosen_inline_result_from_language_code[$i]}}	]]

		# Bate-papo (id)
		[[ ${cid:=${message_chat_id[$i]}}					]] ||
		[[ ${cid:=${edited_message_chat_id[$i]}}			]] ||
		[[ ${cid:=${callback_query_message_chat_id[$i]}} 	]] ||
		[[ ${cid:=${channel_post_chat_id[$i]}}				]] ||
		[[ ${cid:=${edited_channel_post_chat_id[$i]}}		]]

		# Bate-papo (tipo)
		[[ ${ctype:=${message_chat_type[$i]}} 					]] ||
		[[ ${ctype:=${edited_message_chat_type[$i]}} 			]] ||
		[[ ${ctype:=${callback_query_message_chat_type[$i]}} 	]] ||
		[[ ${ctype:=${channel_post_chat_type[$i]}}				]] ||
		[[ ${ctype:=${edited_channel_post_chat_type[$i]}}		]]

		# Bate-papo (título)
		[[ ${ctitle:=${message_chat_title[$i]}}					]] ||
		[[ ${ctitle:=${edited_message_chat_title[$i]}} 			]] ||
		[[ ${ctitle:=${callback_query_message_chat_title[$i]}} 	]] ||
		[[ ${ctitle:=${channel_post_chat_title[$i]}}			]] ||
		[[ ${ctitle:=${edited_channel_post_chat_title[$i]}}		]]

		# Mensagem (id)
		[[ ${mid:=${message_message_id[$i]}} 				]] ||
		[[ ${mid:=${edited_message_message_id[$i]}} 		]] ||
		[[ ${mid:=${callback_query_id[$i]}} 				]] ||
		[[ ${mid:=${inline_query_id[$i]}} 					]] ||
		[[ ${mid:=${chosen_inline_result_result_id[$i]}}	]] ||
		[[ ${mid:=${channel_post_message_id[$i]}}			]] ||
		[[ ${mid:=${edited_channel_post_message_id[$i]}}	]]

		# Mensagem (data)
		[[ ${mdate:=${message_date[$i]}}				]] ||
		[[ ${mdate:=${edited_message_date[$i]}} 		]] ||
		[[ ${mdate:=${callback_query_message_date[$i]}}	]] ||
		[[ ${mdate:=${channel_post_date[$i]}}			]] ||
		[[ ${mdate:=${edited_channel_post_date[$i]}}	]]

		# Mensagem (texto)
		[[ ${mtext:=${message_text[$i]}} 				]] ||
		[[ ${mtext:=${edited_message_text[$i]}} 		]] ||
		[[ ${mtext:=${callback_query_message_text[$i]}} ]] ||
		[[ ${mtext:=${inline_query_query[$i]}} 			]] ||
		[[ ${mtext:=${chosen_inline_result_query[$i]}}	]] ||
		[[ ${mtext:=${channel_post_text[$i]}}			]] ||
		[[ ${mtext:=${edited_channel_post_text[$i]}}	]]

		# Mensagem (tipo)
		[[ ${etype:=${message_entities_type[$i]}} 					]] ||
		[[ ${etype:=${edited_message_entities_type[$i]}} 			]] ||
		[[ ${etype:=${callback_query_message_entities_type[$i]}}	]] ||
		[[ ${etype:=${channel_post_entities_type[$i]}}				]] ||
		[[ ${etype:=${edited_channel_post_entities_type[$i]}}		]]

		# Flags
		fmt=${fmt//\{BOT_TOKEN\}/${_BOT_INFO_[0]:--}}
		fmt=${fmt//\{BOT_ID\}/${_BOT_INFO_[1]:--}}
		fmt=${fmt//\{BOT_FIRST_NAME\}/${_BOT_INFO_[2]:--}}
		fmt=${fmt//\{BOT_USERNAME\}/${_BOT_INFO_[3]:--}}
		fmt=${fmt//\{BASENAME\}/${_BOT_SCRIPT_:--}}
		fmt=${fmt//\{OK\}/${return[ok]:-${ok:--}}}
		fmt=${fmt//\{UPDATE_ID\}/${update_id[$i]:--}}
		fmt=${fmt//\{OBJECT_TYPE\}/${obj:--}}
		fmt=${fmt//\{OBJECT_ID\}/${oid:--}}
		fmt=${fmt//\{FROM_ID\}/${fid:--}}
		fmt=${fmt//\{FROM_IS_BOT\}/${fbot:--}}
		fmt=${fmt//\{FROM_FIRST_NAME\}/${fname:--}}
		fmt=${fmt//\{FROM_USERNAME\}/${fuser:--}}
		fmt=${fmt//\{FROM_LANGUAGE_CODE\}/${lcode:--}}
		fmt=${fmt//\{CHAT_ID\}/${cid:--}}
		fmt=${fmt//\{CHAT_TYPE\}/${ctype:--}}
		fmt=${fmt//\{CHAT_TITLE\}/${ctitle:--}}
		fmt=${fmt//\{MESSAGE_ID\}/${mid:--}}
		fmt=${fmt//\{MESSAGE_DATE\}/${mdate:--}}
		fmt=${fmt//\{MESSAGE_TEXT\}/${mtext:--}}
		fmt=${fmt//\{ENTITIES_TYPE\}/${etype:--}}
		fmt=${fmt//\{METHOD\}/${FUNCNAME[2]/main/ShellBot.getUpdates}}
		fmt=${fmt//\{RETURN\}/$(SetDelmValues "$2")}

		exec 2<&5

		# log
		[[ $fmt ]] && { echo "$fmt" >> "$_BOT_LOG_FILE_" || MessageError API; }

		# Limpa objetos
		fid= fbot= fname= fuser= lcode= cid= ctype= 
		ctitle= mid= mdate= mtext= etype= obj= oid=
	done

	return $?
}

MethodReturn()
{
	# Retorno
	case $_BOT_TYPE_RETURN_ in
		json) echo "$1";;
		value) SetDelmValues "$1";;
		map)
			local key val vars vals i obj
			return=()

			mapfile -t vars <<< $(GetAllKeys "$1")
			mapfile -t vals <<< $(GetAllValues "$1")

			for i in ${!vars[@]}; do
				key=${vars[$i]//[0-9\[\]]/}
				key=${key#result.}
				key=${key//./_}

				val=${vals[$i]}
				val=${val#\"}
				val=${val%\"}
				
				[[ ${return[$key]} ]] && return[$key]+=${_BOT_DELM_}${val} || return[$key]=$val
				[[ $_BOT_MONITOR_ ]] && printf "[%s]: return[%s] = '%s'\n" "${FUNCNAME[1]}" "$key" "$val"
			done
			;;
	esac
	
	[[ $(jq -r '.ok' <<< "$1") == true ]]

	return $?
}

MessageError()
{
	# Variáveis locais
	local err_message err_param assert i
	
	# A variável 'BASH_LINENO' é dinâmica e armazena o número da linha onde foi expandida.
	# Quando chamada dentro de um subshell, passa ser instanciada como um array, armazenando diversos
	# valores onde cada índice refere-se a um shell/subshell. As mesmas caracteristicas se aplicam a variável
	# 'FUNCNAME', onde é armazenado o nome da função onde foi chamada.
	
	# Obtem o índice da função na hierarquia de chamada.
	[[ ${FUNCNAME[1]} == CheckArgType ]] && i=2 || i=1
	
	# Lê o tipo de ocorrência.
	# TG - Erro externo retornado pelo core do telegram.
	# API - Erro interno gerado pela API do ShellBot.
	case $1 in
		TG)
			err_param="$(Json '.error_code' "$2")"
			err_message="$(Json '.description' "$2")"
			;;
		API)
			err_param="${3:--}: ${4:--}"
			err_message="$2"
			assert=true
			;;
	esac

	# Imprime erro
	printf "%s: erro: linha %s: %s: %s: %s\n"					\
							"${_BOT_SCRIPT_}"					\
							"${BASH_LINENO[$i]:--}" 			\
							"${FUNCNAME[$i]:--}" 				\
							"${err_param:--}" 					\
							"${err_message:-$_ERR_UNKNOWN_}" 	1>&2 

	# Finaliza script/thread em caso de erro interno, caso contrário retorna 1
	${assert:-false} && exit 1 || return 1
}

CheckArgType()
{
	# CheckArgType recebe os dados da função chamadora e verifica
	# o dado recebido com o tipo suportado pelo parâmetro.
	# É retornado '0' para sucesso, caso contrário uma mensagem
	# de erro é retornada e o script/thread é finalizado com status '1'.
	case $1 in
		user)		id "$3" &>/dev/null						|| MessageError API "$_ERR_SERVICE_USER_NOT_FOUND_" "$2" "$3";;
		func)		[[ $(type -t "$3") == function			]] 	|| MessageError API "$_ERR_FUNCTION_NOT_FOUND_" "$2" "$3";;
		var)		[[ -v $3 								]] 	|| MessageError API "$_ERR_VAR_NAME_" "$2" "$3";;
		int)		[[ $3 =~ ^-?[0-9]+$ 					]] 	|| MessageError API "$_ERR_TYPE_INT_" "$2" "$3";;
		float)		[[ $3 =~ ^-?[0-9]+\.[0-9]+$ 			]] 	|| MessageError API "$_ERR_TYPE_FLOAT_" "$2" "$3";;
		bool)		[[ $3 =~ ^(true|false)$ 				]] 	|| MessageError API "$_ERR_TYPE_BOOL_" "$2" "$3";;
		token)		[[ $3 =~ ^[0-9]+:[a-zA-Z0-9_-]+$		]] 	|| MessageError API "$_ERR_TOKEN_INVALID_" "$2" "$3";;
		file)		[[ $3 =~ ^@ && ! -f ${3#@} 				]] 	&& MessageError API "$_ERR_FILE_NOT_FOUND_" "$2" "$3";;
		return)		[[ $3 == @(json|map|value) 				]] 	|| MessageError API "$_ERR_ARG_" "$2" "$3";;
		cmd)		[[ $3 =~ ^/[a-zA-Z0-9_]+$ 				]] 	|| MessageError API "$_ERR_ARG_" "$2" "$3";;
		flag)		[[ $3 =~ ^[a-zA-Z0-9_]+$ 				]] 	|| MessageError API "$_ERR_ARG_" "$2" "$3";;
	esac

	return $?
}

FlushOffset()
{    
	local sid eid jq_obj

	while :; do
		jq_obj=$(ShellBot.getUpdates --limit 100 --offset $(ShellBot.OffsetNext))
		IFS=
