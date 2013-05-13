#!/bin/sh
# $Id: on_device_updater.sh 58511 2010-10-28 10:26:29Z henry $
# on_device_updater.sh - Based on updater.sh.  Lives in the update tarballs.
#
# Usage:
#   on_device_updater.sh <update_dir> [post_update command]
#
# Where <update_dir> is the directory (usually in /mnt/storage) where the
# updater lives.
# If a third argument is specified, then it will be executed after a
# successful update.
#
# This updater will ALWAYS update the opposite partition.

UPDATE_FILE=$1
POST_UPDATE=$2
RFS_SIZE=33718183
RFS_IMAGE_SIZE=88620
KRN_SIZE=2109248
PSP_SIZE=4644
RFS_MD5=fbe6279f19e72f91334ff9f9dc46abac
KRN_MD5=307b05e51f999b9c1e66dd65bbfab341
PSP_MD5=0329676a6d70d859cd54905c119d51c7
TARGET_PLATFORM=falconwing
LOGFILE_NAME=update.log
LOGFILE_DIR=/mnt/storage
LOGFILE=${LOGFILE_DIR}/${LOGFILE_NAME}

[ "${UPDATE_FILE}" ] || { echo "Syntax: $0 [update_tarball]"; exit 1; }
[ -f "${UPDATE_FILE}" ] || { echo "Syntax: $0 [update_tarball]"; exit 1; }

# /mnt/storage may be an empty mount point (hence tempfs) if in recovery mode
# make sure it exists
[ -d /mnt/storage ] || { mkdir /mnt/storage; }

# POST_UPDATE undefined is the new way to tell we're in phase 1
if [ "${POST_UPDATE}" ]
then
    echo "Continuing $0 phase 2 from tarball ${UPDATE_FILE}" >> ${LOGFILE}
else
    echo "Starting $0 from tarball ${UPDATE_FILE}" > ${LOGFILE}
fi

echo "$0 updating from tarball ${UPDATE_FILE}"
echo "/proc/cmdline:" >> ${LOGFILE}
cat /proc/cmdline >> ${LOGFILE}

# /mnt/storage is not mounted in recovery mode (perhaps to save time?)
# We need it for psp backup and for logging
for arg in $(cat /proc/cmdline)
do
    case "${arg}" in
    logo.brand\=*)
        BRAND=$(echo ${arg} | cut -d= -f2)
        ;;
    partition\=recovery)
	# Save the update log we've written so far
	echo "Mounting storage partition" | tee -a ${LOGFILE}
	cp ${LOGFILE} /tmp
	# Mount the storage partition.
	fsck.ext3 -y $(grep /mnt/storage /etc/fstab | awk '{print $1}')
	mount /mnt/storage
	# Copy update log back to /mnt/storage
	cp /tmp/${LOGFILE_NAME} ${LOGFILE_DIR}
	echo "Storage partition mounted" | tee -a ${LOGFILE}
	;;
    esac
done
if [ "x${BRAND}" = "xchumby" ]
then
    BRAND=""
else
    BRAND=".${BRAND}"
fi

echo "BRAND=${BRAND}" >> ${LOGFILE}

fail() {
    echo $*
    echo $* >> ${LOGFILE}
    sync ; sync
    # Clean up here.  Unmount partitions and draw the failure screen.
    imgtool --mode=draw /bitmap/${VIDEO_RES}/update_unsuccessful.bin${BRAND}.jpg
    exit 1
}

# Backup /psp to $1/psp.backup
backup_psp()
{
	BASE=$1
	[ "${BASE}" = "" ] && { echo "No base dir for psp.backup specified" | tee -a ${LOGFILE}; exit 1; }
	# Wipe any existing backup
	[ -d ${BASE}/psp.backup ] && rm -rf ${BASE}/psp.backup
	# Default list - we now keep an actual backup_list which the user can modify
	# Both happen to be the same for now but /psp/backup_list always overrides this
	# list and contains a reference to itself.
	#BACKUP_LIST="pan mute volume network_config network_configs ts_hid_settings brightness localtime timezone timezone_city pandora_act pandora_pass pandora_stn pandora_user photobucket"
	BACKUP_LIST="network_config network_configs"
	[ -f /psp/backup_list ] && BACKUP_LIST="$(cat /psp/backup_list)"
	[ "${BACKUP_LIST}" = "" ] && { echo "Backup list is empty" | tee -a ${LOGFILE}; exit 1; }
	# Make sure we can write
	mkdir ${BASE}/psp.backup || { echo "Unable to create ${BASE}/psp.backup" | tee -a ${LOGFILE}; exit 1; }
	[ -d ${BASE}/psp.backup ] || { echo "${BASE}/psp.backup creation failed" | tee -a ${LOGFILE}; exit 1; }
	# Copy everything
	echo "Beginning backup to ${BASE}/psp.backup" | tee -a ${LOGFILE}
	CWD=$(pwd)
	cd /psp
	for f in ${BACKUP_LIST}
	do
		cp -a ${f} ${BASE}/psp.backup/
	done
	cd ${CWD}
	echo "Backup completed" | tee -a ${LOGFILE}
	sync
}


if [ "${CNPLATFORM}" != "${TARGET_PLATFORM}" ]
then
	fail "This update is intended for ${TARGET_PLATFORM}, but you're running ${CNPLATFORM}"
fi


# This is being done because ... ?
# XXX Removing files from /psp/ is something we normally shouldn't do XXX
rm -f /psp/fmradio_xclk


# These partitions are the allowable boot partitions, as currently defined.
RFSA_PART=/dev/mmcblk0p2
RFSB_PART=/dev/mmcblk0p3


RFS_TARBALL=rfs.tar.gz
PSP_TARBALL=psp.tar.gz
KRN_FILE=krn

if echo ${UPDATE_FILE} | grep -q tgz
then
    EXTRACT_CMD=tar
    EXTRACT_ARG=xzOf
else
    EXTRACT_CMD=unzip
    EXTRACT_ARG=-p
fi

echo "EXTRACT_CMD=${EXTRACT_CMD} EXTRACT_ARG=${EXTRACT_ARG}" >> ${LOGFILE}

# Stop the control panel.  We'd better be daemonized by now, e.g. by
# running under something that did a fork() { exec() } { exit() } if we
# were launched from flashplayer.
stop_control_panel
switch_fb.sh 0
# Has no effect
#cat /dev/zero > /dev/fb1 2> /dev/null

echo "CP stopped; ps:" >> ${LOGFILE}
ps >> ${LOGFILE}

# We don't verify the integrity, as they're verified when the update is
# downloaded from the server.  Or, if we're doing a USB update, we hope
# they know what they're doing (and an invalid archive would have prevented
# this script from running, anyway.)



# The kernel commandline will have "root=${RFSA_PART}" as one of the lines
# when booting if we're in rfsa.  Otherwise, it'll have rfsb.
if [ $(cat /proc/cmdline | tr ' ' '\n' | grep "root=${RFSA_PART}" | wc -l) -gt 0 ]
then
    CURRENT_PART=${RFSA_PART}
    UPDATE_PART=${RFSB_PART}
    UPDATE_KERN=krnB
    OTHER_PARTITION=1
else
    CURRENT_PART=${RFSB_PART}
    UPDATE_PART=${RFSA_PART}
    UPDATE_KERN=krnA
    OTHER_PARTITION=0
fi

echo "CURRENT_PART=${CURRENT_PART}; UPDATE_PART=${UPDATE_PART}; UPDATE_KERN=${UPDATE_KERN}; OTHER_PARTITION=${OTHER_PARTITION}" >> ${LOGFILE}

# XXX HACK!
# If there is no "post update" command, then we assume the system is
# performing the first stage of an update, and expects this script to
# reboot.  Presumably, the update will continue afterwards, and the update
# system will call us again with an argument to do something /other/ than
# reboot.
# So we use the existence of the "post update" command to determine whether
# we're on the first step of the update process, or the second.
# If it's not there, we're on part one because we'll reboot afterwards.
# If it's there, we're on part two because we're not going to reboot.
if [ "x${POST_UPDATE}" != "x" ]
then
    PART_NAME="part 2/2"
else
    PART_NAME="part 1/2"
fi

echo "PART_NAME=${PART_NAME}" >> ${LOGFILE}

# The kernel commandline will have "partition=recovery" if we're in
# recovery mode.  Use that to determine whether we're on the active
# partition or not.
if [ $(cat /proc/cmdline | tr ' ' '\n' | grep "partition=recovery" | wc -l) -gt 0 ]
then
    OTHER_ACTIVE=1
else
    OTHER_ACTIVE=0
fi

echo "OTHER_ACTIVE=${OTHER_ACTIVE}" >> ${LOGFILE}

# Update the other partition.  Start out by drawing the "Updating!" image.
imgtool --mode=draw /bitmap/${VIDEO_RES}/updating_software.bin${BRAND}.jpg
fbwrite "\n\n\n    Updating ${PART_NAME}..."

echo "Updating ${PART_NAME}" >> ${LOGFILE}

# Set update in progress flag.  Used to detect a failed update.
config_util --cmd=putupdate --updateflag=1


echo "Update marked as in-progress" >> ${LOGFILE}

# Ensure the other partition is unmounted.
if [ $(mount | grep " ${UPDATE_PART} " | wc -l) -gt 0 ]
then
    echo "Attempting to unmount ${UPDATE_PART}" >> ${LOGFILE}
    umount ${UPDATE_PART} || fail "Unable to unmount ${UPDATE_PART}"
    sleep 1
    if [ $(mount | grep " ${UPDATE_PART} " | wc -l) -gt 0 ]
    then
        fail "Unable to unmount update partition ${UPDATE_PART}!"
    fi
fi

# Create temporary mount point
UPDATE_PART_DIR=/tmp/updater.$$
mkdir -p ${UPDATE_PART_DIR} || fail "Unable to create temp mountpoint"

# Temporarily mount the other partition as ext2 to get a reasonable maximum size
# without unnecessary kjournald overhead
if mount -text2 -onoatime,nodiratime,ro ${UPDATE_PART} ${UPDATE_PART_DIR}
then
	RFS_PARTITION_SIZE=$(df ${UPDATE_PART} | awk '/^\// {print $2;}')
	echo "mounted ${UPDATE_PART} on ${UPDATE_PART_DIR}, got partition size ${RFS_PARTITION_SIZE}" >> ${LOGFILE}
	# Ignore failures due to mount issues - this is just a safety check
	if [ "${RFS_PARTITION_SIZE}" ]
	then
		[ ${RFS_IMAGE_SIZE} -gt ${RFS_PARTITION_SIZE} ] && fail "Image size ${RFS_IMAGE_SIZE} exceeds partition size ${RFS_PARTITION_SIZE} on ${UPDATE_PART}"
	else
		echo "Image size ${RFS_IMAGE_SIZE}k will fit on partition ${UPDATE_PART}" | tee -a ${LOGFILE}
		echo "Partition size is ${RFS_PARTITION_SIZE}k and will have ~$(expr ${RFS_PARTITION_SIZE} - ${RFS_IMAGE_SIZE})k remaining" | tee -a ${LOGFILE}
	fi
fi

# as we're not doing anything with the actual update,
# it's okay to skup rootfs format stuff to accelerate the update process.
# --Huan

# Attempt unmount regardless of return from temporary mount
umount ${UPDATE_PART}

echo "Unmounted ${UPDATE_PART} - starting format" >> ${LOGDIR}

# Format the newly-unmounted partition.
mkfs.ext3 ${UPDATE_PART} || fail "Unable to reformat ${UPDATE_PART}"

# Re-mount the newly-reformatted partition.

# Mount the partition as ext2, as we won't need journaling.  This cuts 30
# seconds off of the update time.  (If it fails, we'll just reformat it!)
mount -text2 -onoatime,nodiratime ${UPDATE_PART} ${UPDATE_PART_DIR} || fail "Unable to remount ${UPDATE_PART}"


# Extract the rfs tarball.
cd ${UPDATE_PART_DIR} || fail "Unable to change to ${UPDATE_PART_DIR}"

${EXTRACT_CMD} ${EXTRACT_ARG} ${UPDATE_FILE} rfs.tar.gz \
        | progress -f -b ${RFS_SIZE} \
        | tar xz -C ${UPDATE_PART_DIR} \
            || fail "Unable to extract tarball ${UPDATE_FILE} to ${UPDATE_PART_DIR}"

echo "Extraction of ${UPDATE_FILE} completed" >> ${LOGFILE}

# Set password for root just for kicks.

# if you like :-)
#sed -i 's/root::/root:$1$iFshNYqt$oPh55AQmDOmGsiDR4jBcp0:/' ${UPDATE_PART_DIR}/etc/shadow
#echo "Updated password for root" >> ${LOGFILE}

# Need to patch the DNS server stuff so that it doesn't try to phone home

sed -i 's/ping.chumby.com/127.0.0.1\/assets/' ${UPDATE_PART_DIR}/usr/chumby/scripts/start_network
echo "Patched network start script" >> ${LOGFILE}

if [ ! -d "/psp/assets" ];
then
    mkdir /psp/assets
fi

if [ ! -e "${UPDATE_PART_DIR}/www/assets" ];
then
    ln -s /psp/assets ${UPDATE_PART_DIR}/www/ \
	|| fail "Unable to link assets directory for web server on ${UPDATE_PART_DIR}/www/"
else
    echo "Seems like the assets dir is already there" >> ${LOGFILE}
fi

echo "Done linking assets for www" >> ${LOGFILE}

# Unmount the newly-populated partition.
# It seems as though it's busy sometimes when it goes to unmount itself.
# So let it try again after 5 seconds.
cd /

umount ${UPDATE_PART_DIR}
if [ $? -ne 0 ]
then
    sleep 5
    umount ${UPDATE_PART_DIR} || fail "Unable to unmount ${UPDATE_PART_DIR}"
fi

echo "Updating kernel ${UPDATE_KERN}" >> ${LOGFILE}

# Update the kernel.
${EXTRACT_CMD} ${EXTRACT_ARG} ${UPDATE_FILE} krn \
        | config_util --cmd=putblock --pad --dev=/dev/mmcblk0p1 --block=${UPDATE_KERN} \
            || fail "Unable to update kernel"



# Switch back to the old polled version of /dev/switch.
if [ -e /psp/flashplayer.cfg ]
then
    echo "Editing /psp/flashplayer.cfg" >> ${LOGFILE}
    sed 's/^FakeBentKeyFlagMask/#FakeBentKeyFlagMask/' < /psp/flashplayer.cfg \
        | sed 's/KbdEventInterface/#KbdEventInterface/' \
        | sed 's/FakeBentKeyCode/#FakeBentKeyCode/' \
        > /psp/flashplayer.cfg.new
    mv /psp/flashplayer.cfg.new /psp/flashplayer.cfg
fi






# Upon successful completion of an update, run the post-update command if
# one was provided.  Otherwise, reboot.
if [ "x${POST_UPDATE}" != "x" ]
then
    echo "Running POST_UPDATE" >> ${LOGFILE}
    eval ${POST_UPDATE}
    echo "POST_UPDATE (${POST_UPDATE}) completed" >> ${LOGFILE}
else

    # Apparently we no longer have a phase 1 / phase 2 indicator, and the absence
    # of POST_UPDATE indicates that we're in phase 1.
    # If a USB update, remove everything from /psp (ORIGIN may not be set on older firmware)
    # Note that Falconwing has a separate /psp mount point and therefore defines the contents of psp.tar.gz
    # differently (as relative to the mount point root rather than relative to /mnt/storage)
    echo "Creating backup of psp; ORIGIN=${ORIGIN}" >> ${LOGFILE}
    backup_psp /mnt/storage
    [ "${ORIGIN}" = "USB" ] && rm -rf /psp/*
    ${EXTRACT_CMD} ${EXTRACT_ARG} ${UPDATE_FILE} psp.tar.gz \
        | tar xz -C /psp \
            || fail "Unable to extract psp tarball"
    
    ${EXTRACT_CMD} ${EXTRACT_ARG} ${UPDATE_FILE} qt4.tar.gz \
        | tar xz -C /mnt/storage \
            || fail "Unable to extract qt4 tarball"

    ${EXTRACT_CMD} ${EXTRACT_ARG} ${UPDATE_FILE} pcsensorpack.tar.gz \
        | tar xz -C /mnt/storage \
            || fail "Unable to extract pjctl tarball"

    ${EXTRACT_CMD} ${EXTRACT_ARG} ${UPDATE_FILE} tslib.tar.gz \
        | tar xz -C /mnt/storage \
            || fail "Unable to extract tslib tarball"
    
    echo "Updated psp" >> ${LOGFILE}

    # If OTA update, restore some files from /psp backup
    if [ "${ORIGIN}" = "USB" ]
    then
	echo "Update origin is ${ORIGIN} - not restoring /psp backup from /mnt/storage/psp.backup" | tee -a ${LOGFILE}
    else
      if [ -d /psp/install ]
      then
        # Previously we'd restore files from /mnt/storage/psp.backup - now we let install script(s)
        # handle that, and pass them the directory location.
        echo "Running install scripts in /psp/install; backup = /mnt/storage/psp.backup" | tee -a ${LOGFILE}
        for INSTALL_SCRIPT in /psp/install/*
        do
            echo "Running ${INSTALL_SCRIPT}" | tee -a ${LOGFILE}
            ${INSTALL_SCRIPT} /mnt/storage/psp.backup
        done
      else
        echo "/psp/install does not exist" | tee -a ${LOGFILE}
      fi
    fi

	# Set the tarball path so rcS.background will pick up the ball and complete
	# phase 2 of update
	echo "Saving path to ${UPDATE_FILE} for phase 2 of update" | tee -a ${LOGFILE}
	echo "${UPDATE_FILE}" > /psp/update_prepared
	sync
    

    echo "Updating bootloader" >> ${LOGFILE}

    # Update the bootloader.
${EXTRACT_CMD} ${EXTRACT_ARG} ${UPDATE_FILE} chumby_boot.bin \
        | config_util --cmd=putblock --pad --dev=/dev/mmcblk0p1 --block=boot \
            || fail "Unable to update bootloader"

    echo "Update completed" >> ${LOGFILE}

    # Updating is now complete.
    imgtool --mode=draw /bitmap/${VIDEO_RES}/rebooting.bin${BRAND}.jpg

    # If we're in the recovery partition, just reboot.
    # If we're in the active partition, swap which partition is active
    # and then reboot.
    if [ "${OTHER_ACTIVE}" -eq 0 ]
    then
	echo "Marking other partition ${OTHER_PARTITION} active" >> ${LOGFILE}
        config_util --cmd=putactive --activeflag=${OTHER_PARTITION}
    fi
    sync
    reboot
    while true; do sleep 5; done
fi




