record_help() {
  HELP_STRING="usage: task record (start|stop|restart|trash|help)

  This task is designed to create other tasks by recording your bash history

  To start a recording run:

        task record start [--name <task_name>]

  To stop a recording and write it as a task to the local tasks.sh file run:

        task record stop [--name <task_name>]

  To throw away the current recording or old recordings run:

         task record trash [--force]

  To start a new recording after you have started recording run:

         task record restart

  To view this help run

         task record (start|stop|restart|trash) --help
                    or
         task record help"

  echo "$HELP_STRING"
}

arguments_record() {
  SUBCOMMANDS='start|stop|restart|trash|help'
  START_OPTIONS='name:n:str sub:s:str'
  STOP_OPTIONS='name:n:str sub:s:str'
  TRASH_OPTIONS='force:f:bool'
}

record_start(){
  NAME=${ARG_NAME,,}
  if [[ -z "$NAME" ]] || [[ $NAME == "1" ]]
  then
     NAME="unnamed"
  fi
  echo "Starting record..."
  # setup recording file to save context
  persist_var RECORDING_FILE "$TASKS_DIR/.rec_$NAME"
  # save starting directory
  persist_var RECORD_START "$RUNNING_DIR"
  # save name
  persist_var RECORD_NAME "$NAME"
  # save current tasks file
  persist_var RECORD_TASKS_FILE "$TASKS_FILE"
  # save if the sub was given
  if [[ ! -z "$ARG_SUB" ]]
  then
    persist_var "ARG_SUB" "$ARG_SUB"
  fi
  # Save prompt command and change it to save commands
  hold_var PROMPT_COMMAND "echo \\\$( history 1 | tr -s \\\" \\\" | cut -f 3- -d \\\" \\\") >> $RECORDING_FILE ;"
}

record_stop(){
  NAME=${ARG_NAME,,}
  if [[ -z "$NAME" ]] || [[ $NAME == "1" ]]
  then
     NAME="unnamed"
  fi
  if [[ ! -z "$RECORDING_FILE" ]]
  then
    #Check to see if the user gave a name on record stop
    #user gives name on start: $RECORD_NAME is set but $NAME is unnamed
    if [[ "$NAME" == "unnamed" ]] && [[ ! -z "$RECORD_NAME" ]]
    then
      NAME=$RECORD_NAME
      mv $RECORDING_FILE $TASKS_DIR/.rec_$NAME
      RECORDING_FILE=$TASKS_DIR/.rec_$NAME
    fi

    # Change prompt back what it was before recording
    release_var PROMPT_COMMAND
    echo "Stopped Recording..."

    # Test to see if task is already defined
    type "task_$NAME" &> /dev/null
    if [[ "$?" == "1" ]] || [[ ! -z "$ARG_SUB" ]]
    then
      # Write it to file
      echo "Writing record to $RECORD_TASKS_FILE : "
      if [[ -z "$ARG_SUB" ]]
      then
      tee -a $RECORD_TASKS_FILE << EOM
# Recorded Task
task_$NAME() {
    pushd \`pwd\` > /dev/null
    cd $RECORD_START
`tail -n +2 $RECORDING_FILE | sed 's/^/    /'`
    popd > /dev/null
}
EOM
      else
        # Extract text from the definition
        local before_text=$(awk "/^task_$NAME.*/ {f=1} f==0" $TASKS_FILE)
        local task_text=$(awk "/^task_$NAME.*/ {f=1} /^}$/ {f=0;next} f" $TASKS_FILE)
        local after_text=$(awk "/^task_$NAME.*/ {f=1} /^}$/ {s=f} f&&s" $TASKS_FILE)

        # Generate boilerplate
        local insert_text="
  #Recorded subcommand
  if [[ \$TASK_SUBCOMMAND == \"$ARG_SUB\" ]]
  then
`tail -n +2 $RECORDING_FILE | sed 's/^/    /'`
  fi"
        echo "Backing up tasks file to $TASK_MASTER_HOME/backup/"
        cp $TASKS_FILE $TASK_MASTER_HOME/backup/tasks.bk

        # Always need to have the before text
        echo "$before_text" > $TASKS_FILE

        # If there is no task_text, create a body
        if [[ -z "$task_text" ]] 
        then
        tee -a $RECORD_TASKS_FILE << EOM
# Recorded Task
task_$NAME() {
EOM
        echo "$insert_text" >> $TASKS_FILE
        echo "}" >> $TASKS_FILE
        echo "$after_text" >> $TASKS_FILE
        else
          # if there is a prexisting task place it after the other stuffs
          echo "$task_text" >> $TASKS_FILE
          echo "$insert_text" >> $TASKS_FILE
          echo "$after_text" >> $TASKS_FILE
        fi
      fi
      # cleanup
      rm $RECORDING_FILE
      clean_up_state
    else
      echo "Wont write to file: task_$NAME already exists"
      echo "Try supplying another name using 'task record stop --name something_else'"
    fi
  else
    echo "You are not recording..."
    echo "Run 'task record start' to start "
  fi
}

record_trash(){
    if [[ ! -z "$RECORDING_FILE" ]]
    then
      #remove_state first
      clean_up_state 
      #then Change prompt back what it was before recording
      release_var PROMPT_COMMAND
      # Remove recording file
      echo "Trashing record file $RECORDING_FILE"
      # Remove recording file
      rm $RECORDING_FILE
    else
      if [[ ! -z "$ARG_FORCE" ]]
      then
        echo "Forcing removal of all .rec files in $TASKS_DIR"
        rm -i $TASKS_DIR/.rec_*
      else
        echo "You are not recording..."
        echo "Run 'task record trash --force' to remove all .rec_* files in $TASKS_DIR "
      fi
    fi
}

record_restart(){
    if [[ ! -z "$RECORDING_FILE" ]]
    then
      # Reset recording file
      echo "Resetting record file..."
      rm $RECORDING_FILE
      echo "Moving back to the start directory..."
      set_return_directory $RECORD_START
    else
      echo "You are not recording..."
      echo "Run 'task record start' to start "
    fi
}
