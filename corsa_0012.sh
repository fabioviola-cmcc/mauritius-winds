#!/bin/sh -l 

# set appname
APPNAME="[corsa_00]"

# configuration
POSTCLEAN=0
PRECLEAN=1
MOVE=0

# load modules
echo "[$APPNAME] -- Loading modules"
module load intel19.5/19.5.281 intel19.5/szip/2.1.1 intel19.5/hdf5/1.10.5 intel19.5/netcdf/C_4.7.2-F_4.5.2_CXX_4.3.1 intel19.5/udunits/2.2.26 intel19.5/cdo/1.9.8 intel19.5/magics/3.3.1 intel19.5/ncview/2.1.8 intel19.5/nco/4.8.1 intel19.5/eccodes/2.12.5

# enable anaconda
echo "[$APPNAME] -- Enabling anaconda"
source ~/.bash_anaconda_3.7
conda activate cmcc

# read parameters
proddate=$1
pyear=${proddate:0:4}
pmonth=${proddate:4:2}
pday=${proddate:6:2}

# set paths
echo "[$APPNAME] -- Setting paths"
dirin=./workdir_0012/IN/
dirwork=./workdir_0012/tmp/
dirout=./workdir_0012/OUT/
finaldir=/work/opa/witoil-dev/witoil-glob-DATA/fcst_data/SK1/

####################################################
#
# Function to process files: Procfile
#
####################################################

Procfile() {
    
    fileg=$1
    name=`basename $1`
    datef=`echo $name | cut -c 4-7`

    yearf=$2
    monthf=$3
    dayf=$4
    hourf=$5
    dateff="${yearf}-${monthf}-${dayf}"
    
    hf=`echo $name | cut -c 16-17`
    ncfileo=MED_2020${datef}${hf}.nc
    
    # What? Convert the grib to nc (1 timestep, a lot of variables)
    echo $fileg
    cdo -r -f nc -t ecmwf copy $fileg ${dirwork}/tmp1_${datef}_${hf}.nc
    
    # set the timestep
    cdo -settime,${hf}:00:00 -setdate,$dateff -settunits,hours -settaxis,1950-1-1,00:00 ${dirwork}/tmp1_${datef}_${hf}.nc ${dirwork}/tmp2_${datef}_${hf}.nc

    # crop
    cdo sellonlatbox,-180,180,-90,90 ${dirwork}/tmp2_${datef}_${hf}.nc ${dirwork}/tmp3_${datef}_${hf}.nc
 
    # select only the desired variables
    Cmd="ncks -h -O -d lon,57.,58. -d lat,-21.,-19. -v time,lon,lat,U10M,V10M ${dirwork}/tmp2_${datef}_${hf}.nc ${dirwork}/$ncfileo"
    eval $Cmd

}


####################################################
#
# main
#
####################################################

# clean work directory
if [[ $PRECLEAN -eq 1 ]]; then
    rm ${dirwork}/* -f
fi

NUMDAYS=5

# determine last file needed
refdate=$(date -d "${proddate}+${NUMDAYS}days" "+%Y%m%d")
ryear=${refdate:0:4}
rmonth=${refdate:4:2}
rday=${refdate:6:2}
LASTFILE="/data/inputs/metocean/rolling/atmos/ECMWF/IFS_010/1.0forecast/1h/grib/${pyear}${pmonth}${pday}/JLS${pmonth}${pday}1200${rmonth}${rday}23001"

# iterate over days
for d in $(seq 0 $NUMDAYS); do

     
    # determine the day to produce
    refdate=$(date -d "${proddate}+${d}days" "+%Y%m%d")
    echo "====================================================================="
    echo "[$APPNAME] -- Processing date $refdate"

    # read parameters
    ryear=${refdate:0:4}
    rmonth=${refdate:4:2}
    rday=${refdate:6:2}

    # manage first timestep of the first day
    if [[ d -eq 0 ]]; then

	# copy original data
	echo "[$APPNAME] -- Copying original file /data/inputs/metocean/historical/model/atmos/ECMWF/IFS_010/analysis/6h/grib/${pyear}/${pmonth}/JLD${pmonth}${pday}0000${rmonth}${rday}00011"
	cp -v /data/inputs/metocean/historical/model/atmos/ECMWF/IFS_010/analysis/6h/grib/${pyear}/${pmonth}/JLD${pmonth}${pday}0000${rmonth}${rday}00001 $dirin/JLS${pmonth}${pday}0000${rmonth}${rday}00001
    fi
	    
    # copy original data
    echo "[$APPNAME] -- Copying original files /data/inputs/metocean/rolling/atmos/ECMWF/IFS_010/1.0forecast/1h/grib/${pyear}${pmonth}${pday}/JLS${pmonth}${pday}0000${rmonth}${rday}*"
    cp /data/inputs/metocean/rolling/atmos/ECMWF/IFS_010/1.0forecast/1h/grib/${pyear}${pmonth}${pday}/JLS${pmonth}${pday}0000${rmonth}${rday}* $dirin
    cp /data/inputs/metocean/rolling/atmos/ECMWF/IFS_010/1.0forecast/1h/grib/${pyear}${pmonth}${pday}/JLS${pmonth}${pday}1200${rmonth}${rday}* $dirin

    echo "[$APPNAME] -- Iterating over timesteps"
	
    # iterate over timesteps
    for hh in $(seq 0 23) ; do
	if [[ hh -le 9 ]]; then
	    hhh=0${hh}
	else
	    hhh=$hh
	fi
	if [[ hh -lt 13 ]]; then 
            fileg=JLS${pmonth}${pday}0000${rmonth}${rday}${hhh}001
	else
	    fileg=JLS${pmonth}${pday}1200${rmonth}${rday}${hhh}001
	fi
        if [ -f $dirin/$fileg ] ; then
	    echo "[$APPNAME] -- Processing file $fileg"
            Procfile $dirin/$fileg $ryear $rmonth $rday $hh
        else
	    echo "[$APPNAME] -- File $fileg not found"
            exit
        fi
    done

    # merge timesteps
    echo "[$APPNAME] -- Merging timesteps..."
    ls $dirwork
    echo ${dirwork}/MED_${day}.nc
    fileout="${ryear}${rmonth}${rday}.nc"
    Cmd="ncrcat -h ${dirwork}/MED_${day}*.nc ${dirout}/$fileout"
    echo $Cmd
    eval $Cmd

    # clean work directory
    echo "[$APPNAME] -- Cleaning work directory..."
    if [[ $POSTCLEAN -eq 1 ]]; then     
	rm ${dirwork}/*
    fi
    
    # move file to final directory
    if [[ $MOVE -eq 1 ]]; then
	mv ${dirout}/$fileout $finaldir
    fi

done
