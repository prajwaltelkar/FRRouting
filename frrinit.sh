#!/bin/bash
#
### BEGIN INIT INFO
# Provides: frr
# Required-Start: $local_fs $network $remote_fs $syslog
# Required-Stop: $local_fs $network $remote_fs $syslog
# Default-Start:  2 3 4 5
# Default-Stop: 0 1 6
# Short-Description: start and stop the FRR routing suite
# Description: FRR is a routing suite for IP routing protocols like
#              BGP, OSPF, RIP and others. This script contols the main
#              "watchfrr" daemon.
### END INIT INFO
#
# This is the main init script for FRR.  It mostly wraps frrcommon.sh which
# provides the actual functions to start/stop/restart things.
#

if [ -r "/lib/lsb/init-functions" ]; then
	. /lib/lsb/init-functions
else
	log_success_msg() {
		echo "$@"
	}
	log_warning_msg() {
		echo "$@" >&2
	}
	log_failure_msg() {
		echo "$@" >&2
	}
fi

# "/usr/lib/frr/frrinit.sh start somenamespace"
FRR_PATHSPACE="$2"

self="`dirname $0`"
if [ -r "$self/frrcommon.sh" ]; then
	. "$self/frrcommon.sh"
else
	. "/usr/lib/frr/frrcommon.sh"
fi

case "$1" in
start)
	daemon_list daemons
	watchfrr_options="$watchfrr_options $daemons"
	daemon_start watchfrr
	;;
stop)
	daemon_stop watchfrr
	all_stop --reallyall
	exit ${still_running:-0}
	;;

restart|force-reload)
	daemon_stop watchfrr
	all_stop --reallyall

	daemon_list daemons
	watchfrr_options="$watchfrr_options $daemons"
	daemon_start watchfrr
	;;

status)
	fail=0
	print_status watchfrr || fail=1
	all_status || fail=1
	exit $fail
	;;

reload)
	if [ ! -x "$RELOAD_SCRIPT" ]; then
		log_failure_msg "The frr-pythontools package is required for reload functionality."
		exit 1
	fi

	# systemd doesn't set WATCHDOG_USEC for reload commands.
	watchfrr_pidfile="$V_PATH/watchfrr.pid"
	watchfrr_pid="`cat \"$watchfrr_pidfile\"`"
	if [ -d "/proc/$watchfrr_pid" ]; then
		wdt="`tr '\0' '\n' < /proc/$watchfrr_pid/environ | grep '^WATCHDOG_USEC='`"
		wdt="${wdt#WATCHDOG_USEC=}"
		[ -n "$wdt" ] && : ${WATCHDOG_USEC:=$wdt}
		[ -n "$WATCHDOG_USEC" ] && export WATCHDOG_USEC
	fi

	# restart watchfrr to pick up added daemons.
	# NB: This will NOT cause the other daemons to be restarted.
	daemon_list daemons
	watchfrr_options="$watchfrr_options $daemons"
	daemon_stop watchfrr && \
		daemon_start watchfrr

	# make systemd not kill watchfrr after ExecReload completes
	# 3 goats were sacrificed to restore sanity after coding this
	watchfrr_pid="`cat \"$watchfrr_pidfile\"`"
	if [ -f "/proc/$watchfrr_pid/cgroup" -a -d "/sys/fs/cgroup/systemd" ]; then
		cg="`egrep '^[0-9]+:name=systemd:' \"/proc/$watchfrr_pid/cgroup\"`"
		cg="${cg#*:*:}"

		cgmain="$cg"
		cgmain="${cgmain%/.control}"
		cgmain="${cgmain%/control}"

		[ -n "$cg" -a "$cg" != "$cgmain" ] && \
			echo "$watchfrr_pid" > "/sys/fs/cgroup/systemd/$cgmain/tasks"
	fi

	NEW_CONFIG_FILE="${2:-$C_PATH/frr.conf}"
	[ ! -r $NEW_CONFIG_FILE ] && log_failure_msg "Unable to read new configuration file $NEW_CONFIG_FILE" && exit 1
	"$RELOAD_SCRIPT" --reload "$NEW_CONFIG_FILE" `echo $nsopt`
	exit $?
	;;

*)
	log_failure_msg "Unknown command: $1" >&2
	exit 1
esac
