#!/bin/bash -l
#
# This script contains all the operations needed to generate
# wind files for Mauritius in the morning. Run 00.
# run.
# Invoked with the date today (let's call it DAY, for simplicity),
# it will generate forecasts for the days:
# - DAY+0 -- using 1h data
# - DAY+1 -- using 1h data
# - DAY+2 -- using 1h data
# - DAY+3 -- using 1+3h data (1h until 6pm included)
# - DAY+4 -- using 3h data
# - DAY+5 -- using 3h data
# - DAY+6 -- using 3h+6h data
# - DAY+7 -- using 6h
# - DAY+8 -- using 6h
#

source $HOME/.bashrc

#####################################################
#
# INITIAL SETUP
#
#####################################################

# set the app name
APPNAME="CRON_WIND_RUN00"

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

# move final files? 1=YES, 0=NO
MOVE=0
POSTCLEAN=0

# set paths
echo "[$APPNAME] -- Setting paths"
basedir=/work/opa/witoil-dev/agrandi/
dirin=${basedir}/workdir_00/IN/
dirwork=${basedir}/workdir_00/tmp/
dirout=${basedir}/workdir_00/OUT/
finaldir=/work/opa/witoil-dev/mauritius/winds/

# log files
LOGFILE=wind_generator_00.log
echo "=== Wind Generator -- $(date) ===" > $LOGFILE


#####################################################
#
# INITIAL CLEAN
#
#####################################################

rm -rf $dirin/*
rm -rf $dirwork/*
rm -rf $dirout/*


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
    ncfileo=MED_${dateff}-${hourf}.nc 
    
    # What? Convert the grib to nc (1 timestep, a lot of variables)
    cdo -r -f nc -t ecmwf copy $fileg ${dirwork}/tmp1_${dateff}_${hf}.nc 2>&1 | tee $LOGFILE
    
    # set the timestep
    cdo -settime,${hf}:00:00 -setdate,$dateff -settunits,hours -settaxis,1950-1-1,00:00 ${dirwork}/tmp1_${dateff}_${hf}.nc ${dirwork}/tmp2_${dateff}_${hf}.nc 2>&1 | tee $LOGFILE

    # crop
    cdo sellonlatbox,-180,180,-90,90 ${dirwork}/tmp2_${dateff}_${hf}.nc ${dirwork}/tmp3_${dateff}_${hf}.nc 2>&1 | tee $LOGFILE
 
    # select only the desired variables   
    ncks -O -h -O -d lon,57.,58. -d lat,-21.,-19. -v time,lon,lat,U10M,V10M ${dirwork}/tmp2_${dateff}_${hf}.nc ${dirwork}/$ncfileo 2>&1 | tee $LOGFILE
    
    if [[ ! ${PIPESTATUS[0]} -eq 0 ]]; then
	
	    echo "--- Long procedure! ---"

	    # select only the desired variable
	    ncks -O -h -O -d lon_2,57.,58. -d lat_2,-21.,-19. -v time,lon_2,lat_2,U10M,V10M ${dirwork}/tmp2_${dateff}_${hf}.nc ${dirwork}/${ncfileo}4 2>&1 | tee $LOGFILE
	    
	    # convert to netcdf3 to invoke ncrename	    
	    ncks -O -3 ${dirwork}/${ncfileo}4 ${dirwork}/${ncfileo}3 2>&1 | tee $LOGFILE
	    
	    # ncrename
	    ncrename -O -d lat_2,lat -d lon_2,lon -v lon_2,lon -v lat_2,lat ${dirwork}/${ncfileo}3 2>&1 | tee $LOGFILE

	    # back to netcdf 4
	    ncks -O -4 ${dirwork}/${ncfileo}3 ${dirwork}/${ncfileo} 2>&1 | tee $LOGFILE
	    
    fi
}


#####################################################
#
# GENERATE 1H DATA
# We generate data for DAY+0, DAY+1, DAY+2
#
#####################################################


# iterate over days
for d in $(seq 0 2); do

    # determine the day to produce
    refdate=$(date -d "${proddate}+${d}days" "+%Y%m%d")
    echo "[$APPNAME] [1h] -- Processing date $refdate"

    # read parameters
    ryear=${refdate:0:4}
    rmonth=${refdate:4:2}
    rday=${refdate:6:2}
	    
    # copy original 1h data
    filename=/data/inputs/metocean/rolling/atmos/ECMWF/IFS_010/1.0forecast/1h/grib/${pyear}${pmonth}${pday}/JLS${pmonth}${pday}0000${rmonth}${rday}*
    echo "[$APPNAME] [1h] [$ryear/$rmonth/$rday] -- Copying original files ${filename}"
    cp $filename $dirin

    # copy the first timestep from analysis folder, if we are processing the first day
    if [[ $d -eq 0 ]]; then

	prevdate=$(date -d "${proddate}-1days" "+%Y%m%d")
	prevyear=${prevdate:0:4}
	prevmonth=${prevdate:4:2}
	prevday=${prevdate:6:2}
	filename=/data/inputs/metocean/rolling/atmos/ECMWF/IFS_010/1.0forecast/1h/grib/${prevyear}${prevmonth}${prevday}/JLS${prevmonth}${prevday}0000${rmonth}${rday}00001
	fileg=$(basename $filename)
	echo "[$APPNAME] [1h] [$ryear/$rmonth/$rday] -- Processing file $fileg"
	cp $filename $dirin
	Procfile $dirin/$fileg $ryear $rmonth $rday 00
    fi
	
    # iterate over timesteps
    echo "[$APPNAME] [1h] [$ryear/$rmonth/$rday] -- Iterating over timesteps"
    for hh in $(seq 0 23) ; do

	# if it's the first timestep of the first day skip,
	# since we have already processed it
	if [[ $d -eq 0 && $hh -eq 0 ]]; then
	    continue
	fi

	# add a trailing 0 if the timestep is made by just 1 digit
	if [[ hh -le 9 ]]; then
	    hh=0${hh}
	fi

	# process the file
        fileg=JLS${pmonth}${pday}0000${rmonth}${rday}${hh}001
        if [ -f $dirin/$fileg ] ; then
	    echo "[$APPNAME] [1h] [$ryear/$rmonth/$rday] -- Processing file $fileg"
            Procfile $dirin/$fileg $ryear $rmonth $rday $hh
        else
	    echo "[$APPNAME] [1h] [$ryear/$rmonth/$rday] -- File $fileg not found"
            exit
        fi
    done

    # merge timesteps
    echo "[$APPNAME] [1h] [$ryear/$rmonth/$rday] -- Merging timesteps..."
    fileout="${ryear}${rmonth}${rday}.nc"
    ncrcat -h ${dirwork}/MED_${ryear}-${rmonth}-${rday}-*.nc ${dirout}/${fileout}  2>&1 | tee $LOGFILE

    # clean work directory
    echo "[$APPNAME] [1h] [$ryear/$rmonth/$rday] -- Cleaning work directory..."
    if [[ $POSTCLEAN -eq 1 ]]; then
	rm ${dirwork}/*
    fi

    # check that file has been correctly generated
    if [[ ! -e ${dirout}/${fileout} ]]; then
	echo "[$APPNAME] [6h] [$ryear/$rmonth/$rday] -- ERROR: file ${fileout} not generated!"
	echo "[$APPNAME] [6h] [$ryear/$rmonth/$rday] -- ERROR: file ${fileout} not generated!" 2>&1 | tee $LOGFILE
    fi
       
    # move file to final directory
    if [[ $MOVE -eq 1 ]]; then
	mv ${dirout}/$fileout $finaldir
	chmod a+rx $finaldir/*
    fi

done


#####################################################
#
# GENERATE 1H+3H DATA
# We generate data for DAY+3
#
#####################################################


# iterate over days
for d in $(seq 3 3); do

    # determine the day to produce
    refdate=$(date -d "${proddate}+${d}days" "+%Y%m%d")
    echo "[$APPNAME] [1-3h] -- Processing date $refdate"

    # read parameters
    ryear=${refdate:0:4}
    rmonth=${refdate:4:2}
    rday=${refdate:6:2}
	    
    # copy original 1h data
    filename=/data/inputs/metocean/rolling/atmos/ECMWF/IFS_010/1.0forecast/1h/grib/${pyear}${pmonth}${pday}/JLS${pmonth}${pday}0000${rmonth}${rday}*
    echo "[$APPNAME] [1-3h] [$ryear/$rmonth/$rday] -- Copying original files ${filename}"
    cp $filename $dirin/
	
    # iterate over timesteps
    echo "[$APPNAME] [1-3h] [$ryear/$rmonth/$rday] -- Iterating over timesteps"
    for hh in $(seq 9 3 18) ; do

	# add a trailing 0 if the timestep is made by just 1 digit
	if [[ hh -le 9 ]]; then
	    hh=0${hh}
	fi
        fileg=JLS${pmonth}${pday}0000${rmonth}${rday}${hh}001
        if [ -f $dirin/$fileg ] ; then
	    echo "[$APPNAME] [1-3h] [$ryear/$rmonth/$rday] -- Processing file $fileg"
            Procfile $dirin/$fileg $ryear $rmonth $rday $hh
        else
	    echo "[$APPNAME] [1-3h] [$ryear/$rmonth/$rday] -- File $fileg not found"
            exit
        fi
    done

    # copy original 3h data
    filename=/data/inputs/metocean/rolling/atmos/ECMWF/IFS_010/1.0forecast/3h/grib/${pyear}${pmonth}${pday}/JLD${pmonth}${pday}0000${rmonth}${rday}*
    echo "[$APPNAME] [1-3h] [$ryear/$rmonth/$rday] -- Copying original files ${filename}"
    cp $filename $dirin
	
    # iterate over timesteps
    echo "[$APPNAME] [1-3h] [$ryear/$rmonth/$rday] -- Iterating over timesteps"
    for hh in $(seq 21 21) ; do

	# add a trailing 0 if the timestep is made by just 1 digit
	if [[ hh -le 9 ]]; then
	    hh=0${hh}
	fi

	# process input files
        fileg=JLD${pmonth}${pday}0000${rmonth}${rday}${hh}001
        if [ -f $dirin/$fileg ] ; then
	    echo "[$APPNAME] [1-3h] [$ryear/$rmonth/$rday] -- Processing file $fileg"
            Procfile $dirin/$fileg $ryear $rmonth $rday $hh
        else
	    echo "[$APPNAME] [1-3h] [$ryear/$rmonth/$rday] -- File $fileg not found"
            exit
        fi
    done
    
    # process the additional first timestep of the following day
    rnextdate=$(date -d "${ryear}-${rmonth}-${rday} +1 days" +%Y%m%d)
    nyear=${rnextdate:0:4}
    nmonth=${rnextdate:4:2}
    nday=${rnextdate:6:2}
    echo "[$APPNAME] [1-3h] -- Copying original files /data/inputs/metocean/rolling/atmos/ECMWF/IFS_010/1.0forecast/3h/grib/${pyear}${pmonth}${pday}/JLD${pmonth}${pday}0000${nmonth}${nday}00001"
    cp /data/inputs/metocean/rolling/atmos/ECMWF/IFS_010/1.0forecast/3h/grib/${pyear}${pmonth}${pday}/JLD${pmonth}${pday}0000${nmonth}${nday}00001 $dirin
    fileg=JLD${pmonth}${pday}0000${nmonth}${nday}00001
    Procfile $dirin/$fileg $nyear $nmonth $nday 00

    # merge timesteps
    echo "[$APPNAME] [1-3h] [$ryear/$rmonth/$rday] -- Merging timesteps..."
    fileout="${ryear}${rmonth}${rday}.nc"
    ncrcat -h ${dirwork}/MED_${ryear}-${rmonth}-${rday}-*.nc ${dirwork}/MED_${nyear}-${nmonth}-${nday}-00.nc ${dirwork}/${fileout}_MERGED 2>&1 | tee $LOGFILE

    # interpolate
    echo "[$APPNAME] [1-3h] [$ryear/$rmonth/$rday] -- Interpolating..."
    cdo -inttime,${ryear}-${rmonth}-${rday},00:00,1hour ${dirwork}/${fileout}_MERGED ${dirwork}/${fileout}_INTERP 2>&1 | tee $LOGFILE
    
    # remove last timestep
    echo "[$APPNAME] [1-3h] [$ryear/$rmonth/$rday] -- Removing last timestep..."
    ncks -O -d time,1,24 ${dirwork}/${fileout}_INTERP ${dirout}/${fileout} 2>&1 | tee $LOGFILE
    
    # clean work directory    
    echo "[$APPNAME] [1-3h] -- Cleaning work directory..."
    if [[ $POSTCLEAN -eq 1 ]]; then
	rm ${dirwork}/*
    fi

    # check that file has been correctly generated
    if [[ ! -e ${dirout}/${fileout} ]]; then
	echo "[$APPNAME] [6h] [$ryear/$rmonth/$rday] -- ERROR: file ${fileout} not generated!"
	echo "[$APPNAME] [6h] [$ryear/$rmonth/$rday] -- ERROR: file ${fileout} not generated!" 2>&1 | tee $LOGFILE
    fi
    
    # move file to final directory
    if [[ $MOVE -eq 1 ]]; then
	mv ${dirout}/$fileout $finaldir
    fi

done


#####################################################
#
# GENERATE 3H DATA
# We generate data for DAY+4 and DAY+5
#
#####################################################

# iterate over days
for d in $(seq 4 5); do

    # determine the day to produce
    refdate=$(date -d "${proddate}+${d}days" "+%Y%m%d")
    echo "[$APPNAME] [3h] -- Processing date $refdate"

    # read parameters
    ryear=${refdate:0:4}
    rmonth=${refdate:4:2}
    rday=${refdate:6:2}
	    
    # copy original data
    filename=/data/inputs/metocean/rolling/atmos/ECMWF/IFS_010/1.0forecast/3h/grib/${pyear}${pmonth}${pday}/JLD${pmonth}${pday}0000${rmonth}${rday}*
    echo "[$APPNAME] [3h] [$ryear/$rmonth/$rday] -- Copying original files ${filename}"
    cp $filename $dirin
	
    # iterate over timesteps
    echo "[$APPNAME] [3h] [$ryear/$rmonth/$rday] -- Iterating over timesteps"
    for hh in $(seq 0 3 21) ; do

	# add a trailing 0 if the timestep is made by just 1 digit
	if [[ hh -le 9 ]]; then
	    hh=0${hh}
	fi
        fileg=JLD${pmonth}${pday}0000${rmonth}${rday}${hh}001
        if [ -f $dirin/$fileg ] ; then
	    echo "[$APPNAME] [3h] [$ryear/$rmonth/$rday] -- Processing file $fileg"
            Procfile $dirin/$fileg $ryear $rmonth $rday $hh
        else
	    echo "[$APPNAME] [3h] [$ryear/$rmonth/$rday] -- File $fileg not found"
            exit
        fi
    done

    # add the additional first timestep of the following day
    rnextdate=$(date -d "${ryear}-${rmonth}-${rday} +1 days" +%Y%m%d)
    nyear=${rnextdate:0:4}
    nmonth=${rnextdate:4:2}
    nday=${rnextdate:6:2}
    echo "[$APPNAME] [3h] -- Copying original files /data/inputs/metocean/rolling/atmos/ECMWF/IFS_010/1.0forecast/3h/grib/${pyear}${pmonth}${pday}/JLD${pmonth}${pday}0000${nmonth}${nday}00001"
    cp /data/inputs/metocean/rolling/atmos/ECMWF/IFS_010/1.0forecast/3h/grib/${pyear}${pmonth}${pday}/JLD${pmonth}${pday}0000${nmonth}${nday}00001 $dirin
    fileg=JLD${pmonth}${pday}0000${nmonth}${nday}00001
    Procfile $dirin/$fileg $nyear $nmonth $nday 00

    # merge timesteps
    echo "[$APPNAME] [3h] [$ryear/$rmonth/$rday] -- Merging timesteps..."
    fileout="${ryear}${rmonth}${rday}.nc"
    ncrcat -h ${dirwork}/MED_${ryear}-${rmonth}-${rday}-*.nc ${dirwork}/MED_${nyear}-${nmonth}-${nday}-00.nc ${dirwork}/${fileout}_MERGED 2>&1 | tee $LOGFILE

    # interpolate
    echo "[$APPNAME] [3h] [$ryear/$rmonth/$rday] -- Interpolating..."
    cdo -inttime,${ryear}-${rmonth}-${rday},00:00,1hour ${dirwork}/${fileout}_MERGED ${dirwork}/${fileout}_INTERP 2>&1 | tee $LOGFILE

    # remove last timestep
    echo "[$APPNAME] [3h] [$ryear/$rmonth/$rday] -- Removing last timestep..."
    ncks -O -d time,1,24 ${dirwork}/${fileout}_INTERP ${dirout}/${fileout} 2>&1 | tee $LOGFILE
    
    # clean work directory
    echo "[$APPNAME] [3h] -- Cleaning work directory..."
    if [[ $POSTCLEAN -eq 1 ]]; then
	rm ${dirwork}/*
    fi

    # check that file has been correctly generated
    if [[ ! -e ${dirout}/${fileout} ]]; then
	echo "[$APPNAME] [6h] [$ryear/$rmonth/$rday] -- ERROR: file ${fileout} not generated!"
	echo "[$APPNAME] [6h] [$ryear/$rmonth/$rday] -- ERROR: file ${fileout} not generated!" 2>&1 | tee $LOGFILE
    fi
        
    # move file to final directory
    if [[ $MOVE -eq 1 ]]; then
	mv ${dirout}/$fileout $finaldir
    fi

done


#####################################################
#
# GENERATE 3+6H DATA
# We generate data for DAY+6
#
#####################################################

# iterate over days
for d in $(seq 6 6); do

    # determine the day to produce
    refdate=$(date -d "${proddate}+${d}days" "+%Y%m%d")
    echo "[$APPNAME] [3+6h] -- Processing date $refdate"

    # read parameters
    ryear=${refdate:0:4}
    rmonth=${refdate:4:2}
    rday=${refdate:6:2}
	    
    # copy original 3h data
    filename=/data/inputs/metocean/rolling/atmos/ECMWF/IFS_010/1.0forecast/3h/grib/${pyear}${pmonth}${pday}/JLD${pmonth}${pday}0000${rmonth}${rday}*
    echo "[$APPNAME] [3+6h] [$ryear/$rmonth/$rday] -- Copying original files ${filename}"
    cp $filename $dirin/
	
    # iterate over timesteps
    echo "[$APPNAME] [3+6h] [$ryear/$rmonth/$rday] -- Iterating over timesteps"
    for hh in $(seq 0 0) ; do

	# add a trailing 0 if the timestep is made by just 1 digit
	if [[ hh -le 9 ]]; then
	    hh=0${hh}
	fi
        fileg=JLD${pmonth}${pday}0000${rmonth}${rday}${hh}001
        if [ -f $dirin/$fileg ] ; then
	    echo "[$APPNAME] [3+6h] [$ryear/$rmonth/$rday] -- Processing file $fileg"
            Procfile $dirin/$fileg $ryear $rmonth $rday $hh
        else
	    echo "[$APPNAME] [3+6h] [$ryear/$rmonth/$rday] -- File $fileg not found"
            exit
        fi
    done

    # copy original 6h data
    filename=/data/inputs/metocean/rolling/atmos/ECMWF/IFS_010/1.0forecast/6h/grib/${pyear}${pmonth}${pday}/JLD${pmonth}${pday}0000${rmonth}${rday}*
    echo "[$APPNAME] [3+6h] [$ryear/$rmonth/$rday] -- Copying original files ${filename}"
    cp $filename $dirin
	
    # iterate over timesteps
    echo "[$APPNAME] [3+6h] [$ryear/$rmonth/$rday] -- Iterating over timesteps"
    for hh in $(seq 6 6 18) ; do

	# add a trailing 0 if the timestep is made by just 1 digit
	if [[ hh -le 9 ]]; then
	    hh=0${hh}
	fi
        fileg=JLD${pmonth}${pday}0000${rmonth}${rday}${hh}001
        if [ -f $dirin/$fileg ] ; then
	    echo "[$APPNAME] [3+6h] [$ryear/$rmonth/$rday] -- Processing file $fileg"
            Procfile $dirin/$fileg $ryear $rmonth $rday $hh
        else
	    echo "[$APPNAME] [3+6h] [$ryear/$rmonth/$rday] -- File $fileg not found"
            exit
        fi
    done
    
    # process the additional first timestep of the following day
    rnextdate=$(date -d "${ryear}-${rmonth}-${rday} +1 days" +%Y%m%d)
    nyear=${rnextdate:0:4}
    nmonth=${rnextdate:4:2}
    nday=${rnextdate:6:2}
    echo "[$APPNAME] [3+6h] -- Copying original files /data/inputs/metocean/rolling/atmos/ECMWF/IFS_010/1.0forecast/6h/grib/${pyear}${pmonth}${pday}/JLD${pmonth}${pday}0000${nmonth}${nday}00001"
    cp /data/inputs/metocean/rolling/atmos/ECMWF/IFS_010/1.0forecast/6h/grib/${pyear}${pmonth}${pday}/JLD${pmonth}${pday}0000${nmonth}${nday}00001 $dirin
    fileg=JLD${pmonth}${pday}0000${nmonth}${nday}00001
    Procfile $dirin/$fileg $nyear $nmonth $nday 00

    # merge timesteps
    echo "[$APPNAME] [3+6h] [$ryear/$rmonth/$rday] -- Merging timesteps..."
    fileout="${ryear}${rmonth}${rday}.nc"
    ncrcat -h ${dirwork}/MED_${ryear}-${rmonth}-${rday}-*.nc ${dirwork}/MED_${nyear}-${nmonth}-${nday}-00.nc ${dirwork}/${fileout}_MERGED 2>&1 | tee $LOGFILE

    # interpolate
    echo "[$APPNAME] [3+6h] [$ryear/$rmonth/$rday] -- Interpolating..."
    cdo -inttime,${ryear}-${rmonth}-${rday},00:00,1hour ${dirwork}/${fileout}_MERGED ${dirwork}/${fileout}_INTERP 2>&1 | tee $LOGFILE
    
    # remove last timestep
    echo "[$APPNAME] [3+6h] [$ryear/$rmonth/$rday] -- Removing the last timestep..."
    ncks -O -d time,1,24 ${dirwork}/${fileout}_INTERP ${dirout}/${fileout} 2>&1 | tee $LOGFILE
    
    # clean work directory
    echo "[$APPNAME] [3+6h] [$ryear/$rmonth/$rday]  -- Cleaning work directory..."
    if [[ $POSTCLEAN -eq 1 ]]; then
	rm ${dirwork}/*
    fi
    
    # check that file has been correctly generated
    if [[ ! -e ${dirout}/${fileout} ]]; then
	echo "[$APPNAME] [6h] [$ryear/$rmonth/$rday] -- ERROR: file ${fileout} not generated!"
	echo "[$APPNAME] [6h] [$ryear/$rmonth/$rday] -- ERROR: file ${fileout} not generated!" 2>&1 | tee $LOGFILE
    fi
    
    # move file to final directory
    if [[ $MOVE -eq 1 ]]; then
	mv ${dirout}/$fileout $finaldir
    fi

done


#####################################################
#
# GENERATE 6H DATA
# We generate data for days DAY+7 and DAY+8
#
#####################################################

# iterate over days
for d in $(seq 7 8); do

    # determine the day to produce
    refdate=$(date -d "${proddate}+${d}days" "+%Y%m%d")
    echo "[$APPNAME] [6h] -- Processing date $refdate"

    # read parameters
    ryear=${refdate:0:4}
    rmonth=${refdate:4:2}
    rday=${refdate:6:2}
	    
    # copy original data
    filename=/data/inputs/metocean/rolling/atmos/ECMWF/IFS_010/1.0forecast/6h/grib/${pyear}${pmonth}${pday}/JLD${pmonth}${pday}0000${rmonth}${rday}*
    echo "[$APPNAME] [6h] [$ryear/$rmonth/$rday] -- Copying original files ${filename}"
    cp $filename $dirin
	
    # iterate over timesteps
    echo "[$APPNAME] [6h] [$ryear/$rmonth/$rday] -- Iterating over timesteps"
    for hh in $(seq 0 6 18) ; do

	# add a trailing 0 if the timestep is made by just 1 digit
	if [[ hh -le 9 ]]; then
	    hh=0${hh}
	fi
	
        fileg=JLD${pmonth}${pday}0000${rmonth}${rday}${hh}001
        if [ -f $dirin/$fileg ] ; then
	    echo "[$APPNAME] [6h] [$ryear/$rmonth/$rday] -- Processing file $fileg"
            Procfile $dirin/$fileg $ryear $rmonth $rday $hh
        else
	    echo "[$APPNAME] [6h] [$ryear/$rmonth/$rday] -- File $fileg not found"
            exit
        fi
    done

    # add the additional first timestep of the following day
    rnextdate=$(date -d "${ryear}-${rmonth}-${rday} +1 days" +%Y%m%d)
    nyear=${rnextdate:0:4}
    nmonth=${rnextdate:4:2}
    nday=${rnextdate:6:2}
    echo "[$APPNAME] [6h] -- Copying original files /data/inputs/metocean/rolling/atmos/ECMWF/IFS_010/1.0forecast/6h/grib/${pyear}${pmonth}${pday}/JLD${pmonth}${pday}0000${nmonth}${nday}00001"
    cp /data/inputs/metocean/rolling/atmos/ECMWF/IFS_010/1.0forecast/6h/grib/${pyear}${pmonth}${pday}/JLD${pmonth}${pday}0000${nmonth}${nday}00001 $dirin
    fileg=JLD${pmonth}${pday}0000${rmonth}${rday}${hh}001
    Procfile $dirin/$fileg $nyear $nmonth $nday 00

    # merge timesteps
    echo "[$APPNAME] [6h] [$ryear/$rmonth/$rday] -- Merging timesteps..."
    fileout="${ryear}${rmonth}${rday}.nc"
    ncrcat -h ${dirwork}/MED_${ryear}-${rmonth}-${rday}-*.nc ${dirwork}/MED_${nyear}-${nmonth}-${nday}-00.nc ${dirwork}/${fileout}_MERGED 2>&1 | tee $LOGFILE

    # interpolate
    echo "[$APPNAME] [6h] [$ryear/$rmonth/$rday] -- Interpolating..."
    cdo -inttime,${ryear}-${rmonth}-${rday},00:00,1hour ${dirwork}/${fileout}_MERGED ${dirwork}/${fileout}_INTERP 2>&1 | tee $LOGFILE

    # remove last timestep
    echo "[$APPNAME] [6h] [$ryear/$rmonth/$rday] -- Removing last timestep..."
    ncks -O -d time,1,24 ${dirwork}/${fileout}_INTERP ${dirout}/${fileout} 2>&1 | tee $LOGFILE

    # clean work directory
    echo "[$APPNAME] [6h] [$ryear/$rmonth/$rday] -- Cleaning work directory..."
    if [[ $POSTCLEAN -eq 1 ]]; then
    	rm ${dirwork}/*
    fi

    # check that file has been correctly generated
    if [[ ! -e ${dirout}/${fileout} ]]; then
	echo "[$APPNAME] [6h] [$ryear/$rmonth/$rday] -- ERROR: file ${fileout} not generated!" 2>&1 | tee $LOGFILE
    fi
    
    # move file to final directory
    if [[ $MOVE -eq 1 ]]; then
	mv ${dirout}/$fileout $finaldir
    fi

done
