#!/bin/bash

cd "$(dirname "${BASH_SOURCE}")" && source "utils.sh"

ask "Please enter site you are trying to connect to [example:bitbucket.org]: "

SITE=$REPLY;
mkdir -p ~/.ssh/;
chmod 700 ~/.ssh/;
cd ~/.ssh/;

ssh-keygen -t rsa -f `whoami`@$SITE -b 4096 -P '';

cat >>  config << EOF

Host ${STIE}
HostName ${SITE}
IdentityFile ~/.ssh/`whoami`@${SITE}
EOF

chmod 600 config;

cd -
cat ~/.ssh/`whoami`@${SITE}.pub
