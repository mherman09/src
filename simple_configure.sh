#!/bin/bash

# Configure script command line options
function usage() {
    echo "$0 [--fortran_compiler=FC] [--lapack_dir=/PATH/TO/LAPACK/LIBRARIES] [--bin_dir=/PATH/TO/EXECUTABLES] [--interactive]"
    echo
    echo "--fortran_compiler=FC                      Define Fortran compiler"
    echo "--lapack_dir=/PATH/TO/LAPACK/LIBRARIES     Define location of LAPACK libraries"
    echo "--bin_dir=/PATH/TO/EXECUTABLES             Define path for installing executables"
    echo "--interactive                              Script prompts for inputs"
    echo
    echo "Note: if working in a root directory or trying to install programs in a root directory, may have to use \"sudo $0\""
    exit 1
}
if [ $# -eq 0 ]
then
    usage
fi

# Parse command line
FC=""
LAPACK_LIB_DIR=""
BIN_DIR=""
INTERACTIVE="N"
DEFAULT="N"
while [ "$1" != "" ]
do
    case $1 in
        --fortran_compiler=*)FC=`echo $1 | sed -e "s/--fortran_compiler=//"`;;
        --lapack_dir=*)LAPACK_LIB_DIR=`echo $1 | sed -e "s/--lapack_dir=//"`;;
        --bin_dir=*)BIN_DIR=`echo $1 | sed -e "s/--bin_dir=//"`;;
        --interactive)INTERACTIVE="Y";;
        *)echo "!! Error: No option $1"; usage;;
    esac
    shift
done

#####
#	Set up and test Fortran compiler
#####
echo "####################################################################################################"
echo "##########                         WORKING ON FORTRAN STUFF                               ##########"
echo "####################################################################################################"
# Get name of Fortran compiler
if [ -z "$FC" -o $INTERACTIVE == "Y" ]
then
    echo Enter the name of your Fortran compiler:
    read FC
fi
echo Testing $FC installation
# Look for an executable named $FC
FC_TEST=`which $FC`
if [ -z $FC_TEST ]
then
    echo !! Error: no executable found named $FC
    echo !! Check to see if $FC is in your PATH or full path is written correctly
    exit 1
fi
# Compile and run a simple Fortran program
FC_TEST="config_fortran_compiler_test"
if [ -f $FC_TEST ]
then
    rm $FC_TEST
fi
cat > $FC_TEST.f << EOF
      PROGRAM main
      IMPLICIT none
      write(*,'(A)') '1234567890'
      END
EOF
$FC $FC_TEST.f -o $FC_TEST
chmod +x $FC_TEST
FC_OUTPUT=`./$FC_TEST`
if [ "$FC_OUTPUT" != "1234567890" ]
then
    echo !! Error: Fortran compiler does not compile test example!
    exit 1
else
    echo Test complete! Using Fortran compiler: $FC
fi
# Clean up
rm $FC_TEST.f $FC_TEST
echo


#####
#	Set up LAPACK path and test LAPACK library
#####
echo "####################################################################################################"
echo "##########                          WORKING ON LAPACK STUFF                               ##########"
echo "####################################################################################################"
if [ $INTERACTIVE == "Y" ]
then
    echo "If you want to install the software that depends on the LAPACK libraries, enter the directory"
    echo "that contains the LAPACK libraries: (Otherwise, leave blank and just hit \"return\")"
    read LAPACK_LIB_DIR
fi

if [ -z "$LAPACK_LIB_DIR" ]
then
    echo Installing software without LAPACK dependencies
else
    # Make sure directory exists and has correct libraries in it
    LAPACK_LIB_DIR_CONTENTS=`ls $LAPACK_LIB_DIR 2>&1`
    EXIST=`echo $LAPACK_LIB_DIR_CONTENTS | awk '{if(/No such file or directory/){print "N";exit}else{print "Y";exit}}'`
    if [ "$EXIST" == "N" ]
    then
        echo !! Error: Directory $LAPACK_LIB_DIR is non-existent
        exit 1
    fi
    if [ -z "$LAPACK_LIB_DIR_CONTENTS" ]
    then
        echo !! Error: Directory $LAPACK_LIB_DIR is empty
        exit 1
    else
        LAPACK_LIB_LIST=""
        for LIB in lapack refblas tmglib
        do
            EXIST=`ls $LAPACK_LIB_DIR/lib$LIB.a 2>&1 | awk '{if(/No such file or directory/){print "N";exit}else{print "Y";exit}}'`
            LIB2=$LIB
            if [ "$EXIST" == "N" -a "$LIB" == "lapack" ]
            then
                echo "LAPACK library \"lapack\" does not exist; looking for library \"reflapack\""
                EXIST=`ls $LAPACK_LIB_DIR/libreflapack.a 2>&1 | awk '{if(/No such file or directory/){print "N";exit}else{print "Y";exit}}'`
                LIB2=reflapack
            fi
            if [ "$EXIST" == "N" ]
            then
                echo !! Error: LAPACK library \"$LIB2\" is not in $LAPACK_LIB_DIR
                exit 1
            fi
            echo Found LAPACK library: $LIB2!
            LAPACK_LIB_LIST="$LAPACK_LIB_LIST -l$LIB2"
        done
    fi
    echo Test complete! Using LAPACK libraries in directory: $LAPACK_LIB_DIR
fi
echo

#####
#	Directory to install software
#####
echo "####################################################################################################"
echo "##########                    WORKING ON INSTALL DIRECTORY STUFF                          ##########"
echo "####################################################################################################"
if [ -z "$BIN_DIR" -o $INTERACTIVE == "Y" ]
then
    echo "Enter the path to place the compiled executables (Default: bin):"
    read ANSWER
    if [ -z "$ANSWER" ]
    then
        ANSWER="bin"
    fi
    BIN_DIR=$ANSWER
fi
echo Putting exectuables in $BIN_DIR
if [ ! -d $BIN_DIR ]
then
    echo Directory $BIN_DIR does not exist....creating it
    mkdir $BIN_DIR
else
    echo Directory $BIN_DIR already exists
fi
echo
echo

echo "####################################################################################################"
echo "##########                           INSTALL THE CODES!                                   ##########"
echo "####################################################################################################"
echo "Type \"make\""


#####
#	Generating makefile
#####
cat > Makefile << EOF
##### Compiler variables #####
FC = -$FC
FWARN = -Wall -Wextra -Wunused -fbounds-check -fbacktrace
FOPT  = -O1
FFLAG = \$(FWARN) \$(FOPT)

##### Executable directory #####
BIN   = $BIN_DIR

##### External libraries #####
LAPACK_LIB_DIR = -L$LAPACK_LIB_DIR
LAPACK_LIB     = $LAPACK_LIB_LIST
LAPACK         = \$(LAPACK_LIB_DIR) \$(LAPACK_LIB)

EOF

if [ -n "$LAPACK_LIB_DIR" ]
then
    echo "all: defm geom misc fits seis scripts other" >> Makefile
else
    echo "all: defm geom misc           scripts other" >> Makefile
fi

cat >> Makefile << EOF

defm: \\
      \$(BIN)/o92util \\
      \$(BIN)/vec2los \\
      \$(BIN)/wraplos
\$(BIN)/o92util: src/o92util.f src/okada92subs.f src/geomsubs.f src/okada92subs_volume.f
	\$(FC) \$(FFLAG) -o \$(BIN)/o92util src/o92util.f src/okada92subs.f src/geomsubs.f src/okada92subs_volume.f
\$(BIN)/vec2los: src/vec2los.f
	\$(FC) \$(FFLAG) -o \$(BIN)/vec2los src/vec2los.f
\$(BIN)/wraplos: src/wraplos.f
	\$(FC) \$(FFLAG) -o \$(BIN)/wraplos src/wraplos.f

geom: \\
      \$(BIN)/lola2distaz \\
      \$(BIN)/distaz2lola \\
      \$(BIN)/sphfinrot \\
      \$(BIN)/platemotion \\
      \$(BIN)/utm2geo
\$(BIN)/lola2distaz: src/lola2distaz.f src/geomsubs.f
	\$(FC) \$(FFLAG) -o \$(BIN)/lola2distaz src/lola2distaz.f src/geomsubs.f
\$(BIN)/distaz2lola: src/distaz2lola.f src/geomsubs.f
	\$(FC) \$(FFLAG) -o \$(BIN)/distaz2lola src/distaz2lola.f src/geomsubs.f
\$(BIN)/sphfinrot: src/sphfinrot.f
	\$(FC) \$(FFLAG) -o \$(BIN)/sphfinrot src/sphfinrot.f
\$(BIN)/platemotion: src/platemotion.f
	\$(FC) \$(FFLAG) -o \$(BIN)/platemotion src/platemotion.f
\$(BIN)/utm2geo: src/utm2geo.f src/geomsubs.f
	\$(FC) \$(FFLAG) -o \$(BIN)/utm2geo src/utm2geo.f src/geomsubs.f

misc: \\
      \$(BIN)/dateutil \\
      \$(BIN)/eventfrequency \\
      \$(BIN)/ff2gmt \\
      \$(BIN)/grid \\
      \$(BIN)/pt2fin \\
      \$(BIN)/perturb \\
      \$(BIN)/readkik
\$(BIN)/dateutil: src/dateutil.f
	\$(FC) \$(FFLAG) -o \$(BIN)/dateutil src/dateutil.f
\$(BIN)/eventfrequency: src/eventfrequency.f
	\$(FC) \$(FFLAG) -o \$(BIN)/eventfrequency src/eventfrequency.f
\$(BIN)/ff2gmt: src/ff2gmt.f
	\$(FC) \$(FFLAG) -o \$(BIN)/ff2gmt src/ff2gmt.f
\$(BIN)/grid: src/grid.f
	\$(FC) \$(FFLAG) -o \$(BIN)/grid src/grid.f
\$(BIN)/pt2fin: src/pt2fin.f
	\$(FC) \$(FFLAG) -o \$(BIN)/pt2fin src/pt2fin.f
\$(BIN)/perturb: src/perturb.f
	\$(FC) \$(FFLAG) -o \$(BIN)/perturb src/perturb.f src/randsubs.f
\$(BIN)/readkik: src/readkik.f
	\$(FC) \$(FFLAG) -o \$(BIN)/readkik src/readkik.f

fits: \\
      \$(BIN)/polyfit \\
      \$(BIN)/polyfit_special \\
      \$(BIN)/multifit \\
      \$(BIN)/fltinv
\$(BIN)/polyfit: src/polyfit.f src/lsqsubs.f
	\$(FC) \$(FFLAG) -o \$(BIN)/polyfit src/polyfit.f src/lsqsubs.f \$(LAPACK)
\$(BIN)/polyfit_special: src/polyfit_special.f
	\$(FC) \$(FFLAG) -o \$(BIN)/polyfit_special src/polyfit_special.f \$(LAPACK)
\$(BIN)/multifit: src/multifit.f
	\$(FC) \$(FFLAG) -o \$(BIN)/multifit src/multifit.f \$(LAPACK)
\$(BIN)/fltinv: src/fltinv.f src/okada92subs.f src/geomsubs.f
	\$(FC) \$(FFLAG) -o \$(BIN)/fltinv src/fltinv.f src/okada92subs.f src/geomsubs.f \$(LAPACK) src/randsubs.f 

seis: \\
      \$(BIN)/mtutil
\$(BIN)/mtutil: src/mtutil.f src/mtsubs.f
	\$(FC) \$(FFLAG) -o \$(BIN)/mtutil src/mtutil.f src/mtsubs.f \$(LAPACK)

scripts: \\
      \$(BIN)/coul_hor.sh \\
      \$(BIN)/coul_dip.sh \\
      \$(BIN)/coul_xsec.sh \\
      \$(BIN)/surf_disp.sh \\
      \$(BIN)/simplify_ffm.sh \\
      \$(BIN)/ternary.sh \\
      \$(BIN)/trg_schem.sh 
\$(BIN)/coul_hor.sh: scripts/coul_hor.sh
	cp scripts/coul_hor.sh \$(BIN)/coul_hor.sh
\$(BIN)/coul_dip.sh: scripts/coul_dip.sh
	cp scripts/coul_dip.sh \$(BIN)/coul_dip.sh
\$(BIN)/coul_xsec.sh: scripts/coul_xsec.sh
	cp scripts/coul_xsec.sh \$(BIN)/coul_xsec.sh
\$(BIN)/surf_disp.sh: scripts/surf_disp.sh
	cp scripts/surf_disp.sh \$(BIN)/surf_disp.sh
\$(BIN)/simplify_ffm.sh: scripts/simplify_ffm.sh
	cp scripts/simplify_ffm.sh \$(BIN)/simplify_ffm.sh
\$(BIN)/ternary.sh: scripts/ternary.sh
	cp scripts/ternary.sh \$(BIN)/ternary.sh
\$(BIN)/trg_schem.sh: scripts/trg_schem.sh
	cp scripts/trg_schem.sh \$(BIN)/trg_schem.sh

other: \\
      \$(BIN)/pole2vel \\
      \$(BIN)/numint
\$(BIN)/pole2vel: src/pole2vel.f
	\$(FC) \$(FFLAG) -o \$(BIN)/pole2vel src/pole2vel.f
\$(BIN)/numint: src/numint.f
	\$(FC) \$(FFLAG) -o \$(BIN)/numint src/numint.f

.PHONY: clean
clean:
	-rm \$(BIN)/o92util
	-rm \$(BIN)/vec2los
	-rm \$(BIN)/wraplos
	-rm \$(BIN)/lola2distaz
	-rm \$(BIN)/distaz2lola
	-rm \$(BIN)/sphfinrot
	-rm \$(BIN)/platemotion 
	-rm \$(BIN)/utm2geo
	-rm \$(BIN)/dateutil
	-rm \$(BIN)/eventfrequency
	-rm \$(BIN)/ff2gmt
	-rm \$(BIN)/grid
	-rm \$(BIN)/pt2fin
	-rm \$(BIN)/perturb
	-rm \$(BIN)/polyfit
	-rm \$(BIN)/multifit
	-rm \$(BIN)/fltinv
	-rm \$(BIN)/readkik
	-rm \$(BIN)/mtutil
	-rm \$(BIN)/coul_hor.sh
	-rm \$(BIN)/coul_dip.sh
	-rm \$(BIN)/coul_xsec.sh
	-rm \$(BIN)/surf_disp.sh
	-rm \$(BIN)/simplify_ffm.sh
	-rm \$(BIN)/ternary.sh
	-rm \$(BIN)/trg_schem.sh
	-rm \$(BIN)/pole2vel
	-rm \$(BIN)/numint
	-rm \$(BIN)/polyfit_special


EOF
