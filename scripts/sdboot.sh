#!/bin/bash -e

# 需要注意的几点：
# 1. 要保证ddr bin中有初始化对应的uart调试串口， 许多芯片的uart调试串口是跟sdcard的pin冲突。 ddr bin 中如果碰到从sdcard启动，并且sdcard与uart有冲突， 可能会关闭uart，这样无法继续调试。
# 2. 需要保证硬件上， sdcard的上电不依赖于软件， 如硬件上vcc sd要默认有
# 3. 要保证uboot image中有初始化sdcard， dts有使能。
# 4. 最好把emmc/nand中的固件擦除，虽然maskrom默认启动优先级是sdcard比较高， 但最好把emmc/nand先擦除
# 5. 如果由于loader不开源难调试，可以只在emmc中刷入loader， 然后其它固件放到uboot中， 这样emmc 中的loader也能加载sd card 中的固件。(仍然有前提是uart与sdcard不能冲突)

BASEDIR="$(dirname $(realpath $0))"

DEVICE=
SDBOOTIMG="$BASEDIR/../../rockdev/sdcard_full.img"
CHIP=rk3399pro
IMAGES="$BASEDIR/../../rockdev"
ROOTFS_IMG="$BASEDIR/../../rockdev/rootfs.img"

BOOT_MERGER="$BASEDIR/../tools/boot_merger_old"
echo $BOOT_MERGER
MKIMAGE="$BASEDIR/../tools/mkimage"
TYPE="all"

#Array of parts with elem in format:
#   fmt1: "size@offset@label"
#   fmt2: "-@offset@label" that size is grew
PARTITIONS=
OFFSETS=
SIZES=
LABELS=

# Input:
#    $1: parameter
function parse_parameter
{
	local para="$(realpath $1)"

	local regex="[-0x]{,2}[[:xdigit:]]*@0x[[:xdigit:]]+\([[:alpha:]]+"
	PARTITIONS=($(egrep -o "${regex}" "${para}" | sed -r 's/\(/@/g'))

	for p in ${PARTITIONS[@]}; do
		l=$(echo $p | cut -d'@' -f1)
		SIZES=(${SIZES[@]} $l)

		l=$(echo $p | cut -d'@' -f2)
		OFFSETS=(${OFFSETS[@]} $l)

		l=$(echo $p | cut -d'@' -f3)
		LABELS=(${LABELS[@]} $l)
	done
}

# Input:
#   $1: MiniloaderAll.bin
#   $2: chip type
function pack_idbloader
{
	local loader="$(realpath $1)"
	local chip=$2

	local TEMP=$(mktemp -d)
	pushd ${TEMP}
	${BOOT_MERGER} --unpack "${loader}"
	${MKIMAGE} \
		-n ${chip} \
		-T rksd \
		-d ./FlashData \
		idbloader.bin

	cat ./FlashBoot >> idbloader.bin

	popd
	mv ${TEMP}/idbloader.bin "$IMAGES/"
	rm -rf ${TEMP}

	echo "$(realpath idbloader.bin)"
}

function createIMG
{
	local rootfs_size_blk
	local rootfs_size_mb
	local last_offset_mb
	local trust_size_mb
	local trust_offset_mb
	local type=$1

	for i in ${!LABELS[@]}; do
		echo label ${LABELS[$i]} offset ${OFFSETS[$i]} size ${SIZES[$i]}
		if [ ${SIZES[$i]} = "-" ]; then
			rootfs_size_blk=$(fdisk -l ${ROOTFS_IMG} | egrep -o "[[:digit:]]+ sectors" | cut -f1 -d' ')
			SIZES[$i]=$rootfs_size_blk						# update rootfs partition size
			rootfs_size_mb=$(expr $(($rootfs_size_blk)) \* 512 \/ 1024 \/ 1024)	# blk to MB ( 1blk=512byte )
			last_offset_mb=$(expr $((${OFFSETS[$i]})) \* 512 \/ 1024 \/ 1024)	# blk to MB ( 1blk=512byte )
		fi

		if [ ${LABELS[$i]} = "trust" ]; then
			trust_size_mb=$(expr $((${SIZES[$i]})) \* 512 \/ 1024 \/ 1024)		# blk to MB ( 1blk=512byte )
			trust_offset_mb=$(expr $((${OFFSETS[$i]})) \* 512 \/ 1024 \/ 1024)	# blk to MB ( 1blk=512byte )
		fi
	done

	if [ $type = "all" ]; then
		GPT_IMAGE_SIZE=$(expr $last_offset_mb + $rootfs_size_mb + 2)
	elif [ $type = "uboot" ]; then
		GPT_IMAGE_SIZE=$(expr $trust_offset_mb + $trust_size_mb + 2)
	fi

	dd if=/dev/zero of=${SDBOOTIMG} bs=1M count=0 seek=$GPT_IMAGE_SIZE
	parted -s ${SDBOOTIMG} mklabel gpt
}

function createGPT
{
	echo "Creating GPT..."
	local type=$1

	for i in ${!LABELS[@]}; do
		local offset=${OFFSETS[$i]}
		local label=${LABELS[$i]}
		local size=${SIZES[$i]}
		echo "Create partition:$label at $offset with size $size"
		local end=$(($size + $offset))
		echo label $label end $end
		end=$((end - 1)) # [start,end], end is included
		parted -s ${SDBOOTIMG} mkpart $label $((${offset}))s $((${end}))s
		if [ $type = "uboot" -a $label = "trust" ]; then
			break
		fi
	done

	partprobe
}

function downloadImages
{
	echo "Downloading images..."
	local DEVICE=${SDBOOTIMG}
	local type=$1

	dd if=$IMAGES/idbloader.bin of=$DEVICE seek=64 conv=nocreat
	dd if=$IMAGES/parameter.txt of=$DEVICE seek=$((0x2000)) conv=nocreat
	sleep 1
	for i in ${!LABELS[@]}; do
		local label=${LABELS[$i]}
		local index=$(($i + 1))
		echo "Copy $label image to ${DEVICE} offset $((${OFFSETS[$i]}))"
		if [ -f $IMAGES/${label}.img ]; then
			dd if=$IMAGES/${label}.img of=${DEVICE} seek=$((${OFFSETS[$i]})) conv=nocreat
		else
			echo "$label image not found, skipped"
		fi

		if [ $type = "uboot" -a $label = "trust" ]; then
			break
		fi
	done

	sync && sync
}

function show_usage
{
	echo -e "Usage of $0:\n" \
		"    require options\n" \
		"      -d: sdcard device, e.g. /dev/sdc\n" \
		"      -c: chip type, e.g. 'rk3128', 'rk3399'\n" \
		"    options\n" \
		"      -i: images dir, e.g. './rockdev/'\n" \
		"      -t: image type, e.g. all / uboot\n" \
		"      -h: show this usage\n"
}

[ $(id -u) -ne 0 ] && \
	echo "Run script as root" && exit 1
[ ! -f $BOOT_MERGER -o ! -f $MKIMAGE ] && \
	echo "Tools $BOOT_MERGER or $MKIMAGE is missing!!!" && exit

while getopts 'd:c:i:t:h' OPT; do
	case $OPT in
	d)
		DEVICE="$OPTARG"
		;;
	c)
		CHIP="$OPTARG"
		;;
	i)
		IMAGES="$OPTARG"
		;;
	t)	TYPE=""$OPTARG""
		;;
	h|?)
		show_usage
		exit 1
		;;
	esac
done

#if [ ! -d "$IMAGES" -o -z "$CHIP" -o ! -b "$DEVICE" ]; then
#	show_usage
#
#	echo -e "Invalid images dir : $IMAGES, or\n" \
#		"Invalid chip type : $CHIP, or\n" \
#		"Invalid sdcard device: $DEVICE \n"
#	exit 1
#fi

# DEVICE must be a removable device, check before completely destory it
#REMOVABLE=$(cat /sys/block/$(echo $DEVICE | cut -d'/' -f3)/removable)
#if [ 0 -eq $REMOVABLE ]; then
#	echo "Be careful, you're try to destory your disk: $DEVICE"
#	exit
#fi

if [ $TYPE = "uboot" ]; then
	SDBOOTIMG="$BASEDIR/../../rockdev/sdcard_uboot.img"
fi
echo $SDBOOTIMG

parse_parameter $IMAGES/parameter.txt

pack_idbloader "$IMAGES/Mini[Ll]oader[Aa]ll.bin" $CHIP

createIMG $TYPE

createGPT $TYPE

downloadImages $TYPE

echo "Done!"
