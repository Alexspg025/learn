#! /bin/bash
#
# run-all.sh
#
# Run a fully-automated word-pair counting pipeline. This will run the
# conventional tmux/byobu panel, but will fully automate. This allows
# progress monitoring.
#
# Use F3 and F4 to switch to the other terminals.
#
# ----------------------

# Work around an lxc-attach bug.
if [[ `tty` == "not a tty" ]]
then
	script -c $0 /dev/null
	exit 0
fi

# Load master config parameters
if [ -z $MASTER_CONFIG_FILE ]; then
	echo "MASTER_CONFIG_FILE not defined!"
	exit -1
fi

if [ -r $MASTER_CONFIG_FILE ]; then
	source $MASTER_CONFIG_FILE
else
	echo "Cannot find master configuration file!"
	exit -1
fi

# ----------------------
# Pair-counting config
if ! [ -z ${PAIR_CONF_FILE} ] && [ -r ${PAIR_CONF_FILE} ]; then
	source ${PAIR_CONF_FILE}
else
	echo "Cannot find pair-counting configuration file!"
	exit -1
fi

# ==================================
# Use byobu so that the scroll bars actually work
byobu new-session -d -n 'cntl' 'top; $SHELL'

byobu new-window -n 'cogsrv' 'nice guile -l ${COMMON_DIR}/cogserver.scm ; $SHELL'

# Wait for the cogserver to initialize.
sleep 5
echo -e "(block-until-idle 0.01)\n.\n." | nc $HOSTNAME $PORT >> /dev/null

# Telnet window
tmux new-window -n 'telnet' 'rlwrap telnet $HOSTNAME $PORT; $SHELL'

# Batch-process the corpus.
tmux new-window -n 'submit' 'sleep 1; ./pair-submit.sh; $SHELL'

# Spare
tmux new-window -n 'spare' 'echo -e "\nSpare-use shell.\n"; $SHELL'

# Fix the annoying byobu display
echo "tmux_left=\"session\"" > $HOME/.byobu/status
echo "tmux_right=\"load_average disk_io date time\"" >> $HOME/.byobu/status
tmux attach

## Shut down the server.
#echo Done pair counting
#echo "(exit-server)" | nc $HOSTNAME $PORT >> /dev/null
#
## Wait for the shutdown to complete.
#sleep 1
#
## Compute the pair marginals.
#echo "Start computing the pair marginals"
#guile -s ${COMMON_DIR}/marginals-pair.scm
#echo "Finish computing the pair marginals"
#echo -e "\n\n\n"
#
#echo Done processing word-pairs
## ------------------------
#
