#!/bin/bash -e

BASEDIR="$(dirname $(realpath $0))"

DEVICE=
SDBOOTIMG="$BASEDIR/../../rockdev/sdcard_full.img"
CHIP=rk3568
IMAGES="$BASEDIR/../../rockdev"
UPDATE_IMG="$BASEDIR/../../rockdev/update.img"
UPDATE_UBOOT_IMG="$BASEDIR/../../rockdev/update_uboot.img"
ROOTFS_IMG="$BASEDIR/../../rockdev/rootfs.img"

PROGRAM_IMAGE_TOOLS="$BASEDIR/../../tools/linux/programming_image_tool/programmer_image_tool"
PROGRAM_OUTPUT_IMG="$BASEDIR/../../tools/linux/programming_image_tool/out_image.bin"
TYPE="all"

function show_usage
{
        echo -e "Usage of $0:\n" \
                "    require options\n" \
                "      -d: sdcard, emmc or spinor device, \n" \
                "      -c: chip type, e.g. 'rk3128', 'rk3399'\n" \
                "    options\n" \
                "      -i: images dir, e.g. './rockdev/'\n" \
                "      -t: image type, e.g. all / uboot\n" \
                "      -h: show this usage\n"
}

#[ $(id -u) -ne 0 ] && \
#        echo "Run script as root" && exit 1
#[ ! -f $BOOT_MERGER -o ! -f $MKIMAGE ] && \
#        echo "Tools $BOOT_MERGER or $MKIMAGE is missing!!!" && exit

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
        t)      TYPE=""$OPTARG""
                ;;
        h|?)
                show_usage
                exit 1
                ;;
        esac
done

if [ $TYPE = "uboot" ]; then
        SDBOOTIMG="$BASEDIR/../../rockdev/sdcard_uboot.img"
	if [ $DEVICE = "spinor" ]; then
		SDBOOTIMG="$BASEDIR/../../rockdev/spinor_uboot.img"
	fi
else
	if [ $DEVICE = "spinor" ]; then
                SDBOOTIMG="$BASEDIR/../../rockdev/spinor_full.img"
        fi
fi
echo $SDBOOTIMG

echo "===================="
$PROGRAM_IMAGE_TOOLS -v
echo "===================="

if [ $TYPE = "uboot" ]; then
	if [ $DEVICE = "spinor" ]; then
		echo "SPI Nor flash uboot image..."
		$PROGRAM_IMAGE_TOOLS -i $UPDATE_UBOOT_IMG -t spinor
	else
		echo "EMMC or SD card uboot image..."
		$PROGRAM_IMAGE_TOOLS -i $UPDATE_UBOOT_IMG -t emmc
	fi

	echo "$PROGRAM_OUTPUT_IMG $SDBOOTIMG"
	mv $PROGRAM_OUTPUT_IMG $SDBOOTIMG
else
        if [ $DEVICE = "spinor" ]; then
                echo "SPI Nor flash full image..."
                $PROGRAM_IMAGE_TOOLS -i $UPDATE_IMG -t spinor
        else
                echo "EMMC or SD card full image..."
                $PROGRAM_IMAGE_TOOLS -i $UPDATE_IMG -t emmc
        fi
	echo "$PROGRAM_OUTPUT_IMG $SDBOOTIMG"
        mv $PROGRAM_OUTPUT_IMG $SDBOOTIMG
fi


echo "Done!"
