#!/bin/sh

RADIODEVICE=radio0
OPENWRT=no
# Interface for normal AP Mode
AP_IF=wlan0
# Interface for MESH
MESH_IF=mesh0
# Channel
MESH_CHANNEL=0
# Mesh-SSID
MESH_SSID="PB-Mesh"
# Needed MTU for B.A.T.M.A.N.
MTU_NEEDED=1528
# Change this to 2nd card, if needed
IW_DEVICE=phy0
# Modified MAC
MODMAC=""
EXCHANGE_MAC="yes"

####
# BATMAN stuff
BAT_IF=bat0
# Increase lookup Frequency to 5s
BAT_INT=5000

check_rc() {
  MSG=""
  if [ -n "$2" ] ; then
    MSG="Error in $2"
  else
    MSG="Failed with RC $1"
  fi
  [ "$1" != "0" ] && echo $MSG && exit 255
}


uci_get_details() {
  #get mac Adress from uci
  SOURCEMAC=$(uci get wireless.$RADIODEVICE.macaddr)
  check_rc $? "getting  SourceMac"
  [[ $MESH_CHANNEL = "0" ]] && MESH_CHANNEL=$( uci get wireless.$RADIODEVICE.channel)
  check_rc $? "getting Channel"
}

conservative_details() {
   SOURCEMAC="F8:D1:11:BD:57:5C"
   MESH_CHANNEL=11
}

modify_MAC() {
  # Modify MAC for 2nd interface if not set
  #Change two letters
  if [ "$MODMAC" = "" ] ;  then
    MODMAC=$( echo $SOURCEMAC | sed 's/c/a/'  | sed 's/1/2/' )
    check_rc $?  "sed :( "
    echo "Found MAC for $RADIODEVICE :  $SOURCEMAC"
    echo " modified for 2nd Wifi-if  :  $MODMAC"
  fi
}

do_wlan_if_up() {
   echo  "Setting up AdHoc Interface for B.A.T.M.A.N. "
   iw $IW_DEVICE interface add $MESH_IF type adhoc
   check_rc $?

  echo "Increasing MTU for $MESH_IF to $MTU_NEEDED"
  ifconfig $MESH_IF mtu $MTU_NEEDED
  check_rc $?

  if [ "$EXCHANGE_MAC" = "yes" ] ; then
    echo "Changing $MESH_IF MAC to $MODMAC"
    ifconfig $MESH_IF hw ether $MODMAC
    check_rc $?
  fi

  echo "Setting up Channel $MESH_CHANNEL"
  iwconfig $MESH_IF channel $MESH_CHANNEL
  check_rc $?

  echo "Setting SSID for Mesh $MESH_SSID"
  iwconfig $MESH_IF  essid  $MESH_SSID
  check_rc $?
}


do_batman_up() {

  echo "Adding $MESH_IF to B.A.T.M.A.N."
  batctl if add  $MESH_IF  
  check_rc $?

  echo "Starting $BAT_IF"
  ifconfig $BAT_IF 0.0.0.0 up
  check_rc $?

  echo "Setting B.A.T.M.A.N. Intervall to $BAT_INT "
  batctl it $BAT_INT
  check_rc $?

}

mesh_start() {
  echo "Starting Mesh-IF!" 
  ifconfig $MESH_IF 0.0.0.0 up
  check_rc $?

# Extract auto IPV6 adress and remove it from mesh if
#  AUTO_IPV6=$( ifconfig $MESH_IF | grep "inet6.* " | sed -e "s/^.*inet6 addr: //" -e "s/ Scope.*\$//" )
#  echo "Removing .. $AUTO_IPV6 from $MESH_IF"
#  ifconfig $MESH_IF inet6 del $AUTO_IPV6
#  check_rc $? "resetting IPv6 on $MESH_IF"


}

mesh_stop() {
  echo "Stopping Mesh if!"
  ifconfig $MESH_IF down
#  check_rc $?
}

do_wlan_if_down() {
   echo "Cleaning up interfaces"
   iw dev $MESH_IF del 
#   check_rc $?
}

do_batman_down() {
  echo "Remove $MESH_IF from  $BAT_IF "
  batctl if del $MESH_IF
#  check_rc $?
}

check_requirements() {
  lsmod | grep batman >> /dev/null
  if [ "$?" != "0" ] ; then
     modprobe  batman-adv
     check_rc $? "Loading kernel module batman-adv failed.. maybe not installed?"
  fi
  batctl if > /dev/null
  check_rc $? "Failed running batctl- maybe not installed? "
}


check_requirements

if [ "$1" = "start" ] ; then
  echo "Starting Mesh Network with uci-collect..."
  uci_get_details 
  modify_MAC  
  do_wlan_if_up 
  mesh_start 
  do_batman_up
  echo "finished"
elif [ "$1" = "stop" ] ; then
  echo "Stopping Mesh Network..."
  mesh_stop
  do_batman_down
  do_wlan_if_down
  echo "finished"
elif [ "$1" =  "start_conservative" ] ; then
  echo "Starting Mesh Network  without Data-collecting..."
  conservative_details 
  modify_MAC 
  do_wlan_if_up 
  mesh_start 
  do_batman_up
  echo "finished"
else
  echo "Valid options are: start start_conservative stop"
fi
