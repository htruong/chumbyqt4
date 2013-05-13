#!/bin/bash

echo "Repacking chumby update file PLZ WAI"

echo " -> Unpacking original update package"
mkdir on-flash-drive
cd on-flash-drive
tar -xzf ../update-orig.tgz

echo " -> Unpacking psp folder"
mkdir psp
cd psp
tar -xzf ../psp.tar.gz

echo " -> Applying PSP Overlay"
cp -R ../../on_device/psp/ ..
GZIP=-1 tar -czf ../psp.tar.gz . 

cd ..
rm -rf psp

echo " -> Adding additional libs"

cp ../on_device/*.tar.gz .

echo " -> Replacing updater script"

cp ../on_device/updater.sh .

echo " -> Repacking update package"

GZIP=-1 tar -czf ../update.tgz *

cd ..
rm -rf on-flash-drive

echo "Now you're good to go. Copy update.tgz to your usb flash drive and press screen while starting up the chumb to update :-)"

