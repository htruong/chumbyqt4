Huan's Public Qt4 Webkit Chumby release
=============

You would have to do all the customizations on on-device folder. The launcher is just a webkit shell, by default, it just displays http://127.0.0.1/cgi-bin/custom/index.cgi which happens to point to /psp/cgi-bin/index.cgi.

Edit network_config for your wifi network if you want to connect the Chumby to your wifi network.

Then, use ./repack-update.sh to pack the new update pack, it will unpack the usual chumby stuff overlay our customizations on top of it.

Copy the copy-to-flash-drive folder to the ROOT of a USB flash drive.

Plug the USB flash drive to the back of the chumby and press THE SCREEN when the chumby is booting up. You'll be presented with a choice of upgrading the chumby. Enjoy.

