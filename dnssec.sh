#!/bin/sh

# Copyright (c) 2009 Kazunori Fujiwara <fujiwara@wide.ad.jp>.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.

PROG=$0

DIR=`dirname $0`
CONFIGFILE="$DIR/dnssec.conf"

keygen="/usr/local/sbin/dnssec-keygen"
signzone="/usr/local/sbin/dnssec-signzone"
dsfromkey="/usr/local/sbin/dnssec-dsfromkey"
rndc="/usr/local/sbin/rndc"
MASTERDIR="/etc/namedb/master"

KSK_PARAM="-n zone -a RSASHA1 -b 2048 -f ksk"
ZSK_PARAM="-n zone -a RSASHA1 -b 1024"
SIGN_PARAM="-N unixtime"

if [ -f $CONFIGFILE ]; then
	. $CONFIGFILE
fi

CMD="$1"
shift

if [ "$CONFIGDIR" = "" ]; then
	CONFIGDIR="$MASTERDIR/config"
fi
if [ "$KEYDIR" = "" ]; then
	KEYDIR="$CONFIGDIR/keydir"
fi
if [ "$KEYBACKUPDIR" = "" ]; then
	KEYBACKUPDIR="$CONFIGDIR/backup"
fi

LOCKF=""

HEAD_ZSKNAME="zsk-"
HEAD_KSKNAME="ksk-"
HEAD_ZSSNAME="zss-"
HEAD_KSSNAME="kss-"

# setup
if [ ! -d $CONFIGDIR ]; then
	mkdir -p $CONFIGDIR
fi
if [ ! -d $KEYBACKUPDIR ]; then
	mkdir -p $KEYBACKUPDIR
fi
if [ ! -d $KEYDIR ]; then
	mkdir -p $KEYDIR
fi

cd $MASTERDIR

_check_file()
{
	while [ "$1" != "" ]; do
		if [ ! -f "$1" ]; then
			echo "$1 does not exist."
			_usage
		fi
		shift
	done
}
_check_nofile()
{
	while [ "$1" != "" ]; do
		if [ -f "$1" ]; then
			echo "$1 exist."
			_usage
		fi
		shift
	done
}

_usage()
{
	if [ "$LOCKF" != "" ]; then
		rm $LOCKF
	fi
	echo "Usage: "
	echo "   $PROG sign zone(s)                 : (Re-)Sign the zone(s)"
	echo "   $PROG keygen zone(s)               : Generate KSK and ZSK for the zone(s)"
	echo "   $PROG keygen2 zone(s)              : Generate KSK and ZSK and standby sets for the zone(s)"
	echo "   $PROG status zone(s)               : Show key status for the zone(s)"
	echo "   $PROG standby-zsk-keygen zone(s)   : Generate standby ZSK key for the zone(s)"
	echo "   $PROG standby-ksk-keygen zone(s)   : Generate standby KSK key for the zone(s)"
	echo "   $PROG zskroll zone(s)              : Roll ZSK for the zone(s)"
	exit 1
}

sign()
{
	_check_file $ZONE $KSK_FILE $ZSK_FILE
	KSK=`head -1 $KSK_FILE`
	ZSK=`head -1 $ZSK_FILE`
	> $INCFILE
	_check_file "$KEYDIR/$KSK.private" "$KEYDIR/$ZSK.private"
	cat $KSK_FILE $ZSK_FILE | while read keyfile
	do
		_check_file "$KEYDIR/$keyfile.key"
		cat "$KEYDIR/$keyfile.key" >> $INCFILE
	done
	for i in $KSK_S_FILE $ZSK_S_FILE
	do
		if [ -f $i ]; then
			keyfile=`head -1 $i`
			_check_file "$KEYDIR/$keyfile.key"
			cat "$KEYDIR/$keyfile.key" >> $INCFILE
		fi
	done
	echo $signzone $SIGN_PARAM -o $ZONE -k $KEYDIR/$KSK.private -f "$ZONE.signed" $ZONE $KEYDIR/$ZSK.private
	$signzone $SIGN_PARAM -o $ZONE -k $KEYDIR/$KSK.private -f "$ZONE.signed" $ZONE $KEYDIR/$ZSK.private 2>&1

	echo "signzone returns $?"

	$rndc -k "$MASTERDIR/rndc.key" reload $ZONE
}

status()
{
	if [ -f $KSK_FILE ]; then
		echo -n "$ZONE's KSK = "
		cat $KSK_FILE;
		$dsfromkey -2 $KEYDIR/`cat $KSK_FILE`
	fi
	if [ -f $KSK_S_FILE ]; then
		echo -n "$ZONE's standby KSK = "
		cat $KSK_S_FILE;
		$dsfromkey -2 $KEYDIR/`cat $KSK_S_FILE`
	fi
	if [ -f $ZSK_FILE ]; then
		echo -n "$ZONE's ZSK = "
		cat $ZSK_FILE;
	fi
	if [ -f $ZSK_S_FILE ]; then
		echo -n "$ZONE's standby ZSK = "
		cat $ZSK_S_FILE;
	fi
}

if [ "$CMD" = "" ]; then
	_usage
fi

for ZONE in $*
do
	LOCKF="$CONFIGDIR/$ZONE.lock"
	TMPF="$CONFIGDIR/$ZONE.$$"
	OUTF="$ZONE.signed"
	KSK_FILE="$CONFIGDIR/$HEAD_KSKNAME$ZONE"
	ZSK_FILE="$CONFIGDIR/$HEAD_ZSKNAME$ZONE"
	KSK_S_FILE="$CONFIGDIR/$HEAD_KSSNAME$ZONE"
	ZSK_S_FILE="$CONFIGDIR/$HEAD_ZSSNAME$ZONE"
	INCFILE="$MASTERDIR/$ZONE.keys"

	touch $TMPF
	if ln $TMPF $LOCKF; then
		:
	else
		rm $TMPF
		echo "zone $ZONE locked"
		continue
	fi
	rm $TMPF
	case $CMD in
	keygen)
		_check_nofile $KSK_FILE $ZSK_FILE
		(cd $KEYDIR; $keygen $KSK_PARAM $ZONE) > $KSK_FILE
		(cd $KEYDIR; $keygen $ZSK_PARAM $ZONE) > $ZSK_FILE
		status
		;;
	keygen2)
		_check_nofile $KSK_FILE $ZSK_FILE $KSK_S_FILE $ZSK_S_FILE
		(cd $KEYDIR; $keygen $KSK_PARAM $ZONE) > $KSK_FILE
		(cd $KEYDIR; $keygen $ZSK_PARAM $ZONE) > $ZSK_FILE
		(cd $KEYDIR; $keygen $KSK_PARAM $ZONE) > $KSK_S_FILE
		(cd $KEYDIR; $keygen $ZSK_PARAM $ZONE) > $ZSK_S_FILE
		status
		;;
	standby-zsk-keygen)
		_check_nofile $ZSK_S_FILE
		(cd $KEYDIR; $keygen $ZSK_PARAM $ZONE) > $ZSK_S_FILE
		status
		;;
	standby-ksk-keygen)
		_check_nofile $KSK_S_FILE
		(cd $KEYDIR; $keygen $KSK_PARAM $ZONE) > $KSK_S_FILE
		status
		;;
	zskroll)
		_check_file $ZONE $ZSK_FILE $ZSK_S_FILE
		ZSK=`head -1 $ZSK_FILE`
		ZSS=`head -1 $ZSK_S_FILE`
		_check_file $KEYDIR/$ZSK.key $KEYDIR/$ZSS.key $KEYDIR/$ZSK.private $KEYDIR/$ZSS.private
		mv $KEYDIR/$ZSK.key $KEYDIR/$ZSK.private $KEYBACKUPDIR/
		mv $ZSK_S_FILE $ZSK_FILE
		(cd $KEYDIR; $keygen $ZSK_PARAM $ZONE) > $ZSK_S_FILE
		OLDZSK="$ZSK"
		ZSK="$ZSS"
		ZSS=`head -1 $ZSK_S_FILE`
		echo "$ZONE 's ZSK: valid -> removed: $OLDZSK"
		echo "$ZONE 's ZSK: standby -> valid: $ZSK"
		echo "$ZONE 's ZSK:      new standby: $ZSS"
		sign
		;;
	sign)
		sign
		;;
	status)
		status
		;;
	*)
		echo "unknown command: $CMD"
		_usage
		;;
	esac
	rm $LOCKF
done
exit 0
