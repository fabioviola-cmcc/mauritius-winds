#!/bin/sh -l 

# set appname
APPNAME="[corsa_00]"

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
dirin=./IN/
dirwork=./tmp/
dirout=./OUT
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
    hf=`echo $name | cut -c 16-17`
    ncfileo=MED_2020${datef}${hf}.nc

    # What? Convert the grib to nc (1 timestep, a lot of variables)
    cdo -r -f nc -t ecmwf copy $fileg ${dirwork}/tmp1.nc

    # crop
    cdo sellonlatbox,-180,180,-90,90 ${dirwork}/tmp1.nc ${dirwork}/tmp2.nc
 
    # select only the desired variables
    Cmd="ncks -h -O -d lon,57.,58. -d lat,-20.,-19. -v time,lon,lat,U10M,V10M ${dirwork}/tmp2.nc ${dirwork}/$ncfileo"
    eval $Cmd

}


####################################################
#
# main
#
####################################################

# clean work directory
rm ${dirwork}/* -f

# iterate over days
for d in $(seq 0 2); do

    # determine the day to produce
    refdate=$(date -d "${proddate}+${d}days" "+%Y%m%d")
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

    echo "[$APPNAME] -- Iterating over timesteps"
	
    # iterate over timesteps
    for hh in $(seq 0 23) ; do
	if [[ hh -le 9 ]]; then
	    hh=0${hh}
	fi
        fileg=JLS${pmonth}${pday}0000${rmonth}${rday}${hh}001
        if [ -f $dirin/$fileg ] ; then
	    echo "[$APPNAME] -- Processing file $fileg"
            Procfile $dirin/$fileg
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
    rm ${dirwork}/*

    # move file to final directory
    mv ${dirout}/$fileout $finaldir
    
done
