#!/bin/sh

###############################################################################
# Script for computing and plotting Coulomb stress changes generated by an
# earthquake in an elastic half-space on a vertical cross-section perpendicular
# to the strike of the earthquake.
###############################################################################

gmt set PS_MEDIA 11x17

if [ ! -f no_green_mwh.cpt ]; then
cat > no_green_mwh.cpt << EOF
# Color table using in Lab for Satellite Altimetry
# For folks who hate green in their color tables
# Designed by W.H.F. Smith, NOAA
# Modified to make small values white
-32     32/96/255       -28     32/96/255
-28     32/159/255      -24     32/159/255
-24     32/191/255      -20     32/191/255
-20     0/207/255       -16     0/207/255
-16     42/255/255      -12     42/255/255
-12     85/255/255      -8      85/255/255
-8      127/255/255     -3.2    127/255/255
-3.2    255/255/255     0       255/255/255
0       255/255/255     3.2     255/255/255
3.2     255/240/0       8       255/240/0
8       255/191/0       12      255/191/0
12      255/168/0       16      255/168/0
16      255/138/0       20      255/138/0
20      255/112/0       24      255/112/0
24      255/77/0        28      255/77/0
28      255/0/0         32      255/0/0
B       32/96/255
F       255/0/0
EOF
fi

###############################################################################
# The user can specify the following variables:
#  PSFILE   Name of the output PostScript file
#  NN[XY]   Density of the computation grid (NNX x NNY)
#  THR      Threshold value for slip in FFM (fraction of maximum slip)
###############################################################################

# Name of output PostScript file
PSFILE="coul_xsec.ps"

# Coulomb stress grid is (NN x NN) points
NNX="150"
NNY="100"
#NNX="50"
#NNY="50"

# Threshold percentage of peak slip in FFM to be retained
THR="0.15"

###############################################################################
#	PARSE COMMAND LINE TO GET SOURCE TYPE AND FILE NAME
###############################################################################

function USAGE() {
echo
echo "Usage: coul_xsec.sh SRC_TYPE SRC_FILE [-Rl/r/t/b] [-Ts/d/r] [-Plo/la|peak]"
echo "    SRC_TYPE     Either MT (moment tensor) or FFM (finite fault model)"
echo "    SRC_FILE     Name of input file"
echo "                   MT:  EVLO EVLA EVDP STR DIP RAK MAG"
echo "                   FFM: finite fault model in subfault format"
echo "    -Rl/r/t/b    Define limits, positive depth down (optional)"
echo "    -Ts/d/r      Define target fault strike/dip/rake (optional)"
echo "    -Plo/la|peak Define cross-section origin coordinates or \"peak\"" 
echo "                   to use peak slip location (default uses epicenter)"
echo 
exit
}
# Check for minimum number of required arguments
if [ $# -lt 2 ]
then
    echo "!! Error: SRC_TYPE and SRC_FILE arguments required"
    echo "!!        Map limits (-Rw/e/s/n) and target kinematics (str/dip/rak) optional"
    USAGE
fi
SRC_TYPE="$1"
SRC_FILE="$2"
# Check that source type is correct
if [ $SRC_TYPE != "FFM" -a $SRC_TYPE != "MT" ]
then
    echo "!! Error: source type must be FFM or MT"
    USAGE
fi
# Check that input file exists
if [ ! -f $SRC_FILE ]
then
    echo "!! Error: no source file $SRC_FILE found"
    USAGE
fi
# Parse optional arguments
LIMS=""
TSTR=""
TDIP=""
TRAK=""
LON0=""
LAT0=""
shift;shift
while [ "$1" != "" ]
do
    case $1 in
        -R*) LIMS="$1"
             ;;
        -T*) TSTR=`echo $1 | sed -e "s/-T//" | awk -F"/" '{print $1}'`
             TDIP=`echo $1 | sed -e "s/-T//" | awk -F"/" '{print $2}'`
             TRAK=`echo $1 | sed -e "s/-T//" | awk -F"/" '{print $3}'`
             ;;
        -P*) LON0=`echo $1 | sed -e "s/-P//" | awk -F"/" '{print $1}'`
             LAT0=`echo $1 | sed -e "s/-P//" | awk -F"/" '{print $2}'`
             ;;
          *) echo "!! Error: no option \"$1\""
             USAGE
             ;;
    esac
    shift
done

###############################################################################
###############################################################################
# Everything below this point should be automated. This script requires the
# tools O92UTIL and GRID from Matt's codes, and creates the figure using
# GMT 5 commands. All of the work is performed in the same directory that
# the script is run from.
###############################################################################
###############################################################################

#####
#       INPUT FILES FOR COULOMB STRESS CALCULATION
#####
if [ $SRC_TYPE == "FFM" ]
then
    # Copy FFM to new file name
    cp $SRC_FILE ./ffm.dat
    # Simplify FFM by removing slip smaller than minimum threshold
    # percentage of maximum slip (THR*MAXSLIP)
    MAXSLIP=`awk '{if(substr($1,1,1)!="#" && NF>3){print $4}}' ffm.dat |\
             gmtinfo -C -I0.01 | awk '{print $2}'`
    awk '{
      if (substr($1,1,1)!="#" && NF>3 && $4<'"$MAXSLIP"'*'"$THR"')
        {print $1,$2,$3,0,$5,$6,$7,$8,$9,$10,$11}
      else
        {print $0}
    }' ffm.dat > t
    mv t ffm.dat
else
    # Copy MT to new file name
    cp $SRC_FILE ./mt.dat
fi

# Elastic half-space properties
LAMDA="4e10" # Lame parameter
MU="4e10"    # Shear modulus
echo "Lame $LAMDA $MU" > haf.dat

# Target fault geometry, orientation and reference point for cross section
if [ $SRC_TYPE == "FFM" ]
then
    # Use slip-weighted strike and dip for target faults (and cross-section azimuth)
    awk 'BEGIN{n=0;s=0;d=0;r=0;z=0;u=0}
         {u=$4;n=n+u;s=s+u*$6;d=d+u*$7;r=r+u*$5;z=z+u*$3}
         END{print z/n,s/n,d/n,r/n}' ffm.dat > junk
    Z=`awk '{printf("%12.0f"),$1}' junk | awk '{print $1}'`
    if [ -z $TRAK ]
    then
        TSTR=`awk '{printf("%12.0f"),$2}' junk | awk '{print $1}'`
        TDIP=`awk '{printf("%12.0f"),$3}' junk | awk '{print $1}'`
        TRAK=`awk '{printf("%12.0f"),$4}' junk |\
              awk '{if(0<$1&&$1<180||$1>360){print 90}else{print -90}}'`
        echo "Automatic target kinematics: $TSTR $TDIP $TRAK"
    else
        echo "Using target kinematics from command line: $TSTR $TDIP $TRAK"
    fi
    if [ -z $LON0 ]
    then
        # Use epicenter as cross-section origin
        LON0=`sed -n -e "3p" ffm.dat | sed -e "s/.*Lon:/Lon:/" | awk '{print $2}'`
        LAT0=`sed -n -e "3p" ffm.dat | sed -e "s/.*Lon:/Lon:/" | awk '{print $4}'`
        echo "Using epicenter as origin: $LON0 $LAT0"
        TXT="e"
    elif [ -z $LAT0 ]
    then
        # Use peak slip as cross-section origin
        MAXLN=`awk 'BEGIN{max=0}
                    {if(substr($1,1,1)!="#"&&NF>3){if($4>max){max=$4;line=NR}}}
                    END{print line}' ffm.dat`
        LON0=`sed -n -e "${MAXLN}p" ffm.dat | awk '{printf("%12.2f"),$2}' | awk '{print $1}'`
        LAT0=`sed -n -e "${MAXLN}p" ffm.dat | awk '{printf("%12.2f"),$1}' | awk '{print $1}'`
        echo "Using peak slip as origin: $LON0 $LAT0"
        TXT="p"
    else
        echo "Origin from command line: $LON0 $LAT0"
        TXT="c"
    fi
    rm junk
else
    Z=`awk '{print $3}' mt.dat`
    if [ -z $TRAK ]
    then
        TSTR=`awk '{print $4}' mt.dat`
        TDIP=`awk '{print $5}' mt.dat`
        TRAK=`awk '{print $6}' mt.dat`
    else
        echo "Using target kinematics from command line: $TSTR $TDIP $TRAK"
    fi
    LON0=`awk '{print $1}' mt.dat`
    LAT0=`awk '{print $2}' mt.dat`
fi
AZ=`echo $TSTR | awk '{if(-90<=$1&&$1<90||$1>=270){print $1+90}else{print $1-90}}'`
DIPD=`echo $TSTR | awk '{if(-90<=$1&&$1<90||$1>=270){print "R"}else{print "L"}}'`
FRIC="0.4"
echo $TSTR $TDIP $TRAK $FRIC > trg.dat

#####
#       SET UP COMPUTATION GRID
#####
# Cross-section limits
if [ -z $LIMS ]
then
    if [ $SRC_TYPE == "FFM" ]
    then
        MAXSLIP=`awk '{if(substr($1,1,1)!="#"&&NF>3){print $4}}' ffm.dat |\
                 gmtinfo -C -I1 | awk '{print $2/100}'`
    else
        MAXSLIP=`awk '{print ((10^(1.5*($7+10.7)))*1e-7/4e10*1e-6)^(1/3)/4}' mt.dat |\
                 gmtinfo -C -I1 | awk '{print $2}'`
    fi
    MX=`echo $MAXSLIP | awk '{print 200+$1*15}' |\
        gmtinfo -C -I50 | awk '{if($2>750){print 750}else{print $2}}'`
    L="-$MX"
    R="$MX"
    B=`echo $Z | awk '{if($1>75){print $1+75}else{print 150}}'`
    T=`echo $Z | awk '{if($1>75){print $1-75}else{print 0}}'`
else
    L=`echo $LIMS | sed -e "s/\// /g" -e "s/-R//" | awk '{print $1}'`
    R=`echo $LIMS | sed -e "s/\// /g" -e "s/-R//" | awk '{print $2}'`
    T=`echo $LIMS | sed -e "s/\// /g" -e "s/-R//" | awk '{print $3}'`
    B=`echo $LIMS | sed -e "s/\// /g" -e "s/-R//" | awk '{print $4}'`
    T=`echo $T $B | awk '{if($1>$2){print $2,$1}else{print $1,$2}}'`
    B=`echo $T | awk '{print $2}'`
    T=`echo $T | awk '{print $1}'`
    echo "Using map limits from command line: $L $R $T $B"
fi

# Create (NNX x NNY) point cross-section grid
grid -x $L $R -nx $NNX -y $T $B -ny $NNY -xsec $LON0 $LAT0 $AZ -o sta.dat
grid -x $L $R -nx $NNX -y $T $B -ny $NNY -xsec $LON0 $LAT0 $AZ -o staxz.dat -xz

#####
#	COMPUTE COULOMB STRESS CHANGE
#####
if [ $SRC_TYPE == "FFM" ]
then
    o92util -ffm ffm.dat -sta sta.dat -haf haf.dat -trg trg.dat -coul coul.out -prog
else
    o92util -mag mt.dat -sta sta.dat -haf haf.dat -trg trg.dat -coul coul.out -prog -gmt rect.out
fi

#####
#	PLOT RESULTS
#####
SCL="0.010"
WID=`echo $L $R $SCL | awk '{print ($2-$1)*$3}'`
PROJ="-Jx${SCL}i/-${SCL}i"
LIMS="-R$L/$R/$T/$B"

# Colored grid of Coulomb stress changes
gmt makecpt -T-1e5/1e5/1e4 -C./no_green_mwh.cpt -D > coul.cpt
gmt makecpt -T-1e-1/1e-1/1e-2 -C./no_green_mwh.cpt -D > coul2.cpt
paste staxz.dat coul.out | awk '{print $1,$2,$6}' |\
    gmt xyz2grd -Gcoul.grd $LIMS -I$NNX+/$NNY+
gmt grdimage coul.grd $PROJ $LIMS -Ccoul.cpt -Y2.5i -K > $PSFILE
gmt psscale -D`echo $WID | awk '{print $1/2}'`i/-0.6i/5.0i/0.2ih -Ccoul2.cpt -Ba0.05 -Bg0.01 \
    -B+l"Coulomb Stress Change (MPa)" -Al -K -O >> $PSFILE

# Map stuff
if [ $TXT == "e" ]
then
    XTXT="Distance from Epicenter (km)"
elif [ $TXT == "p"  ]
then
    XTXT="Distance from Peak Slip Location (km)"
else
    XTXT="Distance from \(${LAT0}N,${LON0}E\) (km)"
fi
ANNOT=`echo $R | awk '{if($1<=300){print 50}else{print 100}}'`
gmt psbasemap $PROJ $LIMS -Bxa${ANNOT} -Bya50 -BWesN -K -O \
    -Bx+l"$XTXT" -By+l"Depth (km)" >> $PSFILE

# Plot cross-section of earthquake fault
if [ $SRC_TYPE == "FFM" ]
then
    awk '{if (substr($1,1,1)!="#" && NF>3) print $2,$1,$3}' ffm.dat |\
      gmt project -C$LON0/$LAT0 -A$AZ -Fpz -Q |\
      sort -g |\
      gmt psxy $PROJ $LIMS -W2p,white -K -O -t30 >> $PSFILE
else
    if [ $DIPD == "L" ]
    then
    gmt psxy $PROJ $LIMS -W2p,white -K -O -t30 >> $PSFILE << EOF
      `awk '{print $6*0.5,'"$Z"'-$6*0.5*sin('"$TDIP"'*0.01745)/cos('"$TDIP"'*0.01745)}' rect.out`
      0 $Z
      `awk '{print -$6*0.5,'"$Z"'+$6*0.5*sin('"$TDIP"'*0.01745)/cos('"$TDIP"'*0.01745)}' rect.out`
EOF
    else
    gmt psxy $PROJ $LIMS -W2p,white -K -O -t30 >> $PSFILE << EOF
      `awk '{print -$6*0.5,'"$Z"'-$6*0.5*sin('"$TDIP"'*0.01745)/cos('"$TDIP"'*0.01745)}' rect.out`
      0 $Z
      `awk '{print $6*0.5,'"$Z"'+$6*0.5*sin('"$TDIP"'*0.01745)/cos('"$TDIP"'*0.01745)}' rect.out`
EOF
    fi
fi

# Legend (all coordinates are in cm from the bottom left)
X1="0.2"
X2="3.2"
Y1="0.2"
Y2="3.3"
XM=`echo $X1 $X2 | awk '{print 0.5*($1+$2)}'`
SHIFT=`echo $TSTR $AZ $WID $X1 $X2 |\
       awk '{if($2-$1>0){print ""}else{print "-X"($3*2.54-$4-$5)"c"}}'`
gmt psxy -JX10c -R0/10/0/10 -W1p -Gwhite $SHIFT -K -O >> $PSFILE << EOF
$X1 $Y1
$X1 $Y2
$X2 $Y2
$X2 $Y1
$X1 $Y1
EOF
LON0=`echo $LON0 | awk '{printf("%10.2f"),$1}' | awk '{print $1}'`
LAT0=`echo $LAT0 | awk '{printf("%10.2f"),$1}' | awk '{print $1}'`
Z0=`echo $Z0 | awk '{printf("%10.2f"),$1}' | awk '{print $1}'`
gmt pstext -JX10c -R0/10/0/10 -F+f+j -K -O >> $PSFILE << EOF
$XM 2.9 12,1 CM @_Target Faults@_
$XM 2.4 10,0 CM Strike/Dip/Rake
$XM 2.0 10,0 CM $TSTR\260/$TDIP\260/$TRAK\260
$XM 0.5 8,0 CM (Projected)
EOF
# Projected focal mechanism of target faults
XF="$XM"  # center of fault in x direction
YF="1.2"  # center of fault in y direction
FLT="0.8" # diameter of beach ball
TRAK=`echo $TRAK | awk '{print $1+0.1}'`
echo $XF $YF 0 $TSTR $TDIP $TRAK 5 |\
    gmt pscoupe -JX10c -R0/10/0/10 -Ad$XF/$YF/$AZ/1e4/90/1e4/-1e4/1e4 -Sa${FLT}c \
        -G155/155/155 -K -O -Xa${XF}c -Ya${YF}c -N >> $PSFILE
# Relative motion vectors
TYPE=`echo $TRAK | awk '{if($1>0){print "TH"}else{print "NO"}}'`
if [ $DIPD == "R" -a $TYPE == "TH" ]
then
    echo $XF $YF $TDIP 0.5 0.1 $TRAK |\
        awk '{print $1+$5*sin($3*0.01745),$2+$5*cos($3*0.01745),-$3,$4}' |\
        gmt psxy -JX10c -R0/10/0/10 -Sv5p+jc+b+l+a60 -W1p -Gblack -K -O >> $PSFILE
    echo $XF $YF $TDIP 0.5 0.1 |
        awk '{print $1-$5*sin($3*0.01745),$2-$5*cos($3*0.01745),-$3,$4}' |\
        gmt psxy -JX10c -R0/10/0/10 -Sv5p+jc+e+r+a60 -W1p -Gblack -K -O >> $PSFILE
elif [ $DIPD == "L" -a $TYPE == "TH" ]
then
    echo $XF $YF $TDIP 0.5 0.1 |\
        awk '{print $1-$5*sin($3*0.01745),$2+$5*cos($3*0.01745),$3,$4}' |\
        gmt psxy -JX10c -R0/10/0/10 -Sv5p+jc+e+l+a60 -W1p -Gblack -K -O >> $PSFILE
    echo $XF $YF $TDIP 0.5 0.1 |
        awk '{print $1+$5*sin($3*0.01745),$2-$5*cos($3*0.01745),$3,$4}' |\
        gmt psxy -JX10c -R0/10/0/10 -Sv5p+jc+b+r+a60 -W1p -Gblack -K -O >> $PSFILE
elif [ $DIPD == "R" -a $TYPE == "NO" ]
then
    echo $XF $YF $TDIP 0.5 0.1 $TRAK |\
        awk '{print $1+$5*sin($3*0.01745),$2+$5*cos($3*0.01745),-$3,$4}' |\
        gmt psxy -JX10c -R0/10/0/10 -Sv5p+jc+e+l+a60 -W1p -Gblack -K -O >> $PSFILE
    echo $XF $YF $TDIP 0.5 0.1 |
        awk '{print $1-$5*sin($3*0.01745),$2-$5*cos($3*0.01745),-$3,$4}' |\
        gmt psxy -JX10c -R0/10/0/10 -Sv5p+jc+b+r+a60 -W1p -Gblack -K -O >> $PSFILE
elif [ $DIPD == "L" -a $TYPE == "NO" ]
then
    echo $XF $YF $TDIP 0.5 0.1 |\
        awk '{print $1-$5*sin($3*0.01745),$2+$5*cos($3*0.01745),$3,$4}' |\
        gmt psxy -JX10c -R0/10/0/10 -Sv5p+jc+b+l+a60 -W1p -Gblack -K -O >> $PSFILE
    echo $XF $YF $TDIP 0.5 0.1 |
        awk '{print $1+$5*sin($3*0.01745),$2-$5*cos($3*0.01745),$3,$4}' |\
        gmt psxy -JX10c -R0/10/0/10 -Sv5p+jc+e+r+a60 -W1p -Gblack -K -O >> $PSFILE
fi

# Location map
#PROJ="-JM1i"
#LIMS=`gmtinfo sta.dat -I0.1/0.1`
#W=`echo $LON0 | awk '{print $1-3}'`
#E=`echo $LON0 | awk '{print $1+3}'`
#S=`echo $LAT0 | awk '{print $1-3}'`
#N=`echo $LAT0 | awk '{print $1+3}'`
#LIMS="-R$W/$E/$S/$N"
#SHFT=`echo $WID | awk '{print $1+0.2}'`
#gmt psbasemap $PROJ $LIMS -Bf1 -K -O -X${SHFT}i --MAP_FRAME_TYPE=plain >> $PSFILE
#gmt pscoast $PROJ $LIMS -W1p -Di -K -O >> $PSFILE
## Plot source fault
#if [ $SRC_TYPE == "FFM" ]
#then
#    ff2gmt -f ffm.dat -clipseg clip.out
#    gmt psxy clip.out $PROJ $LIMS -W1p,105/105/105 -K -O -t40 >> $PSFILE
#else
#    awk '{print $1,$2,$4,$5,$6}' rect.out |\
#        gmt psxy $PROJ $LIMS -SJ -W1p,105/105/105 -K -O -t40 >> $PSFILE
#fi
## Plot epicenter
#if [ $SRC_TYPE == "FFM" ]
#then
#    LONX=`sed -n -e "3p" ffm.dat | sed -e "s/.*Lon:/Lon:/" | awk '{print $2}'`
#    LATX=`sed -n -e "3p" ffm.dat | sed -e "s/.*Lon:/Lon:/" | awk '{print $4}'`
#    echo $LONX $LATX |\
#        gmt psxy $PROJ $LIMS -Sa0.15i -W1p,black -K -O  >> $PSFILE
#fi
#awk '{if(NR==1){print $1,$2}}END{print $1,$2}' sta.dat |\
#    gmt psxy $PROJ $LIMS -W1p,blue -K -O >> $PSFILE
#awk '{if(NR==1){print $1,$2}}END{print $1,$2}' sta.dat |\
#    gmt psxy $PROJ $LIMS -Sc0.4c -W0.5p -Gwhite -K -O >> $PSFILE
#awk '{if(NR==1){print $1,$2,"9,0 CM -"}}' sta.dat |\
#    gmt pstext $PROJ $LIMS -F+f+j -K -O >> $PSFILE
#awk 'END{print $1,$2,"9,0 CM +"}' sta.dat |\
#    gmt pstext $PROJ $LIMS -F+f+j -K -O >> $PSFILE

echo 0 0 | gmt psxy $PROJ $LIMS -O >> $PSFILE

#####
#	CLEAN UP
#####
ps2pdf $PSFILE
rm Ad*
rm no_green_mwh.cpt




