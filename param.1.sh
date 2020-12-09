#shellcheck shell=bash

# author:       Li Junhao           edwin.jh.lee@gmail.com    edwinjhlee.github.io
# maintainer:   Li Junhao

@src std/assert

str.repr(){
    printf '"%s"' "${1//\"/\\\"}"
}

list.repr(){
    printf "( "
    for i in "$@"; do
        printf '"%s" ' "${i//\"/\\\"}"
    done
    printf ")"
}

str.trim(){
    local var="$*"
    # remove leading whitespace characters
    var="${var#"${var%%[![:space:]]*}"}"
    # remove trailing whitespace characters
    var="${var%"${var##*[![:space:]]}"}"
    echo -n "$var"
}

line.to_array.trim.ignore_empty(){
    local name=${1:?Array name}
    local line arr=() IFS=
    while read -r line; do
        line="$(str.trim "$line")"
        [ "$line" = "" ] && continue
        arr+=("$line")
    done <<< "$(cat -)"
    eval "$name"'=("${arr[@]}")'
}

param.debug(){
    local IFS=
    [[ "$X_BASH_DEBUG" =~ (^|,)param($|,) ]] && printf "DBG: %s" "$@" >&2
}

# shellcheck disable=SC2142
# alias param='if ! eval "$(param.__parse "${FUNCNAME[0]}" "$@")"; then param.help.show; return $? 2>/dev/null || exit $?; fi <<<'
# alias param='eval "$(param.__parse "${FUNCNAME[0]}" "$@")" <<<'
# alias param='{ eval "$(param.__parse "${FUNCNAME[0]:-$0}" "$@")"; } <<<'

# alias param='
#     local _param_code 2>/dev/null; 
#     _param_code="$(param.__parse "${FUNCNAME[0]:-$0}" "$@")"
#     if [ $? -eq 0 ]; then 
#         eval "${_param_code}"
#     else
#         return $? 2>/dev/null || exit $?; 
#     fi <<<'


# shellcheck disable=SC2154
alias param='
    local _param_code _param_help_docs=() 2>/dev/null; 
    { 
        _param_code="$(param.__parse "${FUNCNAME[0]:-$0}" "$@")"; 
        case "$?" in
            0) eval "$_param_code" ;;
            1) return 1 2>/dev/null || exit 1 ;;
            *) return 0 ;;
        esac
    } <<<'

alias param='param.__parse "${FUNCNAME[0]:-$0}" "$@" <<<'

alias show_help_then_return_or_exit="param.help.show; return 1 2>/dev/null || exit 1; "

param.help.show(){
    param.help "$funcname" "${_param_help_docs[@]}" >&2
    param.example.show >&2
}

param._type.check(){
    local code name="$1" val="$2" op="$3"; shift 3;
    assert "$val" "$op" "$@"
    code=$?
    if [ $code -eq 1 ]; then
        echo "Parameter check ERROR: $name" >&2
        param.help.show
        return 1
    fi

    if [[ "$name" == \\\$* ]]; then
        return 0
    fi

    if [[ "$op" == '=~['?']' || "$op" == '=['?']' ]]; then
        local sep=${op:((${#op}-2)):1}
        # shellcheck disable=SC2207
        local data=( $(echo "$val" | tr "$sep" '\n') ) # should not quote '$(...)'
        [ ${#data[@]} -eq 0 ] && data=("")

        echo "local $name 2>/dev/null"
        echo "$name=$(list.repr "${data[@]}")"
    else
        echo "local $name 2>/dev/null"
        echo "$name=$(str.repr "$val")"
    fi

    return 0
}


param._type.check(){
    # shellcheck disable=SC2016
    local CHOICE_LIST_MUST_NOT_BE_EMTPY='
        [ "${#@}" -eq 0 ] && {
            echo "ERROR: Please provide candidate list right after $op for parameter[$name]" >&2
            param.help.show
            return 0
        }
    '

    local IFS=$'\n'

    local name="$1" val="$2" op="$3"; shift 3
    case "$op" in
    =~)
        eval "$CHOICE_LIST_MUST_NOT_BE_EMTPY"
        if ! assert.within_regex "$val" "$@"; then
            echo "ERROR:  $name='$val' NOT match any regex defined" >&2
            param.help.show
            return 1
        fi;;
    =)
        eval "$CHOICE_LIST_MUST_NOT_BE_EMTPY"
        if ! assert.within "$val" "$@"; then
            # echo "$val" "$@" >&2
            echo "ERROR: $name='$val' Not one of the candidate set." >&2
            param.help.show
            return 1
        fi ;;
    =str | =int)
        if [ -z "${val}" ]; then
            echo "ERROR: A non-null value is expected for parameter: $name" >&2
            param.help.show
            return 1
        fi

        if [ "$op" = "=int" ]; then
            if  [[ ! "$val" =~ ^[\ \t]*[0-9]+[\ \t]*$ ]]; then
                echo "ERROR: $name='$val' An integer expected." >&2
                param.help.show
                return 1
            fi
        fi

        [ "${#@}" -ne 0 ] && {
            if ! assert.within "$val" "$@"; then
                echo "ERROR: $name='$val' Not inside the $op set." >&2
                param.help.show
                return 1
            fi 
        };;
    =\[?\] | =?)
        eval "$CHOICE_LIST_MUST_NOT_BE_EMTPY"

        local sep=${op:1:1};
        [[ "$op" == '=['?']' ]] &&  sep=${op:2:1}
        # shellcheck disable=SC2207
        local data=( $(echo "$val" | tr "$sep" '\n') ) # should not quote '$(...)'
        [ ${#data[@]} -eq 0 ] && data=("")

        local datum
        for datum in "${data[@]}"; do
            if ! assert.within "$datum" "$@"; then
                echo "ERROR: [$name='$val'] After splited with \'$sep\', element '$datum' does NOT match the string set" >&2
                param.help.show
                return 1
            fi
        done

        if [[ "$op" == '=['?']' ]]; then
            [[ ! "$name" == \\\$* ]] && {
                echo "local $name 2>/dev/null"
                echo "$name=$(list.repr "${data[@]}")"
            }
            return 0 # continue
        fi ;;
    =~\[?\] | =~? )
        eval "$CHOICE_LIST_MUST_NOT_BE_EMTPY"

        local sep=${op:2:1};    
        [[ "$op" == '=~['?']' ]] && sep=${op:3:1}
        # shellcheck disable=SC2207
        local data=( $(echo "$val" | tr "$sep" '\n') ) # should not quote '$(...)'
        [ ${#data[@]} -eq 0 ] && data=("")

        local datum
        for datum in "${data[@]}"; do
            assert.within_regex "$datum" "$@" && continue
            echo "ERROR: [$name='$val']. After splited with \'$sep\', element '$datum' does NOT match the regex set." >&2
            param.help.show
            return 1
        done

        if [[ "$op" == '=~['?']' ]]; then
            [[ ! "$name" == \\\$* ]] && {
                echo "local $name 2>/dev/null"
                echo "$name=$(list.repr "${data[@]}")"
            }
            return 0 # continue
        fi ;;
    *)  [ "$op" == "" ] || echo ": TODO: $op" >&2 ;;
    esac

    [[ ! "$name" == \\\$* ]] && {
        echo "local $name 2>/dev/null"
        echo "$name=$(str.repr "$val")"
    }
    return 0
}

param.__parse.add_help_doc_item(){
    local IFS

    local name="${1}" # $1
    local desc="${2}" # $3
    local op="${3}"
    local default="${4}"
    shift; shift; shift; shift

    local type_desc="" o

    case "$op" in
        = | ==) IFS='|'; type_desc="$*";;
        =~) IFS='|'; type_desc="Regex pattern: $*";;
        =str) IFS='|'; [ $# -eq 0 ] && type_desc="String" || type_desc="String: $*" ;;
        =int) IFS='|'; [ $# -eq 0 ] && type_desc="Int" || type_desc="Int: $*" ;;
        =\[?\]) 
            o="${op:2:1}"
            IFS=' '; type_desc="Join by '$o'. Item: $*"
            ;;
        =~\[?\])
            o="${op:3:1}"
            IFS=' '; type_desc="Join by '$o'. Item match regex: $*"
            ;;
        *) type_desc=""
    esac

    _param_help_docs+=( "$name" "$default" "$type_desc" "$desc")

}

param.__parse(){
    local i IFS=$'\n'
    local funcname="$1"; shift

    local varlist=()    typelist=()     deslist=()
    local vallist=()    deflist=()      # default
    local oplist=()     choicelist=()

    local arg_description arg_deslist=() arg_oplist=() arg_choicelist=()
    local rest_argv_des="" rest_argv_op="" rest_argv_choices=()

    local linelist=() line nextline lineindex all_arg_arr all_arg_arr2
    line.to_array.trim.ignore_empty linelist 

    # Step 1: Parsing into tokens
    # for line in "${linelist[@]}"; do
    for (( lineindex=0; lineindex < ${#linelist[@]}; lineindex++ )); do
        line="${linelist[lineindex]}"

        # shellcheck disable=SC2207 # this rule is wrong
        all_arg_arr=( $(echo "$line" | xargs -n 1) ) # all_arg_arr=( "$(str.arg "$line")" )

        nextline="${linelist[lineindex+1]}"
        if [[ "$nextline" = =* ]]; then
            # shellcheck disable=SC2207 # this rule is wrong
            all_arg_arr2=( $(echo "$nextline" | xargs -n 1) )
            # TODO: !!!
            all_arg_arr+=( "${all_arg_arr2[@]}" )
            (( lineindex ++ ))
        fi

        varname="${all_arg_arr[0]}"
        ###### BEGIN: handle #1 like
        if [[ "$varname" =~ \#[[:digit:]]+ ]]; then
            # echo "KKK $varname" >&2
            varname="${varname:1}"
            case "${all_arg_arr[1]}" in
            = | =~ | =str | =str? | =float | =int | =\[?\] | =? | =~\[?\] | =~? )
                arg_description=""
                arg_oplist+=( "${all_arg_arr[1]}" )
                arg_choicelist+=( "${all_arg_arr[*]:2}" ) 
                param.__parse.add_help_doc_item "$varname" "$arg_description" "${all_arg_arr[1]}" "" "${all_arg_arr[@]:2}"
                ;;
            *)
                arg_description="${all_arg_arr[1]}"
                arg_oplist+=( "${all_arg_arr[2]}" )
                arg_choicelist+=( "${all_arg_arr[*]:3}" ) 
                param.__parse.add_help_doc_item "$varname" "$arg_description" "${all_arg_arr[2]}" "" "${all_arg_arr[@]:3}"
                ;;
            esac
            arg_deslist+=("$arg_description")
            continue
        fi
        ###### END: handle #1 like

        ###### BEGIN: handle ... for rest_argv
        if [ "$varname" = "..." ]; then
            # IFS=
            case "${all_arg_arr[1]}" in
            = | =~ | =str | =str? | =float | =int | =\[?\] | =? | =~\[?\] | =~? )
                rest_argv_op="${all_arg_arr[1]}"
                rest_argv_choices=( "${all_arg_arr[@]:2}" )
                param.__parse.add_help_doc_item "$varname" "" "${all_arg_arr[1]}" "" "${all_arg_arr[@]:2}"
                ;;
            *)
                rest_argv_des="${all_arg_arr[1]}"
                rest_argv_op="${all_arg_arr[2]}"
                rest_argv_choices=( "${all_arg_arr[@]:3}" )

                param.__parse.add_help_doc_item "$varname" "$rest_argv_des" "${all_arg_arr[2]}" "" "${all_arg_arr[@]:3}"
                ;;
            esac
            IFS=$'\n'
            continue
        fi
        ###### END: handle ... for rest_argv
        
        if [[ "$varname" =~ ^(arg)+((ENV)|(env))+: ]]; then
            typelist+=( "${varname%%:*}" )
            varname="${varname#*:}"
        else
            typelist+=("arg")
        fi

        local default
        if [[ "$varname" == *=* ]]; then
            default="${varname#*=}"
            varname="${varname%%=*}"
            varlist+=("$varname")
            vallist+=("$default") # Default value
            deflist+=("$default")
        else
            default=""
            varlist+=("$varname")
            vallist+=("")
            deflist+=("")
        fi
        
        IFS=$'\n'
        local description op
        case "${all_arg_arr[1]}" in
        = | =~ | =str | =str? | =float | =int | =\[?\] | =? | =~\[?\] | =~? )
            description=""
            op="${all_arg_arr[1]}"
            choicelist+=( "${all_arg_arr[*]:2}" ) 
            param.__parse.add_help_doc_item "$varname" "$description" "$op" "$default" "${all_arg_arr[@]:2}"
            ;;
            
        *)
            description="${all_arg_arr[1]}"
            op="${all_arg_arr[2]}"
            choicelist+=( "${all_arg_arr[*]:3}" )
            param.__parse.add_help_doc_item "$varname" "$description" "$op" "$default" "${all_arg_arr[@]:3}"
            ;;
        esac

        deslist+=("$description")
        oplist+=( "$op" )
    done

    # Step 1b: Check --help or -h
    for i in $#; do
        if [ "$i" = "-h" ] || [ "$i" = "--help" ]; then
            param.help.show
            return 2
        fi
    done

    # Step 1c: Setupt _varlist
    IFS=$'\n'
    echo "local _varlist 2>/dev/null"
    echo "_varlist=$(list.repr "${varlist[@]}")"

    # Step 2: Init the valus with the enviroment
    for (( i=0; i < ${#varlist[@]}; ++i )); do
        local name=${varlist[i]}
        if [[ "${typelist[i]}" = *env ]]; then
            :
        elif [[ "${typelist[i]}" = *ENV ]]; then
            name="$(echo "$name" | tr '[:lower:]' '[:upper:]')"
        else
            continue
        fi

        local value="${!name}"
        [ -n "$value" ] && vallist[i]=$value
    done

    local rest_argv_str="local _rest_argv=( "
    local rest_argv=()

    # Step 3: Init the values with the parameter
    while [ ! "$#" -eq 0 ]; do
        local parameter_name=$1
        if [ "$parameter_name" = --help ] || [ "$parameter_name" = -h ]; then
            param.help.show
            return 1
        fi

        if [[ ! "$parameter_name" == --* ]]; then
            rest_argv_str+="$(str.repr "$parameter_name") "
            rest_argv+=("$parameter_name")
            shift
            continue
        fi

        parameter_name=${parameter_name:2}
        shift
        local sw=0 i
        for i in "${!varlist[@]}"; do
            [[ ! "${typelist[i]}" = arg* ]] && continue
            local _varname=${varlist[i]}
            if [ "$parameter_name" == "$_varname" ]; then
                vallist[i]=$1
                shift
                sw=1
                break
            fi
        done
        if [ $sw -eq 0 ]; then
            echo "ERROR: Unsupported parameter: --$parameter_name" >&2
            param.help.show
            return 0
        fi
            
    done

    echo "$rest_argv_str ) 2>/dev/null"

    # Step 4: If value is NULL, use the default value. Then, Type-CHECK
    for i in "${!varlist[@]}"; do
        # For some starnge case, it might not be redundant.
        # if [ "${vallist[i]}" == "" ]; then
        #     vallist[i]=${deflist[i]}
        # fi

        # shellcheck disable=SC2206
        local choices=( ${choicelist[i]} )  # should not quote '$(...)'

        param._type.check "${varlist[i]}" "${vallist[i]}" "${oplist[$i]}" "${choices[@]}"
        [ $? -eq 1 ] && {
            param.help.show
            return 1
        }
    done

    # Step 5: Handle the parameter number
    local max_i=-1
    for i in "${!arg_deslist[@]}"; do
        [ $max_i -lt "$i" ] && max_i=$i

        # shellcheck disable=SC2206
        local choices=( ${arg_choicelist[i]} )  # should not quote '$(...)'
        param._type.check "\\\$$i" "${rest_argv[i]}" "${arg_oplist[i]}" "${choices[@]}"
        [ $? -eq 1 ] && return 1
    done

    # Step 6: Handle the rest parameter
    if [ -n "$rest_argv_op" ]; then
        for i in "${!rest_argv[@]}"; do
            [ "$i" -le "$max_i" ] && continue
            
            param._type.check "\\\$$((i+1))" "${rest_argv[i]}" "$rest_argv_op" "${rest_argv_choices[@]}"
            [ $? -eq 1 ] && return 1
        done
    fi

    echo funcname="${funcname}"
    echo "_param_help_docs=$(list.repr "${_param_help_docs[@]}")"
}

shopt -s expand_aliases

param.help(){
    echo
    echo "----------------"
    local i funcname="${1#*/}"
    shift
    printf "%s:\n" "${funcname}" # "${FUNCNAME[0]}"
    while [ $# -gt 0 ]; do
        # echo "fff"
        param.help.item "$1" "$2" "$3" "$4"
        shift 1; shift 1; shift 1; shift 1; # Not equal shift 4
    done
}

param.help.item(){
    local varname="$1"
    local default="$2"
    local typedef="$3"
    local descrip="$4"

    local max_width
    max_width="$(tput cols)"
    (( max_width > 80 )) && (( max_width = 80 ))
    (( max_width -= 20 ))

    local space30 diffspace
    space30="$(printf "%${max_width}s" "")"

    local a b
    if [[ "$varname" =~ [0-9]+ ]]; then
        varname="\$$varname"
    elif [ "$varname" != "..." ]; then
        varname="--$varname"
    fi
    a="$(printf "    %-10s %-10s <%s>" "${varname}" "${default}" "${typedef}")"
    b="$(printf "    $(tput bold; tput setaf 6)%-10s$(tput init) %-10s <$(tput setaf 3)%s$(tput init)>" "${varname}" "${default}" "${typedef}")"
    
    descrip="$(tput bold; tput setaf 1)$descrip$(tput init)"

    if [ "$max_width" -le "${#a}" ]; then
        printf "%s\n$space30%s"  "$b" "$descrip"
    else
        local diff=$(( max_width - ${#a} ))
        diffspace="$( printf "%${diff}s" " " )"
        # printf "%s${diffspace}%s" "$b" "$descrip"
        printf "%s${diffspace}%s" "$b" "$descrip"
    fi
    printf "\n"
}

alias param.example='local _param_example 2>/dev/null; param.__example _param_example'

param.example.show(){
    # shellcheck disable=SC2154
    echo "$_param_example"
}

param.__example(){
    local name=$1 s
    shift
    # shellcheck disable=SC2034
    s="$(param.__example.cat "$@")"
    eval "$name=\"\$s\""
}

param.__example.cat(){
    local i
    echo "----------------"
    printf "Example:\n"
    for (( i=1; i<${#@}; i++ )); do
        printf "  $(tput setaf 6)%s:$(tput init)\n" "* ${!i}"
        (( i++ ))
        printf "    > $(tput setaf 2)%s$(tput init)\n" "${!i}"
    done
}
