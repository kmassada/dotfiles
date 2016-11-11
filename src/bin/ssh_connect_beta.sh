#!/bin/bash
# set -x #debug

cd "$(dirname "${BASH_SOURCE}")" && source "utils.sh"

#Global variables & functions
function nullify() {
  "$@" >/dev/null 2>&1
}

#=================================#
#            Help Menu            #
#=================================#

print_help() {

	print_info "
	There are only 2 ways to run this script
	-> ssh_connect.sh <USER>@<SERVER>:<PORT> <Name> 
		USER= username
		SERVER= server ip, or name
		PORT= default is 22 (optional)
		NAME= your name for server (optional)

	-> ssh_connect.sh -h 
		<- displays help

	-> There's a major limitation, script only checks 
	   for duplicate names, NOT IP
	" >&2

	exit -1
}

#====================================#
#            Help Display            #
#====================================#

while getopts ":h" opt; do
case $opt in
h)
	print_help
	;;

\?)
	print_error "Invalid option: -$OPTARG" >&2
	print_help
	;;
esac
done

#========================================#
#            Param Validation            #
#========================================#

if [ $# -ne 2 ]; then
    print_error "Illegal number of parameters"
    print_help
fi

#input
RESULTS=(`echo $1 | awk -F"[@: ]" '{print $1" "$2" "$3}'`)
USER="${RESULTS[0]}"
SERVER="${RESULTS[1]}"
PORT="${RESULTS[2]}"
[ ! -z $PORT ] || PORT="22";
echo $USER'@'$SERVER':'$PORT' '$NAME

NAME=$2;

#============================================#
#            Checks And Confirms             #
#============================================#

check_client() {
	##install client 
	if nullify uname -a | grep -i ubuntu ; then
		#dpkg-query -l openssh-client
		if ! nullify dpkg --get-selections | grep openssh-client ; then 
			print_info "installing packages"
			sudo apt-get install -qy openssh-client ;
		fi
	fi

	if [ -f /etc/redhat-release ] ; then
		if ! nullify rpm -q openssh-clients ; then 
			print_info "installing packages"
			sudo yum install -y openssh-clients;
		fi
	fi 

	if [ $(uname -s) == "Darwin" ]; then
		if ! nullify cmd_exists "ssh-copy-id" ; then
			# Homebrew
		    if [ $(cmd_exists "brew") -eq 1 ]; then
		        printf "\n" | ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
		        #  └─ simulate the ENTER keypress
		        print_result $? "brew"
		    fi

		    if [ $(cmd_exists "brew") -eq 0 ]; then

		        execute "brew update" "brew (update)"
		        execute "brew upgrade" "brew (upgrade)"
		        execute "brew cleanup" "brew (cleanup)"
		        printf "\n"

		        brew_install "ssh-copy-id"
		        printf "\n"
		    fi
		fi
	fi
}

check_config() {
	#check for already present file 
	if grep -A 4 $NAME ~/.ssh/config || grep  $USER@$SERVER ~/.ssh/config; then
		print_info "$NAME or $USER@$SERVER seems to exist in the config file"
		if ssh -o BatchMode=yes $NAME echo 'OK' ; then 
			print_info "key exist and config already written"
			print_info "will exit"
			sleep 5
			exit -1;
		elif ssh -o BatchMode=yes $USER@$SERVER echo 'OK' ; then 
			print_info "key exist and config already written"
			print_info "will exit"
			sleep 5
			exit -1;
		elif ! grep  $USER@$SERVER ~/.ssh/config; then
			print_error "$NAME was not found but $USER@$SERVER in config, this shouldn't occur, check values"
			print_error "will exit"
			exit -1;
		elif [ -f $USER@$SERVER ] ; then 
			print_error "$NAME and $USER@$SERVER are matching in config but connection fails"
			print_error "check connection to server, or key on server "
			print_erro "will exit"
			exit -1;
		fi
	fi
}

check_host() {
	#check for valid connection
	#status=$(ssh -o BatchMode=yes -o ConnectTimeout=5 192.168.3.1 echo ok 2>&1)
	#if ssh -q -o “BatchMode=yes” user@host “echo 2>&1″ && echo “Up” || echo “Down”
	#ssh-keyscan
	HOST_STATUS="$(ssh -p $PORT -o BatchMode=yes -o ConnectTimeout=10 $USER@$SERVER echo OK 2>&1)"
	if echo "${HOST_STATUS}" | grep -ie 'No route\|Not found\|not known' >/dev/null 2>&1; then
		print_error "The Host you trying to reach is not up. Test connection then re-run script";
		exit -1;
	fi

	if ! nullify ping -c 3 $SERVER ; then
		print_error "host not found"
		exit -1;
	fi
}

function import_key {
#if trusted directory doesn't exist, create it
print_info "creating directory for trusted ssh"
TRUSTED="$HOME/.ssh/trusted"
if [ ! -d $TRUSTED ] ; then 
	mkdir -p $TRUSTED;
fi
cd $TRUSTED;
print_success "$TRUSTED"

#$1 is the validname passed as a param	
VALIDNAME=$1;
if [ $USER == "root" ] ; then 
	ssh-keygen -t rsa -f $USER@$SERVER -b 4096 ;
else
	ssh-keygen -t rsa -f $USER@$SERVER -b 4096 -P '' ;
fi


print_success "key for $VALIDNAME was created";

#make node trusted
#touch ~/.ssh/known_hosts 2>&1 >/dev/null ;
nullify ssh-keygen -R $SERVER ; 
ssh-keyscan -p $PORT -H $SERVER >> ~/.ssh/known_hosts;

#copy over key
if ssh-copy-id -p $PORT -i $TRUSTED/$USER@$SERVER.pub $USER@$SERVER; then
print_success "key for $USER@$VALIDNAME was copied";

#write config file
#touch  ~/.ssh/config 2>&1 >/dev/null ;
echo -e '' >> ~/.ssh/config
cat >> ~/.ssh/config << EOF
Host $VALIDNAME
HostName $SERVER
User $USER
IdentityFile $TRUSTED/$USER@$SERVER
EOF
if [ "$PORT" != "22" ]
	then echo 'Port' $PORT >> ~/.ssh/config
fi
print_success "config file was written"

else 
	print_error "Key has been created, but could not be copied to server"

	ask_for_confirmation "Do you want to delete the created keys $USER@$SERVER.pub $USER@$SERVER?"
    if answer_is_yes; then
    	rm -i $USER@$SERVER.pub $USER@$SERVER
    	exit -1;
    fi
fi
}

check_host
check_client
check_config

import_key $NAME


if ssh $NAME echo 'OK' ; then
	print_success "Task completed"
	ask_for_confirmation "Do you want to delete the PUB key $USER@$SERVER.pub?"
    if answer_is_yes; then
    	rm -i $USER@$SERVER.pub
    fi
fi