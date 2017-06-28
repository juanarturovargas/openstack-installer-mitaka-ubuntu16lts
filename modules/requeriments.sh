#!/bin/bash

#
# OpenStack Installer
# OpenStack MITAKA for Ubuntu 16.04lts
#

PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
#
# Como primer punto se requiere el script de configuracion
# Existen dos archivos 3 de configuracion, el primero es controller-config.rc
# El segundo es el compute-config.rc y el tercero es el main-config.rc
# En el tercer archivo se indica si se va a instalar un controlador o un nodo de computo.


# Validar el archivo principal de configuracion
if [ -f ./configs/main-config.rc ]
then
	source ./configs/main-config.rc
	mkdir -p /etc/openstack-control-script-config
else
	echo "Can't access my config file. Aborting !"
	echo ""
	exit 0
fi

# Validar si existe el archivo de configuración del controller
if [ -f ./configs/controller-config.rc ] then
	if [ -f ./configs/controller-config.rc ] then
		source ./configs/main-config.rc
		mkdir -p /etc/openstack-control-script-config
	else
		echo "Can't access my config file. Aborting !"
		echo ""
		exit 0
	fi
fi


# Limpieza de archivos temporales.
rm -rf /tmp/keystone-signing-*
rm -rf /tmp/cd_gen_*

# Ejeción de validaciones
export DEBIAN_FRONTEND=noninteractive

DEBIAN_FRONTEND=noninteractive apt-get -y install aptitude

osRepositoryInstalled=`aptitude search python-openstackclient|grep python-openstackclient|head -n1|wc -l`
userIsRoot=`whoami|grep root|wc -l`
systemOperationVersion=`cat /etc/lsb-release|grep DISTRIB_DESCRIPTION|grep -i ubuntu.\*16.\*LTS|head -n1|wc -l`
internalNetworkBridgePresent=`ovs-vsctl show|grep -i -c bridge.\*$integration_bridge`
kernel64installed=`uname -p|grep x86_64|head -n1|wc -l`


echo "************Inician las validaciones*********************"

# Validar la verón del sistema operativo
if [ $systemOperationVersion == "1" ] then
	echo "Version del sistema operativo correcta: [UBUNTU 16.04 LTS O/S]"
else
	echo "La version del sistema operativo no es la correcta. [El proceso es Abortado]"
	exit 0
fi

# Validar si el instalador se ejecuta con el usuario root.
if [ $userIsRoot == "1" ] then
	echo "El usuario de ejecucion es el correcto: [root]"
else
	echo "El instalador no se esta ejecutando con root: [Proceso de instalación es Abortado]"
	exit 0
fi

# Validar si el kernel es x86_64 (amd64)
if [ $kernel64installed == "1" ] then
	echo "El Kernel instalado es x86_64 (amd64): [La versión de Kernel es correcta]"
else
	echo "El sistema no cuenta con Kernel x86_64: [Proceso de instalación es Abortado]"
	exit 0
fi

echo "*********El proceso de validación ha terminado: [Se continua con la instalación]***********"

if [ $osRepositoryInstalled == "1" ]
then
	echo "OK - El repositorio de OpenStack MITAKA esta disponible para su instalación"
else
	echo "ERROR - OpenStack MITAKA Unavailable. Aborting !"
	exit 0
fi

searchCeilometer=`aptitude search ceilometer-api|grep -ci "ceilometer-api"`
if [ $searchCeilometer == "1" ] then
echo "OK - Repositorio de Ceilometer verificado: [Repositorio de Ceilometer localizado]"
else
	echo "ERROR - El repositorio de Ceilometer no esta instalado: [Error al buscar el repositorio de ceilometer]"
	exit 0
fi


if [ $internalNetworkBridgePresent == "1" ] then
	echo "Integration Bridge Present"
else
	echo "Integration Bridge NOT Present. Aborting !"
	exit 0
fi

echo "Installing initial packages"
echo ""

#
# We proceed to install some initial packages, some of then non-interactivelly
#

apt-get -y update

apt-get -y install crudini python-iniparse debconf-utils

echo "libguestfs0 libguestfs/update-appliance boolean false" > /tmp/libguest-seed.txt
debconf-set-selections /tmp/libguest-seed.txt

DEBIAN_FRONTEND=noninteractive aptitude -y install pm-utils saidar sysstat iotop ethtool iputils-arping libsysfs2 btrfs-tools \
	cryptsetup cryptsetup-bin febootstrap jfsutils libconfig8-dev \
	libcryptsetup4 libguestfs0 libhivex0 libreadline5 reiserfsprogs scrub xfsprogs \
	zerofree zfs-fuse virt-top curl nmon fuseiso9660 libiso9660-8 genisoimage sudo sysfsutils \
	glusterfs-client glusterfs-common nfs-client nfs-common libguestfs-tools

rm -r /tmp/libguest-seed.txt

#
# Then we proceed to configure Libvirt and iptables, and also to verify proper installation
# of libvirt. If that fails, we stop here !
#

if [ -f /etc/openstack-control-script-config/libvirt-installed ]
then
	echo "Pre-requirements already installed"
else
	echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" > /tmp/iptables-seed.txt
	echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" >> /tmp/iptables-seed.txt
	debconf-set-selections /tmp/iptables-seed.txt
	DEBIAN_FRONTEND=noninteractive aptitude -y install iptables iptables-persistent
	/etc/init.d/netfilter-persistent flush
	/etc/init.d/netfilter-persistent save
	update-rc.d netfilter-persistent enable
	systemctl enable netfilter-persistent
	/etc/init.d/netfilter-persistent save
	rm -f /tmp/iptables-seed.txt
	killall -9 dnsmasq > /dev/null 2>&1
	killall -9 libvirtd > /dev/null 2>&1
	DEBIAN_FRONTEND=noninteractive aptitude -y install qemu kvm qemu-kvm libvirt-bin libvirt-doc
	rm -f /etc/libvirt/qemu/networks/default.xml
	rm -f /etc/libvirt/qemu/networks/autostart/default.xml
	# /etc/init.d/libvirt-bin stop
	# update-rc.d libvirt-bin enable
	systemctl stop libvirt-bin stop
	systemctl enable libvirt-bin
	ifconfig virbr0 down
	DEBIAN_FRONTEND=noninteractive aptitude -y install dnsmasq dnsmasq-utils
	/etc/init.d/dnsmasq stop
	systemctl disable dnsmasq
	update-rc.d dnsmasq disable
	killall -9 dnsmasq > /dev/null 2>&1
	killall -9 libvirtd > /dev/null 2>&1
	sed -r -i 's/ENABLED\=1/ENABLED\=0/' /etc/default/dnsmasq
	/etc/init.d/netfilter-persistent flush
	iptables -A INPUT -p tcp -m multiport --dports 22 -j ACCEPT
	/etc/init.d/netfilter-persistent save
	/etc/init.d/libvirt-bin start

	sed -i.ori 's/#listen_tls = 0/listen_tls = 0/g' /etc/libvirt/libvirtd.conf
	sed -i 's/#listen_tcp = 1/listen_tcp = 1/g' /etc/libvirt/libvirtd.conf
	sed -i 's/#auth_tcp = "sasl"/auth_tcp = "none"/g' /etc/libvirt/libvirtd.conf
	# sed -i.ori 's/libvirtd_opts="-d"/libvirtd_opts="-d -l"/g' /etc/default/libvirt-bin
	cat /etc/default/libvirt-bin > /etc/default/libvirt-bin.BACKUP
	echo "start_libvirtd=\"yes\"" > /etc/default/libvirt-bin
	echo "libvirtd_opts=\"-d -l\"" >> /etc/default/libvirt-bin

	# /etc/init.d/libvirt-bin restart
	systemctl stop libvirt-bin
	killall -9 dnsmasq > /dev/null 2>&1
	killall -9 libvirtd > /dev/null 2>&1
	systemctl start libvirt-bin

	iptables -A INPUT -p tcp -m multiport --dports 16509 -j ACCEPT
	/etc/init.d/netfilter-persistent save
	
	#implementación de Linux Security Module
	#https://help.ubuntu.com/lts/serverguide/apparmor.html
	apt-get -y install apparmor-utils
	# aa-disable /etc/apparmor.d/usr.sbin.libvirtd
	# /etc/init.d/libvirt-bin restart
	chmod 644 /boot/vmlinuz-*
fi


# KSM Tuned:
# https://launchpad.net/ubuntu/xenial/+package/ksmtuned
# enables and tunes Kernel Samepage Merging
aptitude -y install ksmtuned
systemctl enable ksmtuned
systemctl restart ksmtuned


testlibvirt=`dpkg -l libvirt-bin 2>/dev/null|tail -n 1|grep -ci ^ii`

if [ $testlibvirt == "1" ]then
	echo "OK - Libvirt se instalo correctamente"
	date > /etc/openstack-control-script-config/libvirt-installed
else
	echo ""
	echo "ERROR - Fallo la instalación de Libvirt [Instalacion abortada]"
	exit 0
fi

