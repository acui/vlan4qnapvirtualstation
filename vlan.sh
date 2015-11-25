#!/bin/sh

start_vlan()
{
    /usr/local/bin/vconfig add bond0 20
    /sbin/ifconfig bond0.20 up
}

stop_vlan()
{
    /sbin/ifconfig bond0.20 down
}

start_vlanbridge()
{
    /sbin/brctl addif br1 bond0.20
}

stop_vlanbridge()
{
    /sbin/brctl delif br1 bond0.20
}

