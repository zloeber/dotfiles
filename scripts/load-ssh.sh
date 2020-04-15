#!/bin/sh

AGENT_BIN=`which ssh-agent`
AGENT_ADD_BIN=`which ssh-add`
AGENT_PID=`ps -fe | grep ${AGENT_BIN} | awk -vuser=$USER -vcmd="$AGENT_BIN" '$1==user && $8==cmd{print $2;exit;}'`
if [ -z "$AGENT_BIN" ]; then
    echo "no ssh agent found!";
    return
fi
if [ "" -eq "$AGENT_PID" ]; then
    if read -sq "YN?Do you want to unlock your ssh keys?"; then
        echo ""
        output=`$AGENT_BIN | sed 's/echo/#echo/g'`
        eval $output
        $AGENT_ADD_BIN
    fi
else
    for f in "/proc/"*
    do
        cmdline=`cat "$f/cmdline"`
        if [ "${AGENT_BIN}" -ef "${cmdline}" ]; then
            export SSH_AUTH_SOCK=`cat $f/net/unix | grep --binary-file=text -oP '((/[^/]*?)+/ssh-[^/]+/agent\.\d+$)'`
            export SSH_AGENT_PID=${f##*/}
            break;
        fi
    done
fi
