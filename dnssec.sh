#!/bin/sh

PROG=$0

CMD="$1"
shift

keygen="/usr/local/sbin/dnssec-keygen"
signzone="/usr/local/sbin/dnssec-signzone"
rndc="/usr/local/sbin/rndc"

CONFIGFILE="dnssec.conf"

LOCKF=""

MASTERDIR="/etc/namedb/master"
KEYDIR="$MASTERDIR"
CONFIGDIR="$MASTERDIR/config"
KEYBACKUPDIR="$CONFIGDIR/backup"

KSK_DEFAULT_PARAM="-n zone -a RSASHA1 -b 2048 -f ksk"
ZSK_DEFAULT_PARAM="-n zone -a RSASHA1 -b 1024"

SIGN_DEFAULT_PARAM="-N unixtime"

HEAD_ZSKNAME="zsk-"
HEAD_KSKNAME="ksk-"
HEAD_ZSSNAME="zss-"
HEAD_KSSNAME="kss-"

# setup
if [ ! -d $CONFIGDIR ]; then
	mkdir $CONFIGDIR
fi
if [ ! -d $KEYBACKUPDIR ]; then
	mkdir $KEYBACKUPDIR
fi

chdir $MASTERDIR

if [ -f $CONFIGFILE ]; then
	. $CONFIGFILE
fi

_check_file()
{
	while [ "$1" != "" ]; do
		if [ ! -f "$1" ]; then
			echo "$1 does not exist."
			_usage
		else
			# To be deleted
			echo "exist: $1"
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
		else
			# To be deleted
			echo "exist: $1"
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
	echo "   $PROG sign zone zone ..."
	echo "   $PROG keygen zone zone ..."
	exit 1
}

sign()
{
		_check_file $ZONE $KSK_FILE $ZSK_FILE
		KSK=`head -1 $KSK_FILE`
		ZSK=`head -1 $ZSK_FILE`
		> $INCFILE
		_check_file "$KSK.private" "$ZSK.private"
		cat $KSK_FILE $ZSK_FILE | while read keyfile
		do
			_check_file "$keyfile.key"
			cat "$keyfile.key" >> $INCFILE
		done
		for i in $KSK_S_FILE $ZSK_S_FILE
		do
			if [ -f $i ]; then
				keyfile=`head -1 $i`
				_check_file "$keyfile.key"
				cat "$keyfile.key" >> $INCFILE
			fi
		done
		echo $signzone $SIGN_PARAM -o $ZONE -k $KSK.private -f "$ZONE.signed" $ZONE $ZSK.private
		$signzone $SIGN_PARAM -o $ZONE -k $KSK.private -f "$ZONE.signed" $ZONE $ZSK.private

		echo "signzone returns $?"

		$rndc reload $ZONE
}

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

	KSK_PARAM="$KSK_DEFAULT_PARAM"
	ZSK_PARAM="$ZSK_DEFAULT_PARAM"
	SIGN_PARAM="$SIGN_DEFAULT_PARAM"
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
	keygen|initkeygen)
		_check_nofile $KSK_FILE $ZSK_FILE
		$keygen $KSK_PARAM $ZONE > $KSK_FILE
		$keygen $ZSK_PARAM $ZONE > $ZSK_FILE
		;;
	standby-zsk-keygen)
		_check_nofile $ZSK_S_FILE
		$keygen $ZSK_PARAM $ZONE > $ZSK_S_FILE
		;;
	standby-ksk-keygen)
		_check_nofile $KSK_S_FILE
		$keygen $ZSK_PARAM $ZONE > $KSK_S_FILE
		;;
	zskroll)
		_check_file $ZONE $ZSK_FILE $ZSK_S_FILE
		ZSK=`head -1 $ZSK_FILE`
		ZSS=`head -1 $ZSK_S_FILE`
		_check_file $ZSK.key $ZSS.key
		mv $ZSK.key $ZSK.private $KEYBACKUPDIR
		mv $ZSK_S_FILE $ZSK_FILE
		$keygen $ZSK_PARAM $ZONE > $ZSK_S_FILE
		ZSK="$ZSS"
		ZSS=`head -1 $ZSK_S_FILE`
		sign
		;;
	sign)
		sign
		;;
	status)
		if [ -f $KSK_FILE ]; then
			echo -n "$ZONE's KSK = "
			cat $KSK_FILE;
		fi
		if [ -f $KSK_S_FILE ]; then
			echo -n "$ZONE's standby KSK = "
			cat $KSK_S_FILE;
		fi
		if [ -f $ZSK_FILE ]; then
			echo -n "$ZONE's ZSK = "
			cat $ZSK_FILE;
		fi
		if [ -f $KSK_FILE ]; then
			echo -n "$ZONE's standby ZSK = "
			cat $ZSK_S_FILE;
		fi
		;;
	*)
		echo "unknown command: $CMD"
		_usage
		;;
	esac
	rm $LOCKF
done
exit 0
