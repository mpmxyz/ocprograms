#!/bin/sh
####################################################
#name       : tarall.sh
#description: creates tar archives for the sub projects
#author     : mpmxyz
#github page: https://github.com/mpmxyz/ocprograms
#forum page : none
####################################################

#reminder: just execute "sh < tarall.sh" when using windows file system...
##complete package
tar --numeric-owner -cf tars/all.tar bios boot home pids usr lib
tar --numeric-owner -cf tars/pids.tar pids
tar --numeric-owner -cf tars/bios.tar bios
tar --numeric-owner -cf tars/boot.tar boot
tar --numeric-owner -cf tars/home.tar home
tar --numeric-owner -cf tars/usr.tar usr
tar --numeric-owner -cf tars/lib.tar lib
##smaller packages
#tar.tar
tar --numeric-owner -cf tars/tar.tar home/bin/tar.lua home/lib/mpm/auto_progress.lua usr/man/tar.man
#purgelib.tar
tar --numeric-owner -cf tars/purgelib.tar home/bin/purgelib.lua usr/man/purgelib.man
#crunch.tar
tar --numeric-owner -cf tars/crunch.tar home/bin/crunch.lua home/lib/mpm/cache.lua home/lib/mpm/lib.lua home/lib/mpm/hashset.lua home/lib/mpm/sets.lua home/lib/mpm/setset.lua home/lib/crunch home/lib/parser usr/man/crunch.man
#qui.tar
tar --numeric-owner -cf tars/qui.tar home/bin/quidemo.lua home/lib/mpm/values.lua home/lib/mpm/qui.lua home/lib/mpm/quidgets.lua home/lib/mpm/qselect.lua home/lib/mpm/qevent.lua home/lib/mpm/stack.lua home/lib/mpm/textgfx.lua
#pid.tar
tar --numeric-owner -cf tars/pid.tar home/bin/pid.lua home/bin/gpid.lua home/lib/pid.lua home/lib/mpm/values.lua home/lib/mpm/libarmor.lua home/lib/mpm/qui.lua home/lib/mpm/quidgets.lua home/lib/mpm/qselect.lua home/lib/mpm/qevent.lua home/lib/mpm/stack.lua home/lib/mpm/textgfx.lua usr/man/pid.man
#cbrowse.tar
tar --numeric-owner -cf tars/cbrowse.tar home/bin/cbrowse.lua home/lib/mpm/tables.lua home/lib/mpm/draw_buffer.lua home/lib/mpm/component_filter.lua home/lib/mpm/config.lua home/lib/mpm/cache.lua home/lib/mpm/lib.lua home/lib/mpm/values.lua usr/man/cbrowse.man
#devfs.tar
tar --numeric-owner -cf tars/devfs.tar boot/98_devfs.lua lib/devfs lib/drivers
