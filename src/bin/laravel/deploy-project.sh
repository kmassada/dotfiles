#!/bin/bash

#=================================#
#            Help Menu            #
#=================================#

print_help() {

	print "
	-> mygitscript.sh <USER>@<GITSERVER> <RepoName> 
		USER= username
		GITSERVER= server ip, or name
		REPONAME= your name of the repo

	-> mygitscript.sh -h 
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
print_error() {
    printf "[✖] $1"
    printf "\n"
}

ask_for_confirmation() {
    print_question "$1 (y/n) "
    read -n 1
    printf "\n"
}

#==============================#
#            Modules           #
#==============================#

detect_env() {
    ENV_DETECT=$1
    cd $ENV_DETECT;
    print_result $? "cd $ENV_DETECT"

    if [ -f app/config/database.php ] || [ -f htdocs/app/config/database.php ]; then
        WEB_ENV='laravel';
    fi

    if [ -f htdocs/sites/default/settings.php ]; then
        WEB_ENV='drupal';
    fi
    if [ -d htdocs/wp-content ]; then
        WEB_ENV='wordpress';
    fi

    if [ ! -z $WEB_ENV ]; then
        ask_for_confirmation "Project is not DRUPAL nor LARAVEL nor WORDPRESS want to continue?"
        if ! answer_is_yes; then
            print_message "exiting gracefully" 
            exit 0;
        fi
    fi
}

get_input() {
    ask "Please enter project name [example:werf]: "
    PROJECT_NAME=$REPLY;

    ask "Please enter full path to your project directory [example:/home/sites/laravel4]: "
    PROJECT_ROOT=$REPLY;

    while [[ ! -f $PROJECT_TAR ]]
    do
        ask "Please enter full path to your project tar [example:/home/sites/laravel4.tar]: "
        PROJECT_TAR=$REPLY;
    done

    ask_for_confirmation "Does project has a database requirement? "
    if answer_is_yes; then
    while [[ ! -f $PROJECT_SQL ]]
        do
            ask "Please enter full path to your project tar [example:/home/sites/laravel4.sql]: "
            PROJECT_SQL=$REPLY;
        done

        ask "Please enter deploy database [example:cgdevel_werf]: "
        PROJECT_DB=$REPLY;
        ask "Please enter deploy database user [example:cgdevel_werf]: "
        PROJECT_DBUSER=$REPLY

        if ! nullify mysql -u $PROJECT_DBUSER -p $PROJECT_DB -e "show tables;"; then 
            print_error "Database has not been setup. Please do so before running this script"
            exit 1;
        fi
    fi

}

htdocs_ext() {
    # if [[ -d $PROJECT_ROOT/htdocs ]]; then
    #     print_error "project exists"
    #     ask_for_confirmation "do you want to overwrite current directory? "

    #     if ! answer_is_yes; then
    #         print_message "exiting gracefully" 
    #         exit 0;
    #     fi
    # fi  

    if ! mkdir -p ~/TMP_DEPLOY/$PROJECT_NAME ; then
        print_error "unable to create directory ~/TMP_DEPLOY/$PROJECT_NAME"
        print_message "exiting gracefully" 
        exit 0;
    fi

    mv $PROJECT_TAR $PROJECT_SQL ~/TMP_DEPLOY/$PROJECT_NAME
    cd ~/TMP_DEPLOY/$PROJECT_NAME

    tar -xzf $PROJECT_TAR -C .
    
}

drupal_db_ext(){
    cd ~/TMP_DEPLOY/$PROJECT_NAME

    vi htdocs/sites/default/settings.php

    if [ $(cmd_exists "drush") -eq 0 ];then
        cd htdocs;
        drush sql-cli < ../$PROJECT_SQL;
        print_result $? "drush sql-cli > ../$PROJECT_SQL"
        cd -;
    fi
}

laravel_db_ext(){
    print_message "Program will attempt to import databse"
    if mysqldump --user $PROJECT_DBUSER $PROJECT_DB < ~/$PROJECT_NAME-`date +%m%d%Y`.sql; then 
        print_result $? "Database: $PROJECT_DB export successful"
    else
        print_error "cannot save laravel database try to do it yourself"
    fi

    cd ~/TMP_DEPLOY/$PROJECT_NAME

    print_message "edit config file"

    vi app/config/database.php

    cd-
}

#==============================#
#            Execute           #
#==============================#

print_message "Porgram will now ask user for project variables"
get_input;

print_message "Program will now try to extract htdocs"
ask_for_confirmation "Do you want to extract archive using sudo? CPanel boxes do not run sudo "
if answer_is_yes; then
    export -f htdocs_ext
    ask_for_sudo
    su -c 'htdocs_ext'
    htdocs_ext   
else
    htdocs_ext  
fi

print_message "Porgram will now detect what environment drupal/laravel"
detect_env ~/TMP_DEPLOY/$PROJECT_NAME

if [ "$WEB_ENV" = "drupal" ]; then 
    print_message "working in DRUPAL" 
    drupal_db_ext;
fi

if [ "$WEB_ENV" = "laravel" ]; then 
    print_message "working in LARAVEL" 
    laravel_db_ext;
fi

print_message "extracted files can now be found here... "
ls -l ~/TMP_DEPLOY/$PROJECT_NAME

print_message "end of program"
