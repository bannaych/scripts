#!/bin/bash
# Script to promote Disaster Recovery server using Active-DR
# Version 0.3
#

# Set variables

FA1=10.226.224.112
POD=ora-target
PGROUP=adr-rep-pg
USER=pureuser
SUFFIX=snap`date +%Y%m%d%H%M`
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


logit ()
{

   echo "INFO `date`- LOG FILES FOR ADR ============================= >> $LOG"

}

RC ()
{
 ERR=$?
   if [ $ERR -ne 1 ]
       then
       logit echo "Function had an error please review logs file and contact Administrator"
       mailx -s "Problem with Script , please review log file and Contact Administrator " $MAILLIST
       exit 0
     fi
}

podstate ()
{

STATE=$(ssh $USER@$FA1 " purepod list $POD "|sed '1d'|awk '{print $6}')
if [ $STATE == "demoted" ]
 then
   echo "POD is Demoted, exiting script" >> $LOG
   exit
 else
  echo " POD is promoted " >> $LOG
fi
}

pgroup ()
{
ssh_cmd="$(cat <<-EOF
    purepgroup list $PGROUP
EOF
)"

result=`ssh -t $USER@$FA1 $ssh_cmd`
if [[ $result == *"Error"* ]]; then
  echo "It's not there"
  ssh $USER@$FA1 "purepgroup create $PGROUP" | tee -a $LOG
  ssh $USER@$FA1 "purevol add $VOL1,$VOL2 --pgroup $PGROUP" |  tee -a $LOG
  ssh $USER@$FA1 "purepgroup setattr --addtargetlist RedDotC $PGROUP" | tee -a $LOG

  fi

}

create_snapshot()
{
  VOLUMES=$(ssh $USER@$FA1 " purevol list --filter \"name='$POD::*'\" --csv"|grep -v Name|awk -F:: '{print $2}'|awk -F, '{print $1}')
for VOL in $VOLUMES; do
    SNAP_NAME="${VOL}.${SNAP_SUFFIX}"
    echo "Taking snapshot of volume $VOL as $SNAP_NAME..."
    ssh $USER@$FA1 "purevol snap $POD::$VOL --suffix $SUFFIX" | tee -a $LOG
done
}

copy-snap ()
{
ssh_cmd="$(cat <<-EOF
    purevol list $VOL1, $VOL2
EOF
)"

newvol=`ssh -t $USER@$FA1 $ssh_cmd`
echo $newvol
if [[ $newvol == *"Error"* ]]; then
  echo "Volumes are not created"
  ssh $USER@$FA1 "purevol copy $POD::data.$SUFFIX $VOL1 --overwrite" | tee -a $LOG
  ssh $USER@$FA1 "purevol copy $POD::fra.$SUFFIX $VOL2 --overwrite" |  tee -a $LOG
  ssh $USER@$FA1 " purevol add $VOL1,$VOL2 --pgroup $PGROUP" | tee -a $LOG
  else
  ssh $USER@$FA1 "purevol copy $POD::data.$SUFFIX $VOL1 --overwrite" | tee -a $LOG
  ssh $USER@$FA1 "purevol copy $POD::fra.$SUFFIX $VOL2 --overwrite" | tee -a $LOG
  fi

}

replicate ()
{


PGRPSNAP=$(ssh $USER@$FA1 "purepgroup list adr-rep-pg --snap --csv"|sed '1d'|awk -F, 'NR==1 {print $1}')
ssh $USER@$FA1 "purepgroup snap $PGROUP" | tee -a $LOG
ssh $USER@$FA1 "purepgroup send $PGROUP --to RedDotC" | tee -a $LOG
}

delsnaps ()
{
ssh $USER@$FA1 "purevol destroy $POD::data.$SUFFIX"
ssh $USER@$FA1 "purevol destroy $POD::fra.$SUFFIX"
ssh $USER@$FA1 "purevol eradicate $POD::data.$SUFFIX"
ssh $USER@$FA1 "purevol eradicate $POD::fra.$SUFFIX"
}

logit >> $LOG
podstate
pgroup
create_snapshot
copy-snap
replicate
delsnaps
