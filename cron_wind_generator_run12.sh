#!/bin/bash -l
#
# This script contains all the operations needed to generate
# wind files for Mauritius in the morning. In the morning, at
# 9, we don't have files for the 00 run yet. So we use the 12
# run.
# Invoked with the date today (let's call it DAY, for simplicity),
# it will generate forecasts for the days:
# - DAY+1 -- using 1h data
# - DAY+2 -- using 1h data
# - DAY+3 -- using 1h data
# - DAY+4 -- using 1+3h data (1h until 6am included)
# - DAY+5 -- using 3h data
# - DAY+6 -- using 3h+6h data
# - DAY+7 -- using 6h
#
#

source $HOME/.bashrc

#####################################################
#
# INITIAL SETUP
#
#####################################################

# set the app name
APPNAME="CRON_WIND_RUN12"

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
dirin=${basedir}/workdir_12/IN/
dirwork=${basedir}/workdir_12/tmp/
dirout=${basedir}/workdir_12/OUT/
finaldir=/work/opa/witoil-dev/mauritius/winds/

# log file
LOGFILE="wind_generator_run12.log"
echo "=== Wind Generator -- run 12 -- $(date) ===" > $LOGFILE

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
    cdo -r -f nc -t ecmwf copy $fileg ${dirwork}/tmp1_${datef}_${hf}.nc
    
    # set the timestep
    cdo -settime,${hf}:00:00 -setdate,$dateff -settunits,hours -settaxis,1950-1-1,00:00 ${dirwork}/tmp1_${datef}_${hf}.nc ${dirwork}/tmp2_${datef}_${hf}.nc

    # crop
    cdo sellonlatbox,-180,180,-90,90 ${dirwork}/tmp2_${datef}_${hf}.nc ${dirwork}/tmp3_${datef}_${hf}.nc
 
    # select only the desired variables
    Cmd="ncks -h -O -d lon,57.,58. -d lat,-21.,-19. -v time,lon,lat,U10M,V10M ${dirwork}/tmp2_${datef}_${hf}.nc ${dirwork}/$ncfileo"
    eval $Cmd

}


#####################################################
#
# GENERATE 1H DATA
#
#####################################################


# iterate over days
for d in $(seq 1 3); do

    # determine the day to produce
    refdate=$(date -d "${proddate}+${d}days" "+%Y%m%d")
    echo "====================================================================="
    echo "[$APPNAME] -- Processing date $refdate"

    # read parameters
    ryear=${refdate:0:4}
    rmonth=${refdate:4:2}
    rday=${refdate:6:2}
	    
    # copy original data
    filename=/data/inputs/metocean/rolling/atmos/ECMWF/IFS_010/1.0forecast/1h/grib/${pyear}${pmonth}${pday}/JLS${pmonth}${pday}1200${rmonth}${rday}*
    echo "[$APPNAME] [$ryear/$rmonth/$rday] -- Copying original files ${filename}"
    cp $filename $dirin
	
    # iterate over timesteps
    echo "[$APPNAME] [$ryear/$rmonth/$rday] -- Iterating over timesteps"
    for hh in $(seq 0 23) ; do
	if [[ hh -le 9 ]]; then
	    hh=0${hh}
	fi
        fileg=JLS${pmonth}${pday}1200${rmonth}${rday}${hh}001
        if [ -f $dirin/$fileg ] ; then
	    echo "[$APPNAME] [$ryear/$rmonth/$rday] -- Processing file $fileg"
            Procfile $dirin/$fileg $ryear $rmonth $rday $hh
        else
	    echo "[$APPNAME] [$ryear/$rmonth/$rday] -- File $fileg not found"
            exit
        fi
    done

    # merge timesteps
    echo "[$APPNAME] [$ryear/$rmonth/$rday] -- Merging timesteps..."
    echo ${dirwork}/MED_${day}.nc
    fileout="${ryear}${rmonth}${rday}.nc"
    Cmd="ncrcat -h ${dirwork}/MED_${ryear}-${rmonth}-${rday}-*.nc ${dirout}/${fileout}"
    echo $Cmd
    eval $Cmd
    if [[ $? -eq 0 ]]; then
	echo "File ${fileout} successfully generated" >> $LOGFILE
    fi

    # clean work directory
    echo "[$APPNAME] -- Cleaning work directory..."
    if [[ $POSTCLEAN -eq 1 ]]; then
	rm ${dirwork}/*
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
#
#####################################################


# iterate over days
for d in $(seq 4 4); do

    # determine the day to produce
    refdate=$(date -d "${proddate}+${d}days" "+%Y%m%d")
    echo "====================================================================="
    echo "[$APPNAME] -- Processing date $refdate"

    # read parameters
    ryear=${refdate:0:4}
    rmonth=${refdate:4:2}
    rday=${refdate:6:2}
	    
    # copy original 1h data
    filename=/data/inputs/metocean/rolling/atmos/ECMWF/IFS_010/1.0forecast/1h/grib/${pyear}${pmonth}${pday}/JLS${pmonth}${pday}1200${rmonth}${rday}*
    echo "[$APPNAME] [$ryear/$rmonth/$rday] -- Copying original files ${filename}"
    cp $filename $dirin/
	
    # iterate over timesteps
    echo "[$APPNAME] [$ryear/$rmonth/$rday] -- Iterating over timesteps"
    for hh in $(seq 0 6) ; do
	if [[ hh -le 9 ]]; then
	    hh=0${hh}
	fi
        fileg=JLS${pmonth}${pday}1200${rmonth}${rday}${hh}001
        if [ -f $dirin/$fileg ] ; then
	    echo "[$APPNAME] [$ryear/$rmonth/$rday] -- Processing file $fileg"
            Procfile $dirin/$fileg $ryear $rmonth $rday $hh
        else
	    echo "[$APPNAME] [$ryear/$rmonth/$rday] -- File $fileg not found"
            exit
        fi
    done

    # copy original 3h data
    filename=/data/inputs/metocean/rolling/atmos/ECMWF/IFS_010/1.0forecast/3h/grib/${pyear}${pmonth}${pday}/JLD${pmonth}${pday}1200${rmonth}${rday}*
    echo "[$APPNAME] [$ryear/$rmonth/$rday] -- Copying original files ${filename}"
    cp $filename $dirin
	
    # iterate over timesteps
    echo "[$APPNAME] [$ryear/$rmonth/$rday] -- Iterating over timesteps"
    for hh in $(seq 9 3 21) ; do
	if [[ hh -le 9 ]]; then
	    hh=0${hh}
	fi
        fileg=JLD${pmonth}${pday}1200${rmonth}${rday}${hh}001
        if [ -f $dirin/$fileg ] ; then
	    echo "[$APPNAME] [$ryear/$rmonth/$rday] -- Processing file $fileg"
            Procfile $dirin/$fileg $ryear $rmonth $rday $hh
        else
	    echo "[$APPNAME] [$ryear/$rmonth/$rday] -- File $fileg not found"
            exit
        fi
    done
    
    # add the additional first timestep of the following day
    rnextdate=$(date -d "${ryear}-${rmonth}-${rday} +1 days" +%Y%m%d)
    nyear=${rnextdate:0:4}
    nmonth=${rnextdate:4:2}
    nday=${rnextdate:6:2}
    echo "[$APPNAME] -- Copying original files /data/inputs/metocean/rolling/atmos/ECMWF/IFS_010/1.0forecast/3h/grib/${pyear}${pmonth}${pday}/JLD${pmonth}${pday}0000${nmonth}${nday}00001"
    cp /data/inputs/metocean/rolling/atmos/ECMWF/IFS_010/1.0forecast/3h/grib/${pyear}${pmonth}${pday}/JLD${pmonth}${pday}0000${nmonth}${nday}00001 $dirin
    fileg=JLD${pmonth}${pday}0000${nmonth}${nday}00001
    Procfile $dirin/$fileg $nyear $nmonth $nday 00

    # merge timesteps
    echo "[$APPNAME] [$ryear/$rmonth/$rday] -- Merging timesteps..."
    echo ${dirwork}/MED_${day}.nc
    fileout="${ryear}${rmonth}${rday}.nc"
    # Cmd="ncrcat -h ${dirwork}/MED_${day}*.nc ${dirout}/$fileout"
    Cmd="ncrcat -h ${dirwork}/MED_${ryear}-${rmonth}-${rday}-*.nc ${dirwork}/MED_${nyear}-${nmonth}-${nday}-00.nc ${dirwork}/${fileout}_MERGED"
    echo $Cmd
    eval $Cmd

    # interpolate
    echo 'cdo -inttime,${ryear}-${rmonth}-${rday},00:00,1hour ${dirwork}/${fileout}_MERGED ${dirwork}/${fileout}_INTER'P
    cdo -inttime,${ryear}-${rmonth}-${rday},00:00,1hour ${dirwork}/${fileout}_MERGED ${dirwork}/${fileout}_INTERP
    
    # remove last timestep
    ncks -d time,1,24 ${dirwork}/${fileout}_INTERP ${dirout}/${fileout}
    
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


#####################################################
#
# GENERATE 3H DATA
#
#####################################################

# iterate over days
for d in $(seq 5 5); do

    # determine the day to produce
    refdate=$(date -d "${proddate}+${d}days" "+%Y%m%d")
    echo "====================================================================="
    echo "[$APPNAME] -- Processing date $refdate"

    # read parameters
    ryear=${refdate:0:4}
    rmonth=${refdate:4:2}
    rday=${refdate:6:2}
	    
    # copy original data
    filename=/data/inputs/metocean/rolling/atmos/ECMWF/IFS_010/1.0forecast/3h/grib/${pyear}${pmonth}${pday}/JLD${pmonth}${pday}1200${rmonth}${rday}*
    echo "[$APPNAME] [$ryear/$rmonth/$rday] -- Copying original files ${filename}"
    cp $filename $dirin
	
    # iterate over timesteps
    echo "[$APPNAME] [$ryear/$rmonth/$rday] -- Iterating over timesteps"
    for hh in $(seq 0 3 21) ; do
	if [[ hh -le 9 ]]; then
	    hh=0${hh}
	fi
        fileg=JLD${pmonth}${pday}1200${rmonth}${rday}${hh}001
        if [ -f $dirin/$fileg ] ; then
	    echo "[$APPNAME] [$ryear/$rmonth/$rday] -- Processing file $fileg"
            Procfile $dirin/$fileg $ryear $rmonth $rday $hh
        else
	    echo "[$APPNAME] [$ryear/$rmonth/$rday] -- File $fileg not found"
            exit
        fi
    done

    # add the additional first timestep of the following day
    rnextdate=$(date -d "${ryear}-${rmonth}-${rday} +1 days" +%Y%m%d)
    nyear=${rnextdate:0:4}
    nmonth=${rnextdate:4:2}
    nday=${rnextdate:6:2}
    echo "[$APPNAME] -- Copying original files /data/inputs/metocean/rolling/atmos/ECMWF/IFS_010/1.0forecast/3h/grib/${pyear}${pmonth}${pday}/JLD${pmonth}${pday}0000${nmonth}${nday}00001"
    cp /data/inputs/metocean/rolling/atmos/ECMWF/IFS_010/1.0forecast/3h/grib/${pyear}${pmonth}${pday}/JLD${pmonth}${pday}0000${nmonth}${nday}00001 $dirin
    fileg=JLD${pmonth}${pday}0000${nmonth}${nday}00001
    Procfile $dirin/$fileg $nyear $nmonth $nday 00

    # merge timesteps
    echo "[$APPNAME] [$ryear/$rmonth/$rday] -- Merging timesteps..."
    echo ${dirwork}/MED_${day}.nc
    fileout="${ryear}${rmonth}${rday}.nc"
    # Cmd="ncrcat -h ${dirwork}/MED_${day}*.nc ${dirout}/$fileout"
    Cmd="ncrcat -h ${dirwork}/MED_${ryear}-${rmonth}-${rday}-*.nc ${dirwork}/MED_${nyear}-${nmonth}-${nday}-00.nc ${dirwork}/${fileout}_MERGED"
    echo $Cmd
    eval $Cmd

    # interpolate
    echo "cdo -inttime,${ryear}-${rmonth}-${rday},00:00,1hour ${dirwork}/${fileout}_MERGED ${dirwork}/${fileout}_INTERP"
    cdo -inttime,${ryear}-${rmonth}-${rday},00:00,1hour ${dirwork}/${fileout}_MERGED ${dirwork}/${fileout}_INTERP

    # remove last timestep
    ncks -d time,1,24 ${dirwork}/${fileout}_INTERP ${dirout}/${fileout}
    
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


#####################################################
#
# GENERATE 3+6H DATA
#
#####################################################

# iterate over days
for d in $(seq 6 6); do

    # determine the day to produce
    refdate=$(date -d "${proddate}+${d}days" "+%Y%m%d")
    echo "====================================================================="
    echo "[$APPNAME] -- Processing date $refdate"

    # read parameters
    ryear=${refdate:0:4}
    rmonth=${refdate:4:2}
    rday=${refdate:6:2}
	    
    # copy original 3h data
    filename=/data/inputs/metocean/rolling/atmos/ECMWF/IFS_010/1.0forecast/3h/grib/${pyear}${pmonth}${pday}/JLD${pmonth}${pday}1200${rmonth}${rday}*
    echo "[$APPNAME] [$ryear/$rmonth/$rday] -- Copying original files ${filename}"
    cp $filename $dirin/
	
    # iterate over timesteps
    echo "[$APPNAME] [$ryear/$rmonth/$rday] -- Iterating over timesteps"
    for hh in $(seq 0 3 12) ; do
	if [[ hh -le 9 ]]; then
	    hh=0${hh}
	fi
        fileg=JLD${pmonth}${pday}1200${rmonth}${rday}${hh}001
        if [ -f $dirin/$fileg ] ; then
	    echo "[$APPNAME] [$ryear/$rmonth/$rday] -- Processing file $fileg"
            Procfile $dirin/$fileg $ryear $rmonth $rday $hh
        else
	    echo "[$APPNAME] [$ryear/$rmonth/$rday] -- File $fileg not found"
            exit
        fi
    done

    # copy original 6h data
    filename=/data/inputs/metocean/rolling/atmos/ECMWF/IFS_010/1.0forecast/6h/grib/${pyear}${pmonth}${pday}/JLD${pmonth}${pday}1200${rmonth}${rday}*
    echo "[$APPNAME] [$ryear/$rmonth/$rday] -- Copying original files ${filename}"
    cp $filename $dirin
	
    # iterate over timesteps
    echo "[$APPNAME] [$ryear/$rmonth/$rday] -- Iterating over timesteps"
    for hh in $(seq 18 18) ; do
	if [[ hh -le 9 ]]; then
	    hh=0${hh}
	fi
        fileg=JLD${pmonth}${pday}1200${rmonth}${rday}${hh}001
        if [ -f $dirin/$fileg ] ; then
	    echo "[$APPNAME] [$ryear/$rmonth/$rday] -- Processing file $fileg"
            Procfile $dirin/$fileg $ryear $rmonth $rday $hh
        else
	    echo "[$APPNAME] [$ryear/$rmonth/$rday] -- File $fileg not found"
            exit
        fi
    done
    
    # add the additional first timestep of the following day
    rnextdate=$(date -d "${ryear}-${rmonth}-${rday} +1 days" +%Y%m%d)
    nyear=${rnextdate:0:4}
    nmonth=${rnextdate:4:2}
    nday=${rnextdate:6:2}
    echo "[$APPNAME] -- Copying original files /data/inputs/metocean/rolling/atmos/ECMWF/IFS_010/1.0forecast/3h/grib/${pyear}${pmonth}${pday}/JLD${pmonth}${pday}0000${nmonth}${nday}00001"
    cp /data/inputs/metocean/rolling/atmos/ECMWF/IFS_010/1.0forecast/6h/grib/${pyear}${pmonth}${pday}/JLD${pmonth}${pday}0000${nmonth}${nday}00001 $dirin
    fileg=JLD${pmonth}${pday}0000${nmonth}${nday}00001
    Procfile $dirin/$fileg $nyear $nmonth $nday 00

    # merge timesteps
    echo "[$APPNAME] [$ryear/$rmonth/$rday] -- Merging timesteps..."
    echo ${dirwork}/MED_${day}.nc
    fileout="${ryear}${rmonth}${rday}.nc"
    # Cmd="ncrcat -h ${dirwork}/MED_${day}*.nc ${dirout}/$fileout"
    Cmd="ncrcat -h ${dirwork}/MED_${ryear}-${rmonth}-${rday}-*.nc ${dirwork}/MED_${nyear}-${nmonth}-${nday}-00.nc ${dirwork}/${fileout}_MERGED"
    echo $Cmd
    eval $Cmd

    # interpolate
    echo 'cdo -inttime,${ryear}-${rmonth}-${rday},00:00,1hour ${dirwork}/${fileout}_MERGED ${dirwork}/${fileout}_INTER'P
    cdo -inttime,${ryear}-${rmonth}-${rday},00:00,1hour ${dirwork}/${fileout}_MERGED ${dirwork}/${fileout}_INTERP
    
    # remove last timestep
    ncks -d time,1,24 ${dirwork}/${fileout}_INTERP ${dirout}/${fileout}
    
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


#####################################################
#
# GENERATE 6H DATA
#
#####################################################
 

# iterate over days
for d in $(seq 7 7); do

    # determine the day to produce
    refdate=$(date -d "${proddate}+${d}days" "+%Y%m%d")
    echo "====================================================================="
    echo "[$APPNAME] -- Processing date $refdate"

    # read parameters
    ryear=${refdate:0:4}
    rmonth=${refdate:4:2}
    rday=${refdate:6:2}
	    
    # copy original data
    filename=/data/inputs/metocean/rolling/atmos/ECMWF/IFS_010/1.0forecast/6h/grib/${pyear}${pmonth}${pday}/JLD${pmonth}${pday}1200${rmonth}${rday}*
    echo "[$APPNAME] [$ryear/$rmonth/$rday] -- Copying original files ${filename}"
    cp $filename $dirin
	
    # iterate over timesteps
    echo "[$APPNAME] [$ryear/$rmonth/$rday] -- Iterating over timesteps"
    for hh in $(seq 0 6 18) ; do
	
	if [[ hh -le 9 ]]; then
	    hh=0${hh}
	fi
	
        fileg=JLD${pmonth}${pday}1200${rmonth}${rday}${hh}001
        if [ -f $dirin/$fileg ] ; then
	    echo "[$APPNAME] [$ryear/$rmonth/$rday] -- Processing file $fileg"
            Procfile $dirin/$fileg $ryear $rmonth $rday $hh
        else
	    echo "[$APPNAME] [$ryear/$rmonth/$rday] -- File $fileg not found"
            exit
        fi
    done

    # add the additional first timestep of the following day
    rnextdate=$(date -d "${ryear}-${rmonth}-${rday} +1 days" +%Y%m%d)
    nyear=${rnextdate:0:4}
    nmonth=${rnextdate:4:2}
    nday=${rnextdate:6:2}
    echo "[$APPNAME] -- Copying original files /data/inputs/metocean/rolling/atmos/ECMWF/IFS_010/1.0forecast/6h/grib/${pyear}${pmonth}${pday}/JLD${pmonth}${pday}0000${nmonth}${nday}00001"
    cp /data/inputs/metocean/rolling/atmos/ECMWF/IFS_010/1.0forecast/3h/grib/${pyear}${pmonth}${pday}/JLD${pmonth}${pday}0000${nmonth}${nday}00001 $dirin
    fileg=JLD${pmonth}${pday}1200${rmonth}${rday}${hh}001
    Procfile $dirin/$fileg $nyear $nmonth $nday 00

    # merge timesteps
    echo "[$APPNAME] [$ryear/$rmonth/$rday] -- Merging timesteps..."
    echo ${dirwork}/MED_${day}.nc
    fileout="${ryear}${rmonth}${rday}.nc"
    Cmd="ncrcat -h ${dirwork}/MED_${ryear}-${rmonth}-${rday}-*.nc ${dirwork}/MED_${nyear}-${nmonth}-${nday}-00.nc ${dirwork}/${fileout}_MERGED"
    echo $Cmd
    eval $Cmd

    # interpolate
    echo 'cdo -inttime,${rhour}-${rmonth}-${rday},00:00,1hour ${dirwork}/${fileout}_MERGED ${dirwork}/${fileout}_INTER'P
    cdo -inttime,${ryear}-${rmonth}-${rday},00:00,1hour ${dirwork}/${fileout}_MERGED ${dirwork}/${fileout}_INTERP

    # remove last timestep
    ncks -d time,1,24 ${dirwork}/${fileout}_INTERP ${dirout}/${fileout}

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
