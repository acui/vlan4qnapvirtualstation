#!/bin/sh

RETVAL=0
QPKG_DIR=""
QPKG_NAME="`/sbin/getcfg QKVM Name -d QKVM -f /etc/config/qpkg.conf`"
MAIN_LINUX_CONFIG="/etc/config/uLinux.conf"
DEFAULT_GW=$(/sbin/getcfg Network "Default GW Device" -f $MAIN_LINUX_CONFIG)
USERGROUP="admin:administrators"
/bin/ln -sf /KVM/Qcmd /bin/virsh

#/sbin/log_tool -t2 -uSystem -p127.0.0.1 -mlocalhost -a "KVM_QNAP_ENABLED=`/sbin/getcfg $QPKG_NAME Enable -u -d FALSE -f /etc/config/qpkg.conf` $0 $1"
if [ `/sbin/getcfg $QPKG_NAME Enable -u -d FALSE -f /etc/config/qpkg.conf` = UNKNOWN ]; then
        /sbin/setcfg $QPKG_NAME Enable TRUE -f /etc/config/qpkg.conf
#	/sbin/log_tool -t2 -uSystem -p127.0.0.1 -mlocalhost -a "$QPKG_NAME ENABLED!"	
elif [ `/sbin/getcfg $QPKG_NAME Enable -u -d FALSE -f /etc/config/qpkg.conf` != TRUE ]; then
        echo "$QPKG_NAME is disabled."
#	/sbin/log_tool -t2 -uSystem -p127.0.0.1 -mlocalhost -a "$QPKG_NAME DISABLED!"
fi

_exit()
{
	/bin/echo -e "Error: $*"
	exit 1
}

wait_prev_process()
{
	cnt=0
	if [ -f /tmp/kvm_sh.pid ]; then

	    #Kill waiting start/stop
	    run_pid=$(cat /tmp/kvm_sh.pid)
            wait_pids=$(/bin/ps | grep "kvm_qnap.sh" | grep -v grep |grep -v "$run_pid"|grep -v $$|awk '{print $1}')
            for pid in $wait_pids; do
	    echo "Kill waiting operation $pid (running:$run_pid, self:$$)" && kill $pid 2>> /dev/null
	    done

	    #Wait running start/stop
	    TIMEOUT_SEC=`getcfg QKVM "Timeout" -f /etc/config/qpkg.conf | cut -d ',' -f2`
	    [ -z $TIMEOUT_SEC ] && TIMEOUT_SEC=0
	    echo "Wait previous kvm_qnap.sh (up to $TIMEOUT_SEC seconds)"
	    while [ "$cnt" -lt "$TIMEOUT_SEC" ] 
	    do
	        run_pid=$(cat /tmp/kvm_sh.pid)
	        run_ps=$(/bin/ps | grep $run_pid | grep -v grep)
	        if [ -z "$run_pid" ] || [ -z "$run_ps" ]; then
	            break
	        fi

	        echo -n "."
	        sleep  1
	        cnt=$((cnt + 1))
	    done
	    [ ! -z "$run_pid" ] && kill $run_pid 2>/dev/null
	fi

	# stored pid
	echo $$ > /tmp/kvm_sh.pid
}

find_base(){
	# Determine BASE installation location according to smb.conf
	QPKG_BASE=
	publicdir=`/sbin/getcfg Public path -f /etc/config/smb.conf`
	if [ ! -z $publicdir ] && [ -d $publicdir ];then
        	publicdirp1=`/bin/echo $publicdir | /bin/cut -d "/" -f 2`
        	publicdirp2=`/bin/echo $publicdir | /bin/cut -d "/" -f 3`
        	publicdirp3=`/bin/echo $publicdir | /bin/cut -d "/" -f 4`
        	if [ ! -z $publicdirp1 ] && [ ! -z $publicdirp2 ] && [ ! -z $publicdirp3 ]; then
        		[ -d "/${publicdirp1}/${publicdirp2}/Public" ] && QPKG_BASE="/${publicdirp1}/${publicdirp2}"
		fi
	fi

	# Determine BASE installation location by checking where the Public folder is.
	if [ -z $QPKG_BASE ]; then
        	for datadirtest in /share/HDA_DATA /share/HDB_DATA /share/HDC_DATA /share/HDD_DATA /share/MD0_DATA /share/MD1_DATA; do
        		[ -d $datadirtest/Public ] && QPKG_BASE="/${publicdirp1}/${publicdirp2}"
		done
	fi
	
	if [ -z $QPKG_BASE ] ; then
		echo "The Public share not found."
		_exit 1
	fi
	QPKG_DIR="$QPKG_BASE/.qpkg/$QPKG_NAME"
	QPKG_HIDDEN_DIR="$QPKG_BASE/.qpkg/.$QPKG_NAME"
}

insert_modules()
{
        ${QPKG_DIR}/modules/Insmod_ko.sh
        /bin/chown ${USERGROUP} /dev/kvm
        
        checkkvm=`/sbin/lsmod | grep kvm | wc -l`
        if [ $checkkvm -eq "1" ]; then
                /sbin/log_tool -t2 -uSystem -p127.0.0.1 -mlocalhost -a "[Virtualization Station] Please enable VT function in BIOS."
        elif [ $checkkvm != "2" ]; then
                /sbin/log_tool -t2 -uSystem -p127.0.0.1 -mlocalhost -a "[Virtualization Station] Firmware version may not compatible with Virtualization Station APP."
        fi
}

remove_modules()
{
        ${QPKG_DIR}/modules/Rmvmod_ko.sh

}

find_base

### QKVM Config Path ###
QKVM_CONFIG_PATH="`/sbin/getcfg QKVM Private_Config -d $QPKG_BASE/.qpkg/.QKVM/ -f /etc/config/qpkg.conf`"

### Check the current value of Private_Config is up to date or not. ###
if [ "$QPKG_HIDDEN_DIR" == "$QKVM_CONFIG_PATH" ]; then
    /bin/echo "Nothing has to do."
else
    /bin/echo "Private_Config has to update."
    /sbin/setcfg QKVM Private_Config "$QPKG_HIDDEN_DIR" -f /etc/config/qpkg.conf
    QKVM_CONFIG_PATH="$QPKG_HIDDEN_DIR"
fi

check_inf_bridge()
{
	/KVM/opt/htdocs/webvirtmgr/network/utility init_bridge_setting
}

source "$QPKG_DIR/kvm_qnap.conf"
source "$QPKG_DIR/vlan.sh"
ENABLED="`/sbin/getcfg $QPKG_NAME Enable -u -d FALSE -f /etc/config/qpkg.conf`"
UPNP_ENABLED="`/sbin/getcfg General "UPNP SUPPORT" -d FALSE -f ${QKVM_CONFIG_PATH}/config/config.conf`"

relink_files()
{
	# Re-link all symbolic link file and folders
	#
	# /KVM/opt/etc/libvirt
	# qemu -> $QPKG_HIDDEN_DIR/.XML/qemu/
	# storage -> $QPKG_HIDDEN_DIR/.XML/storage/
	#
	# /KVM/opt/var/lib/libvirt/qemu
	# save -> $QPKG_HIDDEN_DIR/.var/save/
	# snapshot -> $QPKG_HIDDEN_DIR/.var/snapshot/
	#
	# /KVM/opt/htdocs/webvirtmgr
	# webvirtmgr.db -> $QPKG_HIDDEN_DIR/.db/webvirtmgr.db
	#
	# Add parameter "n" to prevent the loop issue while creating symbolic of folder.
	# For example: 
	# [/KVM/opt/var/lib/libvirt/qemu/snapshot] # ls -al snapshot
	# lrwxrwxrwx    1 admin    administ        47 Jan 16 17:32 snapshot -> /share/CACHEDEV1_DATA/.qpkg/.QKVM/.var/snapshot/
	/bin/ln -sfn $QPKG_HIDDEN_DIR/.XML/qemu /KVM/opt/etc/libvirt/qemu
	/bin/ln -sfn $QPKG_HIDDEN_DIR/.XML/storage /KVM/opt/etc/libvirt/storage
	/bin/ln -sfn $QPKG_HIDDEN_DIR/.var/save /KVM/opt/var/lib/libvirt/qemu/save
	/bin/ln -sfn $QPKG_HIDDEN_DIR/.var/snapshot /KVM/opt/var/lib/libvirt/qemu/snapshot
	/bin/ln -sf $QPKG_HIDDEN_DIR/.db/webvirtmgr.db /KVM/opt/htdocs/webvirtmgr/webvirtmgr.db
	# 2015.06.24 Got one user reported the Web Server cannot startup.
	# After checked, the stunnel.pem is not existed in /etc/config/stunnel/
	# Thus we should check the stunnel.pem is not existed or not, if not, just use the file in /etc/default_config/stunnel/
	if [ ! -f "/etc/config/stunnel/stunnel.pem" ]; then
	    /bin/ln -sf /etc/default_config/stunnel/stunnel.pem /KVM/opt/conf/server.crt
	else
	    /bin/ln -sf /etc/config/stunnel/stunnel.pem /KVM/opt/conf/server.crt
	fi
}


if [ ! -d "/KVM" ]; then
        /bin/ln -sf $QPKG_DIR /KVM
fi

if [ ! -f "/usr/lib/locale/en_US/LC_CTYPE" ]; then
	/bin/cp -rf $QPKG_DIR/opt/usr /
fi

case "$1" in
	checkbr)
	    check_inf_bridge
	;;

	start)
	    # Starting KVM_QNAP...
	    version1=$(/sbin/getcfg System "Version" -f /etc/default_config/uLinux.conf | sed 's/\.//g')
	    if [ $version1 -ne '420' ]; then
	    	/bin/cp /KVM/opt/cgi-bin/qvsRedirectLib64.cgi /home/httpd/cgi-bin/qvsRedirect.cgi
	    	/bin/echo "Start process terminated."
	    	exit 1
	    fi
	    

	    ### For symbolic link file and folders only ###
	    relink_files

	    start_ps=$(/bin/ps | grep "kvm_qnap.sh start" | grep -v grep | wc -l)

	    ### For UPnP Upgrade only ###
	    if [ -f /tmp/kvmupgrade.log ]; then
		echo "Upgrade"
		#/bin/rm -rf /tmp/kvmupgrade.log
	    else 
	        if [ "$UPNP_ENABLED" == "TRUE" ] || [ "$UPNP_ENABLED" == "True" ]; then
		    /KVM/upnp.sh scan &
		fi
	    fi

	    if [ "$ENABLED" != "TRUE" ]; then
	        echo "$QPKG_NAME is disabled."
	        exit 1	
	    else
	        echo "$QPKG_NAME is enabled, enable KVM Web UI."

	        wait_prev_process
	        /sbin/setcfg QKVM Qkvm_Status "STARTING" -f /etc/config/qpkg.conf

	        if [ ! -c /dev/kvm ]; then
	            insert_modules
	        fi
	        check_inf_bridge
                start_vlan
                start_vlanbridge
	        #xrdp_ena="`/sbin/getcfg "xrdp" enable -f ${QKVM_CONFIG_PATH}/config/config.conf`"
	        #[ "$xrdp_ena" == "TRUE" ] && /KVM/XRDP/xrdp.sh start &

	        start_daemon_task
	        start_kvm_qnap

	        /sbin/setcfg QKVM Qkvm_Status "STARTED" -f /etc/config/qpkg.conf
	    fi	
	    /bin/chmod 755 /KVM/opt/htdocs/webvirtmgr/lib/LibvirtVga.py*
	    RETVAL=$?
	;;
	
	stop)  	
	    #Stopping KVM_QNAP...

	    wait_prev_process	    
	    /sbin/setcfg QKVM Qkvm_Status "STOPPING" -f /etc/config/qpkg.conf

	    stop_daemon_task
	    if [ -f /KVM/XRDP/xrdp.sh ]; then
	        /KVM/XRDP/xrdp.sh stop
	    fi
	    stop_kvm_qnap
            stop_vlanbridge
            stop_vlan
	    [ -c /dev/kvm ] && remove_modules
	    [ -d "${QKVM_CONFIG_PATH}/tmp" ] && rm -rf "${QKVM_CONFIG_PATH}/tmp"
	    /bin/rm /bin/virsh
	    /sbin/setcfg QKVM Qkvm_Status "STOPPED" -f /etc/config/qpkg.conf
	    RETVAL=$?
	;;

	restart)
	    start_daemon_task
	    restart_kvm_qnap

	    #xrdp_ena="`/sbin/getcfg "xrdp" enable -f ${QKVM_CONFIG_PATH}/config/config.conf`"
	    #if [ "$xrdp_ena" == "TRUE" ]; then
	    #    /KVM/XRDP/xrdp.sh restart 
	    #else
	    #    /KVM/XRDP/xrdp.sh stop
	    #fi

	    RETVAL=$?	
	;;
	
	*)
	    echo "Usage: $0 {start|stop|restart}"
	    exit 1
esac

# finish process
/bin/rm -f /tmp/kvm_sh.pid

exit $RETVAL
