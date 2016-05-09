# vlan4qnapvirtualstation

Added vlan to a VirtualStation's virtual switch.
The default scripts added a new vlan with id 20 to the bond0 interface. And set the virtual switch br1 to bond0.20 . You can edit vlan.sh to fit your own need.

WARNING: If an interface does not have a vlan id in the NAS system settings. Do not use these scripts on that interface. They will make all the traffic on that inferface to be transfered with vlan id 20. But if the interface already has a vlan id, these scripts will not affect anything other than br1.

Supported VirtualStation Version:
 * 2.1.5132