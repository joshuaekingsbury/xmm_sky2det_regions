#!/bin/bash

## Currently runs from placing inside analysis directory
## Takes two arguments; xxxxxxxx-obj-image-sky-fits, ds9 region file in [DS9/Funtools, CIAO, SAOtng] formats
## Third optional argument is output file name (expected without file extension!)
## Output are two region files in detector coordinates
##  -outfile.reg (DS9 formatted)
##  -outfile.txt (XMM formatted)

## Pre-reqs
# bc - Basic Calculator 1.07.1
# wcstools 3.9.5

## Make sure to have SAS paths set appropriately
## SAS_CCFPATH, SAS_CCF and SAS_ODF

####
## Example
####

## ds9.reg contains the region:
##  box(9:56:35.9111,+69:36:53.095,656.723",85.926",320.71996) # color=white width=4

## [USER analysis]$ ./sky2det.sh mos1S001-obj-image-sky.fits ds9.reg

## Output detector regions in files
## outfile.reg:
##  box(596.9,-6683.9,13134.4599958949,1718.5199975862,358.561930869141) # color=white width=4
## outfile.txt:
##  &&((DETX,DETY) IN box(596.9,-6683.9,13134.4599958949,1718.5199975862,358.561930869141))

####
##  Setup inputs, outputs, and get necessary values from fits file header
####

skyfile=$1 # (./mos1S001-obj-image-sky.fits)
inreg=$2 # Region file in a ds9 fk5 format (./cap1.reg)
det=$(gethead INSTRUME "$skyfile")
det_lower=$(echo "$det" | tr '[:upper:]' '[:lower:]')
expid=$(gethead EXPIDSTR "$skyfile")
outreg=${3-"${det_lower:1}$expid"}

# Create/overwrite region files
> "$outreg.txt"
> "$outreg.reg"

# For finding relative rotation angle
position_angle=$(gethead PA_PNT "$skyfile")

# For scaling shapes appropriately
#deg_per_pixel=$(gethead REFXCDLT "$skyfile")
deg_per_pixel=$(gethead REFYCDLT "$skyfile")
## Header returns value in scientific notation; bc cannot interpret
## Using awk and printf as suggested here: https://stackoverflow.com/a/12882612
deg_per_pixel=$(echo "$deg_per_pixel" | awk '{printf("%.15f\n", $1)}')
# echo $deg_per_pixel

####
##  A slew of helper functions
####

function xms2decimal(){
    local xms=$1
    #echo $xms

    # Get leading value (degree or hour) by trimming everything after/including first ":"
    local decimal=${xms%%:*}
    #echo $decimal

    # Update xms by trimming leading value including first ":"
    local xms=${xms#*:} # xms should now be just minutes and seconds
    #echo $xms
    #echo ${xms%%:*}

    # Use bc to accomplish floating-point arithmetic
    # Take the minutes value, divide by 60, and add to the decimal
    local decimal=$(echo "scale=10; $decimal+${xms%%:*}/60.0" | bc -q)
    #echo $decimal

    local xms=${xms#*:} # xms should now be just seconds

    # Take the seconds value, divide by 60, and add to the decimal
    local decimal=$(echo "scale=10; $decimal+${xms%%:*}/3600.0" | bc -q)

    echo "$decimal"
}
#xms2decimal "69:50:32.120"

function hr2deg(){
    local deg=$(echo "scale=10; $1*15.0" | bc -ql)
    echo "$deg"
}

function ra_hr2deg_decimal(){
    local decimal=$(xms2decimal $1)
    local decimal=$(hr2deg $decimal)
    echo "$decimal"
}

function dec_deg_decimal(){
    local dms=$1

    local sign=${dms:0:1}
    
    ## Save sign
    if [[ "$sign" != "+" && "$sign" != "-" ]]; then
        local sign=""
    fi

    ## Strip sign from front if it exists
    local decimal=${dms#*"$sign"}
    ## Convert to decimal
    local decimal=$(xms2decimal $decimal)

    echo "$sign$decimal"
}
# ra_hr2deg_decimal 9:55:2.6666
#dec_deg_decimal -9:55:2.6666
#dec_deg_decimal +69:50:32.120

function arcsec2arcsec(){
    local arcsec="${1%%\"*}" # Removes arcsecond '"' mark if included
    echo "$arcsec"
}
#arcsec2arcsec 111.974

function arcsec2arcmin(){
    local arcsec=$(arcsec2arcsec "$1") # Removes arcsecond '"' mark if included
    local arcmin=$(echo "scale=10; $arcsec/60.0" | bc -q)
    echo "$arcmin"
}
#arcsec2arcmin "180.5\""

function arcmin2degree(){
    local arcmin="${1%%\'*}"
    local degree=$(echo "scale=10; $arcmin/60" | bc -q)
    echo "$degree"
}
#arcmin2degree 1.866233333

# Give sky2det conversion output string; return comma separated string (CSS)
function det_str2css(){
    local det_str=$1
    #local css=$(echo ${det_str// /,})
    #local css=$(echo "$det_str" | sed 's/ /,/g')
    local css=$(echo "$det_str" | awk -v OFS="," '$1=$1')
    echo "$css"
}
#det_str2css "eats shoots n'leaves" # Description of a panda

function sky2det_coord(){
    local det_coord_str=$(esky2det datastyle=user ra=$1 dec=$2 instrument=$det checkfov=no outunit=det withheader=no calinfostyle=set calinfoset=$skyfile verbosity=0)
    local det_coord_str=$(det_str2css "$det_coord_str")

    echo "$det_coord_str"
}
#sky2det_coord 148.5 69.999

function sky2det_rot(){
    local position_angle=$1
    local sky_reg_angle=$2

    #local det_reg_angle=$(echo "scale=0; ($det_reg_angle+90.0)%360.0" | bc -q)
    local det_reg_angle=$(echo "scale=10; $position_angle-$sky_reg_angle" | bc -q)
    
    ## Next make sure is within [0,360]; Assuming both inputs are always each [0,360]
    ## Add 360 and then take remainder in case value is negative
    local det_reg_angle=$(echo "scale=0; ($det_reg_angle+360.0)%360.0" | bc -q)
    local det_reg_angle=$(echo "scale=10; 360.0-$det_reg_angle" | bc -q)
    
    echo "$det_reg_angle"
}
#sky2det_rot 319.15689 315

function angular2degree(){
    local angular=$1
    if [[ "$angular" == *"'"* ]]; then
        local degree=$(arcmin2degree "$angular")
    else
        local arcmin=$(arcsec2arcmin "$angular")
        local degree=$(arcmin2degree "$arcmin")
    fi
    echo "$degree"
}

function degree2pixel(){
    local degree=$1
    local degree_per_pixel=$2
    local pixels=$(echo "scale=10; $degree/$degree_per_pixel" | bc -q)
    echo "$pixels"
}
#echo $deg_per_pixel
#degree2pixel 0.0311 $deg_per_pixel

function arcsec2pixel(){
    local arcsec=$1
    local arcmin=$(arcsec2arcmin "$arcsec")
    local degree=$(arcmin2degree "$arcmin")

    local degree_per_pixel=$2

    local pixels=$(degree2pixel $degree $degree_per_pixel)
    echo "$pixels"
}
#arcsec2pixel 111.974 $deg_per_pixel

####
##  Begin reading file, converting regions, and writing out region-by-region
####

line_num=0

while read -r line
do
    line_num=$((line_num+=1))

    ## Removes header line and any other comment lines
    ## Removes parenthesis containing line in header of SAOtng region format
    if [[ "${line:0:1}" == "#" ]]; then
        echo "***Skipping line $line_num as comment (#)"
        continue
    fi

    ## Assuming only remaining lines from ds9 formats (non-image; non-xy) are regions
    if [[ "${line}" != *"("* ]]; then
        echo "***Skipping line $line_num without \"(\""
        continue
    fi

    ## Now only lines containing regions should be read
    exclude=false
    sign=""
    shape=""
    shape_params=""
    fmt=""

    det_coords_str=""
    det_reg_str_ds9=""
    det_reg_str_xmm=""

    ## If line start with box,circle,ellipse,-,!
    if [[ "${line:0:1}" == "-" || "${line:0:1}" == "!" ]]; then
        exclude=true
        sign="${line:0:1}"
        line="${line#*"$sign"}" #Trim exclude character
    fi

    shape="${line%"("*}"
    ## Trim leading "+" from shape in case of SAOtng format regions
    shape="${shape#*"+"}"

    fmt="${line#*")"}"
    #echo $shape
    #echo $fmt

    line="${line#*"("}" # Everything right of first "("
    line="${line%")"*}" # Everything left of last ")"

    #echo ${line%%","*}
    ## Assuming first two values inside () are ra and dec; extract and convert to decimal
    ra_hms="${line%%","*}"
    ra=$(ra_hr2deg_decimal "${line%%","*}"); line="${line#*","}"
    dec_dms="${line%%","*}"
    dec=$(dec_deg_decimal "${line%%","*}"); line="${line#*","}"
    #echo "$ra_hms;$ra"; echo "$dec_dms;$dec"; echo $line

    det_coords=$(sky2det_coord $ra $dec)

    ## esky2det spits outs strings of "*" if it fails to find a proper conversion
    ## If not accounted for the "*" can expand later into a list of files in directory and break code
    ## If found, then skip the current region
    if [[ "$det_coords" == *"*"* ]]; then
        echo "The detector coordinates for $ra_hms;$ra and $dec_dms;$dec are supposedly out-of-bounds of detector."
        echo "Skipping region on line $line_num."
        continue
    fi

    det_x="${det_coords%%","*}"
    det_y="${det_coords#*","}"
    #echo $det_coords; echo $det_x; echo $det_y


    # Making uniform lowercase for matching
    shape=$(echo "$shape" | tr '[:upper:]' '[:lower:]')
    #echo $shape

    if [[ "$shape" == "circle" ]]; then
        ## CIRCLE; RADIUS(as)
        #radius_as=$(arcsec2arcsec "${line%%","*}")

        radius=$(angular2degree "${line%%","*}")
        radius_pixels=$(degree2pixel "$radius" "$deg_per_pixel")

        #conv_reg mode=2 imagefile=$skyfile ra=$ra dec=$dec radius=$radius
        #converted_str=$(conv_reg mode=3 imagefile=$skyfile ra=$ra dec=$dec radius=$radius)
        #det_coord_str=$(esky2det datastyle=user ra=$ra dec=$dec instrument=$det checkfov=no outunit=det withheader=no calinfostyle=set calinfoset=$skyfile verbosity=0)
        #det_coord_str=$(det_str2css "$det_coord_str")
        
        shape_params="$radius_pixels"

    elif [[ "$shape" == "ellipse" ]]; then
        ## ELLIPSE; SEMI_A(as),SEMI_B(as),ROTATION(deg) 
        semi_a=$(angular2degree "${line%%","*}"); line="${line#*","}"
        semi_b=$(angular2degree "${line%%","*}"); line="${line#*","}"

        semi_a_pixels=$(degree2pixel "$semi_a" "$deg_per_pixel")
        semi_b_pixels=$(degree2pixel "$semi_b" "$deg_per_pixel")
        rotation=$(sky2det_rot "${line%%","*}" "$position_angle")

        shape_params="$semi_a_pixels,$semi_b_pixels,$rotation"

    elif [[ "$shape" == "box" ]]; then
        ## BOX; WIDTH(as),HEIGHT(as),ROTATION(deg)
        width=$(angular2degree "${line%%","*}"); line="${line#*","}"
        height=$(angular2degree "${line%%","*}"); line="${line#*","}"

        width_pixels=$(degree2pixel "$width" "$deg_per_pixel")
        height_pixels=$(degree2pixel "$height" "$deg_per_pixel")
        rotation=$(sky2det_rot "${line%%","*}" "$position_angle")

        shape_params="$width_pixels,$height_pixels,$rotation"

    else
        echo "Not circle, ellipse, or box. Skipping region."
        continue
    fi

    ## ds9 Region str
    det_reg_str_ds9="$sign$shape($det_x,$det_y,$shape_params)$fmt"
    echo $det_reg_str_ds9

    echo "$det_reg_str_ds9" >> "$outreg.reg"

    ## xmmselect Region str
    if [[ "$sign" == "-" ]]; then
        sign="!"
    fi

    #shape_params=$(echo "$shape_params" | sed 's/,/ /g') # To split up comma separated into space separated
    
    det_reg_str_xmm="&&$sign((DETX,DETY) IN $shape($det_x,$det_y,$shape_params))"
    echo $det_reg_str_xmm

    echo "$det_reg_str_xmm" >> "$outreg.txt"

    ## Expected input/outputs
    #-circle(9:56:50.9163,+69:50:32.120,111.974")
    #-circle(12422.0,4758.4,2239.4799935820) 
    #&&!((DETX,DETY) IN circle(12422.0,4758.4,2239.4799935820))


    #echo "$line"
done < "$inreg"