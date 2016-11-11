#!/bin/bash

#=================================#
#            Help Menu            #
#=================================#

print_help() {
	echo "
	-> create-model.sh <Model> <Models> 
        Model and Models are the singular and plural of your model
		will generate a model and create the following
        ./app/controllers/ModelController.php
        ./app/routes/_routes_model}.php
        ./app/views/model
	-> create-model.sh -h 
		<- displays help
	" >&2

	exit -1
}
#===============================#
#            Helpers            #
#===============================#

ask_for_sudo() {

    # Ask for the administrator password upfront
    sudo -v

    # Update existing `sudo` time stamp until this script has finished
    # https://gist.github.com/cowboy/3118588
    while true; do
        sudo -n true
        sleep 60
        kill -0 "$$" || exit
    done &> /dev/null &

}

nullify() {
	#Global variables & functions
	"$@" >/dev/null 2>&1
}


cmd_exists() {
    [ -x "$(command -v "$1")" ] \
        && printf 0 \
        || printf 1
}

answer_is_yes() {
    [[ "$REPLY" =~ ^[Yy]$ ]] \
        && return 0 \
        || return 1
}

print_result() {
    [ $1 -eq 0 ] \
        && printf "[✔] $2" \
        || printf "[✖] $2"
    printf "\n"

    [ "$3" == "true" ] && [ $1 -ne 0 ] \
        && exit
}

print_question() {
    printf "[?] $1"
}

answer_is_yes() {
    [[ "$REPLY" =~ ^[Yy]$ ]] \
        && return 0 \
        || return 1
}

ask() {
    printf "[?] $1"
    read
}

print_message() {
    printf "[!] $1"
    printf "\n"
}

ask_for_confirmation() {
    print_question "$1 (y/n) "
    read -n 1
    printf "\n"
}

#==============================#
#            Function          #
#==============================#

#input
verify_entry() { 
    MODEL_LOW=(`echo $1 | tr '[:upper:]' '[:lower:]'`)
    MODEL_SIN=(`echo $1 | tr '[:upper:]' '[:lower:]' | sed -e 's/\b\(.\)/\u\1/g'`)
    MODEL_PLU=(`echo $2 | tr '[:upper:]' '[:lower:]'`)

    print_message "You have entered < $MODEL_LOW > should be all lowercase < template >
    You have entered < $MODEL_SIN > should have first letter capitalized < Template > 
    You have entered < $MODEL_PLU > should have first letter capitalized and be plural < templates>
    " 

    ask_for_confirmation "Do you want to continue, if does not match template, please select no?"
    if ! answer_is_yes; then
        print_message "exiting gracefully" 
        print_help
        exit 0;
    fi

    if [ ! -d app ]; then 
        print_message "script is not in the right folder. must be run inside [PROJECT]/" 
        print_help
        exit 0;
    fi
}

#==============================#
#            Program           #
#==============================#

#display help
while getopts ":h" opt; do
case $opt in
h)
    print_help
    ;;
v)
    verify_entry $@
    ;;
\?)
    echo -e "Invalid option: -$OPTARG" >&2
    print_help
    ;;
esac
done

if [ $# -ne 2 ]; then
    echo -e "Illegal number of parameters"
    print_help
fi

verify_entry $@

print_message "creating ./app/controllers/${MODEL_SIN}Controller.php"
cp  ./app/controllers/TemplateController.php ./app/controllers/${MODEL_SIN}Controller.php
sed  -i "s/Template/$MODEL_SIN/g;s/template/$MODEL_LOW/g;s/templates/$MODEL_PLU/g" ./app/controllers/${MODEL_SIN}Controller.php 

print_message "creating ./app/routes/_routes_${MODEL_LOW}.php"
cp  ./app/routes/_routes_template.php  ./app/routes/_routes_${MODEL_LOW}.php
sed  -i "s/Template/$MODEL_SIN/g;s/template/$MODEL_LOW/g;s/templates/$MODEL_PLU/g" ./app/routes/_routes_${MODEL_LOW}.php

print_message "creating ./app/views/$MODEL_LOW"
cp -r ./app/views/modeltemplate ./app/views/$MODEL_LOW 
sed  -i "s/Template/$MODEL_SIN/g;s/template/$MODEL_LOW/g" ./app/views/$MODEL_LOW/*.php

print_message "creating ./app/models/$MODEL_SIN".php
cp -r ./app/models/Template.php ./app/models/$MODEL_SIN.php 
sed  -i "s/Template/$MODEL_SIN/g;s/template/$MODEL_LOW/g;s/templates/$MODEL_PLU/g" ./app/models/$MODEL_SIN.php