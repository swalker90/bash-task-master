parse_args_for_task() {
  _tmverbose_echo "Parsing arguments: $@"
  if [[ -z "$ARG_FORMAT" ]] || [[ "$ARG_FORMAT" == "bash" ]]
  then
    bash_parse "$@"
    _tmverbose_echo "Parsed arguments as bash"
  elif [[ "$ARG_FORMAT" == "yaml" ]]
  then
    _tmverbose_echo "Parsing arguments as yaml"
    if [[ -f "$TASKS_DIR/$ARGUMENTS" ]]
    then
      cp $TASKS_DIR/$ARGUMENTS $STATE_DIR/args.yaml
      _tmverbose_echo "ARGUMENTS variable is a path ($TASKS_DIR/$ARGUMENTS), copied to $STATE_DIR/args.yaml"
    elif [[ -f "$ARGUMENTS" ]]
    then
      cp $ARGUMENTS $STATE_DIR/args.yaml
      _tmverbose_echo "ARGUMENTS variable is a path ($ARGUMENTS), copied to $STATE_DIR/args.yaml"
    else
      echo "$ARGUMENTS" > $STATE_DIR/args.yaml
      _tmverbose_echo "ARGUMENTS variable is a string, Created $STATE_DIR/args.yaml from arguments string"
    fi
    yaml_parse_and_validate "$@"
  else
    echo Could not find desired argument format: $ARG_FORMAT
    exit 1
  fi
}

parse_help() {
  #Load the tasks file now instead of at the begining to be able to use local format
  if [[ "$(type -t task_$TASK_SUBCOMMAND)" != "function" ]]
  then
    . $TASKS_FILE
  fi
  if [[ -z "$ARG_FORMAT" ]] || [[ "$ARG_FORMAT" == "bash" ]]
  then
    bash_help
  elif [[ "$ARG_FORMAT" == "yaml" ]]
  then
    yaml_help $TASK_SUBCOMMAND
  else
    echo Could not find desired argument format: $ARG_FORMAT
    exit 1
  fi
}
  

validate_args_for_task() {
  if [[ -z "$ARG_FORMAT" ]] || [[ "$ARG_FORMAT" == "bash" ]]
  then
    bash_validate "$@"
  elif [[ "$ARG_FORMAT" == "yaml" ]]
  then
    _tmverbose_echo "Skipping yaml validation step (validation should be in yaml wrapper)"
    return
  else
    echo Could not find desired argument format: $ARG_FORMAT
    exit 1
  fi
}

yaml_parse_and_validate() {
  _tmverbose_echo "Parsing and validating with 'yaml_driver.py $STATE_DIR/args.yaml $@'"
  vars="$($TASK_MASTER_HOME/lib/yaml_driver.py $STATE_DIR/args.yaml "$@")"
  if [[ "$?" != 0 ]]
  then
    _tmverbose_echo "yaml parsing and Validation failed"
    exit 1
  fi
  eval "$vars"
}

yaml_help() {
 _tmverbose_echo "Running yaml help: 'yaml_driver $STATE_DIR/args.yaml help $TASK_SUBCOMMAND'"
 $TASK_MASTER_HOME/lib/yaml_driver.py $STATE_DIR/args.yaml help $TASK_SUBCOMMAND
}


bash_validate() {
  # Define available types
  declare -A verif
  local avail_types='str|int|bool|nowhite|upper|lower|single|ip'
  local verif[str]='^.*$'
  local verif[int]='^[0-9]*$'
  local verif[bool]='^1$'
  local verif[nowhite]='^[^[:space:]]+$'
  local verif[upper]='^[A-Z]+$'
  local verif[lower]='^[a-z]+$'
  local verif[single]="^.{1}$"
  local verif[ip]="^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$"
  local SUBCOMMANDS=""

  # Check if argument specifications exist
  type arguments_$TASK_COMMAND &> /dev/null 
  if [[ "$?" == "0" ]]
  then
    arguments_$TASK_COMMAND
    # check if subcommand exists or if there are no subcommands
    if [[ $TASK_SUBCOMMAND =~ ^($SUBCOMMANDS)$ ]] || [[ -z "$SUBCOMMANDS" ]]
    then
      # handle subcommandless tasks
      local sub=${TASK_SUBCOMMAND^^}
      # Check required arguments
      local reqvar_com="${TASK_COMMAND^^}_REQUIREMENTS"
      local reqvar_sub="${sub}_REQUIREMENTS"
      if [[ ! -z "${!reqvar_sub}" ]] || [[ ! -z "${!reqvar_com}" ]]
      then
        for requirement in ${!reqvar_sub} ${!reqvar_com}
        do
          local name=${requirement%%:*}
          local atype=${requirement##*:}
          # Make sure that the argument exists
          local valname="ARG_${name^^}"
          if [[ -z "${!valname}" ]]
          then
            echo "Missing required argument: --${name,,}"
            return 1
          fi
          # Make sure that the argument is the right type
          if [[ ! "${!valname}" =~ ${verif[$atype]} ]]
          then
            echo "--${name,,} argument does not follow verification requirements: $atype:::${verif[$atype]}"
            return 1
          fi
        done
      fi
      # Verify optional requirements
      local optvar="${sub}_OPTIONS"
      if [[ ! -z "${!optvar}" ]]
      then
        for option in ${!optvar}
        do
          local name=${option%%:*}
          name=${name//-/_}
          local atype=${option##*:}
          local valname="ARG_${name^^}"
          if [[ ! -z "${!valname}" ]] && [[ ! "${!valname}" =~ ${verif[$atype]} ]]
          then
            echo "Argument does not follow verification requirements: $name=${!valname} $atype:::${verif[$atype]}"
            return 1
          fi
        done
      fi
    else
      echo "Unknown subcommand: $TASK_SUBCOMMAND"
      echo Available subcommands: $SUBCOMMANDS
      return 1
    fi
  fi
  return 0

}

bash_parse() {
  # All arguments after the command will be parsed into environment variables
  # load argument specification
  type arguments_$TASK_COMMAND &> /dev/null 
  if [[ "$?" == "0" ]]
  then
    arguments_$TASK_COMMAND
  fi
  if [[ -z "$SPEC_REQUIREMENT_NAME" ]]
  then
    local SPEC_REQUIREMENT_NAME=${TASK_COMMAND^^}_REQUIREMENTS
    local SPEC_OPTION_NAME=${TASK_COMMAND^^}_OPTIONS
    local requirements="${!SPEC_REQUIREMENT_NAME} ${!SPEC_OPTION_NAME}"
  fi
  #check if there are more than one specified arg and add the first ones to the end
  unset ADDED_ARGS
  shift
  while [[ $# != "0" ]]
  do
    ARGUMENT="$1"
    if [[ $ARGUMENT =~ ^\-[A-Za-z]{2,}$ ]]
    then
      local separated=$(echo "$ARGUMENT" | awk '{ match($1,"-[A-Za-z]{2,}", a); split(a[0], b, "") ; j="" ; s = " -" ; for(i=2;i in b; i++) { j = j s b[i] ; } print j }')
      # grab the last character as this argument
      ARGUMENT="-${separated:${#separated}-1:1}"
      # add added args
      local ADDED_ARGS="$ADDED_ARGS ${separated%-[[:alpha:]]}"
    fi
    #ignore any whitespace arguments
    if [[ -z "$ARGUMENT" ]]
    then
      shift
      ARGUMENT="$1"
    fi
    #Translate shortend arg
    if [[ "$ARGUMENT" =~ ^-[A-Za-z]$ ]]
    then
      local spec=$(sed "s/[A-Za-z_-]*:[^${ARGUMENT#-}]:[a-z]*//g" <<< "$requirements" |tr -d '[[:space:]]' )
      local long_arg="${spec%%:*}"
      if [[ -z "$long_arg" ]] || [[ ! "$spec" =~ ^[a-z_-]+:[A-Za-z]:[a-z]+$ ]]
      then
        echo "Unrecognized short argument: $ARGUMENT"
        return 1
      fi
      ARGUMENT="--${long_arg,,}"
    fi
    local spec=$(sed "s/.*\(${ARGUMENT#--}:[A-Za-z]:[a-z]*\).*/\1/g" <<< "$requirements" |tr -d '[[:space:]]' )
    if [[ "$ARGUMENT" =~ ^--[a-z_-]+$ ]]
    then
      local TRANSLATE_ARG="${ARGUMENT#--}"
      TRANSLATE_ARG=${TRANSLATE_ARG//-/_}
      if [[ -z "$2" ]] || [[ "$2" =~ ^--[a-z_-]+$ ]] || [[ "$2" =~ ^-[[:alpha:]]$ ]] || [[ "${spec##*:}" == "bool" ]]
      then
        export ARG_${TRANSLATE_ARG^^}="1"
      else
        shift
        export ARG_${TRANSLATE_ARG^^}="$1"
      fi
    elif [[ "$ARGUMENT" =~ ^[a-z0-9_-]*$ ]] && [[ -z "$TASK_SUBCOMMAND" ]]
    then
      TASK_SUBCOMMAND="$ARGUMENT"
      SPEC_REQUIREMENT_NAME=${TASK_SUBCOMMAND^^}_REQUIREMENTS
      SPEC_OPTION_NAME=${TASK_SUBCOMMAND^^}_OPTIONS
      requirements="${requirements} ${!SPEC_REQUIREMENT_NAME} ${!SPEC_OPTION_NAME}"
    else
      echo "Unrecognized argument: $ARGUMENT"
      return 1
    fi
    shift
  done
  if [[ ! -z "$ADDED_ARGS" ]]
  then
    parse_args_for_task "GARBAGE" $ADDED_ARGS
  fi
}

bash_help() {
  if [[ ! -z "$TASK_SUBCOMMAND" ]]
  then
    type arguments_$TASK_SUBCOMMAND &> /dev/null
    if [[ "$?" == "0" ]]
    then 
      echo
      arguments_$TASK_SUBCOMMAND
      reqname=${TASK_SUBCOMMAND^^}_REQUIREMENTS
      optname=${TASK_SUBCOMMAND^^}_OPTIONS
      descname=${TASK_SUBCOMMAND^^}_DESCRIPTION
      if [[ "${SUBCOMMANDS/\|\|/}" != "$SUBCOMMANDS" ]] || [[ ! -z "${!reqname}" ]] || [[ ! -z "${!optname}" ]] || [[ ! -z "${!descname}" ]]
      then
        echo "Command: task $TASK_SUBCOMMAND"
        TASK_SUBCOMMAND=${TASK_SUBCOMMAND//-/_}
        if [[ ! -z "${!descname}" ]]
        then
          echo "  ${!descname}"
        else
          echo "  No description available"
        fi
        if [[ ! -z "${!reqname}" ]]
        then
          echo "  Required:"
          for req in ${!reqname}
          do
            arg_spec=${req%:*}
            echo "    --${arg_spec%:*}, -${arg_spec#*:} ${req##*:}"
          done
        fi
        if [[ ! -z "${!optname}" ]]
        then
          echo "  Optional:"
          for opt in ${!optname}
          do
            arg_spec=${opt%:*}
            if [[ "${opt##*:}" == "bool" ]]
            then
              echo "    --${arg_spec%:*}, -${arg_spec#*:}"
            else
              echo "    --${arg_spec%:*}, -${arg_spec#*:} ${opt##*:}"
            fi
          done
        fi
        echo
      fi
      for sub in ${SUBCOMMANDS//\|/ }
      do 
        echo "Command: task $TASK_SUBCOMMAND $sub"
        sub=${sub//-/_}
        reqname=${sub^^}_REQUIREMENTS
        optname=${sub^^}_OPTIONS
        descname=${sub^^}_DESCRIPTION
        if [[ ! -z "${!descname}" ]]
        then
          echo "  ${!descname}"
        else
          echo "  No description available"
        fi
        if [[ ! -z "${!reqname}" ]]
        then
          echo "  Required:"
          for req in ${!reqname}
          do
            arg_spec=${req%:*}
            echo "    --${arg_spec%:*}, -${arg_spec#*:} ${req##*:}"
          done
        fi
        if [[ ! -z "${!optname}" ]]
        then
          echo "  Optional:"
          for opt in ${!optname}
          do
            arg_spec=${opt%:*}
            if [[ "${opt##*:}" == "bool" ]]
            then
              echo "    --${arg_spec%:*}, -${arg_spec#*:}"
            else
              echo "    --${arg_spec%:*}, -${arg_spec#*:} ${opt##*:}"
            fi
          done
        fi
        echo
      done
      
    else
      echo "No arguments are defined"
    fi
    return 0
  fi
  return 1
}
