#!/bin/bash
# Script automate the creating on volumes outside the ADR POD using snapshots 
# Version 0.2
#

# Set variables

FA1=10.226.224.112
POD=ora-target
PGROUP=adr-rep-pg
USER=pureuser
SUFFIX=snap`date +%Y%m%d%M`
VOL1=drdatavol
VOL2=drfravol
DDMONYYYY=`date +%d%b%Y`
LOG="/home/oracle/adr_${DDMONYYYY}.log"


tput clear

if [[ $EUID -eq 0 ]]
then
  echo "This script cannot be run as root user please run again as user ${ORA_USER}"
   exit 0
fi


function logit ()
{

   echo "INFO `date`- ${*}" >> $LOG 2>&1

}

RC ()
{
 ERR=$?
   if [ $ERR -ne 1 ]
       then
       logit echo "Function had an error please review logs file and contact Administrator"
       mailx -s "Problem with Refresh Script on ${DBNAME}, please review log file and Contact Administrator " $MAILLIST
       exit 0
     fi
}


pgroup ()
{
ssh_cmd="$(cat <<-EOF
    purepgroup list $PGROUP
EOF
)"

result=`ssh -t pureuser@10.226.224.112 $ssh_cmd`
if [[ $result == *"Error"* ]]; then
  echo "It's not there"
  ssh pureuser@10.226.224.112 "purepgroup create $PGROUP"
  ssh $USER@$FA1 "purevol add drdatavol,drfravol --pgroup $PGROUP"
  ssh $USER@$FA1 "purepgroup setattr --addtargetlist RedDotC adr-rep-pg"

  fi

}

create_snapshot()
{
  VOLUMES=$(ssh pureuser@10.226.224.112 " purevol list --filter \"name='ora-target::*'\" --csv"|grep -v Name|awk -F:: '{print $2}'|awk -F, '{print $1}')
for VOL in $VOLUMES; do
    SNAP_NAME="${VOL}.${SNAP_SUFFIX}"
    echo "Taking snapshot of volume $VOL as $SNAP_NAME..."
    ssh pureuser@10.226.224.112 "purevol snap ora-target::$VOL --suffix $SUFFIX"
done
}

copy-snap ()
{
ssh_cmd="$(cat <<-EOF
    purevol list $VOL1, $VOL2
EOF
)"

newvol=`ssh -t pureuser@10.226.224.112 $ssh_cmd`
echo $newvol
if [[ $newvol == *"Error"* ]]; then
  echo "Volumes are not created"
  ssh pureuser@10.226.224.112 "purevol copy ora-target::data.$SUFFIX drdatavol --overwrite"
  ssh pureuser@10.226.224.112 "purevol copy ora-target::fra.$SUFFIX drfravol --overwrite"
  ssh pureuser@10.226.224.112 " purevol add drdatavol,drfravol --pgroup adr-rep-pg"
  else
  ssh pureuser@10.226.224.112 "purevol copy ora-target::data.$SUFFIX drdatavol --overwrite"
  ssh pureuser@10.226.224.112 "purevol copy ora-target::fra.$SUFFIX drfravol --overwrite"
  fi

}

replicate ()
{


PGRPSNAP=$(ssh $USER@$FA1 ssh pureuser@10.226.224.112 "purepgroup list adr-rep-pg --snap --csv"|sed '1d'|awk -F, 'NR==1 {print $1}')
ssh $USER@$FA1 "purepgroup snap $PGROUP"
ssh $USER@$FA1 "purepgroup send $PGROUP --to RedDotC"
}


pgroup
create_snapshot
copy-snap
replicate
