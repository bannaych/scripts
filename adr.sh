#!/bin/bash
# Script automate the creating on volumes outside the ADR POD using snapshots 
# Version 0.1
#

# Set variables

Array1=10.226.224.112
POD=ora-target
PGROUP=adr-rep-pg
USER=pureuser
SUFFIX=snap`date +%Y%m%d%M`
VOL1=drdatavol
VOL2=drfravol


tput clear

if [[ $EUID -eq 0 ]]
then
  echo "This script cannot be run as root user please run again as user ${ORA_USER}"
   exit 0
fi


pgroup ()
{
ssh_cmd="$(cat <<-EOF
    purepgroup list $PGROUP
EOF
)"

result=`ssh -t $USER@$Array1 $ssh_cmd`
if [[ $result == *"Error"* ]]; then
  echo "It's not there"
  ssh $USER@$Array1 "purepgroup create $PGROUP"
  fi

}

create_snapshot()
{
  VOLUMES=$(ssh $USER@$Array1 " purevol list --filter \"name='ora-target::*'\" --csv"|grep -v Name|awk -F:: '{print $2}'|awk -F, '{print $1}')
for VOL in $VOLUMES; do
    SNAP_NAME="${VOL}.${SNAP_SUFFIX}"
    echo "Taking snapshot of volume $VOL as $SNAP_NAME..."
    ssh $USER@$Array1 "purevol snap ora-target::$VOL --suffix $SUFFIX"
done
}

copy-snap ()
{
ssh_cmd="$(cat <<-EOF
    purevol list $VOL1, $VOL2
EOF
)"

newvol=`ssh -t $USER@$Array1 $ssh_cmd`
echo $newvol
if [[ $newvol == *"Error"* ]]; then
  echo "Volumes are not created"
  ssh $USER@$Array1 "purevol copy ora-target::data.$SUFFIX drdatavol --overwrite"
  ssh $USER@$Array1 "purevol copy ora-target::fra.$SUFFIX drfravol --overwrite"
  ssh $USER@$Array1 " purevol add drdatavol,drfravol --pgroup adr-rep-pg"
  fi

}


pgroup
create_snapshot
copy-snap
