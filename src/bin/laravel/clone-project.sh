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
    cd $PROJECT_ROOT;
    print_result $? "cd $PROJECT_ROOT"

    if [ -f app/config/database.php ] || [ -f htdocs/app/config/database.php ]; then
        WEB_ENV='laravel';
    fi

    if [ -f htdocs/sites/default/settings.php ]; then
        WEB_ENV='drupal';
    fi

    if [ -d htdocs/wp-content ]; then
        WEB_ENV='wordpress';
    fi

    if [ -z $WEB_ENV ]; then
        ask_for_confirmation "Project is not DRUPAL nor LARAVEL nor WORDPRESS want to continue?"
        if ! answer_is_yes; then
            print_message "exiting gracefully" 
            exit 0;
        fi
        WEB_ENV="other";
    fi
}

get_input() {
    ask "Please enter project name [example:werf]: "
    PROJECT_NAME=$REPLY;

    while [[ ! -d $PROJECT_ROOT ]]
    do
        ask "Please enter full path to your project directory [example:/home/sites/laravel4]: "
        PROJECT_ROOT=$REPLY;
    done
}

drupal_tar(){
    if [ $(cmd_exists "drush") -eq 0 ];then
        cd htdocs;
        drush sql-dump > ~/$PROJECT_NAME-`date +%m%d%Y`.sql;
        print_result $? "drush sql-dump > ~/$PROJECT_NAME-`date +%m%d%Y`.sql"
        cd -;
    fi
    print_message "will try to tar up $PROJECT_ROOT" 

    if [[ -d $PROJECT_ROOT/scripts ]]; then
        PROJECT_SCRIPTS="scripts"
    fi

    ask_for_confirmation "Do you want to make archive using sudo? CPanel boxes do not run sudo "
    if answer_is_yes; then
        ask_for_sudo
        sudo tar czf  ~/$PROJECT_NAME-`date +%m%d%Y`.tar.gz --totals htdocs $PROJECT_SCRIPTS
    else
        tar czf  ~/$PROJECT_NAME-`date +%m%d%Y`.tar.gz --totals htdocs $PROJECT_SCRIPTS 
    fi
}

laravel_tar(){
    print_message "attempting to retrieve laravel passwords"
    PROJECT_DATABASE=$(grep -A10 "'mysql' => array" app/config/database.php | grep 'database' | awk -F[\'] '{print $4}')
    PROJECT_USERNAME=$(grep -A10 "'mysql' => array" app/config/database.php | grep 'username' | awk -F[\'] '{print $4}')
    PROJECT_PASSWORD=$(grep -A10 "'mysql' => array" app/config/database.php | grep 'password' | awk -F[\'] '{print $4}')

    if mysqldump --user $PROJECT_USERNAME --password=$PROJECT_PASSWORD $PROJECT_DATABASE > ~/$PROJECT_NAME-`date +%m%d%Y`.sql; then 
        print_result $? "Database: $PROJECT_DATABASE export successful"
    else
        print_error "cannot save laravel database try to do it yourself"
    fi

    print_message "will try to tar up $PROJECT_ROOT"

    ask_for_confirmation "Do you want to make archive using sudo? CPanel boxes do not run sudo "
    if answer_is_yes; then
        ask_for_sudo
        sudo tar czf  ~/$PROJECT_NAME-`date +%m%d%Y`.tar.gz --totals  .
    else
        tar czf  ~/$PROJECT_NAME-`date +%m%d%Y`.tar.gz --totals .
    fi
}

wordpress_tar(){
    print_message "attempting to retrieve wordpress passwords"
    PROJECT_DATABASE=$(grep 'DB_NAME' htdocs/wp-config.php | awk -F[\'] '{ print $4 }')
    PROJECT_USERNAME=$(grep 'DB_USER' htdocs/wp-config.php | awk -F[\'] '{ print $4 }')
    PROJECT_PASSWORD=$(grep 'DB_PASSWORD' htdocs/wp-config.php | awk -F[\'] '{ print $4 }')

    if mysqldump --user $PROJECT_USERNAME --password=$PROJECT_PASSWORD $PROJECT_DATABASE > ~/$PROJECT_NAME-`date +%m%d%Y`.sql; then 
        print_result $? "Database: $PROJECT_DATABASE export successful"
    else
        print_error "cannot save drupal database try to do it yourself"
    fi

    print_message "will try to tar up $PROJECT_ROOT"

    ask_for_confirmation "Do you want to make archive using sudo? CPanel boxes do not run sudo "
    if answer_is_yes; then
        ask_for_sudo
        sudo tar czf  ~/$PROJECT_NAME-`date +%m%d%Y`.tar.gz --totals  .
    else
        tar czf  ~/$PROJECT_NAME-`date +%m%d%Y`.tar.gz --totals .
    fi
}

other_tar(){
    
    print_message "will try to tar up $PROJECT_ROOT"

    ask_for_confirmation "Do you want to make archive using sudo? CPanel boxes do not run sudo "
    if answer_is_yes; then
        ask_for_sudo
        sudo tar czf  ~/$PROJECT_NAME-`date +%m%d%Y`.tar.gz --totals  .
    else
        tar czf  ~/$PROJECT_NAME-`date +%m%d%Y`.tar.gz --totals .
    fi
}

#==============================#
#            Execute           #
#==============================#

print_message "Porgram will now ask user for project variables"
get_input;

print_message "Porgram will now detect what environment drupal/laravel"
detect_env;

if [ "$WEB_ENV" = "drupal" ]; then 
    print_message "working in DRUPAL" 
    drupal_tar;
fi

if [ "$WEB_ENV" = "laravel" ]; then 
    print_message "working in LARAVEL" 
    laravel_tar;
fi

if [ "$WEB_ENV" = "wordpress" ]; then 
    print_message "working in WORDPRESS" 
    wordpress_tar;
fi

if [ "$WEB_ENV" = "other" ]; then 
    print_message "working fils only" 
    other_tar;
fi

print_message "tar files can now be found here... "
ls -l ~/$PROJECT_NAME-`date +%m%d%Y`*

print_message "end of program" 

