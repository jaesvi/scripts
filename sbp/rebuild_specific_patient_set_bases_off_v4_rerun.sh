#!/usr/bin/env bash

set=$1 && shift

if [ -z "$set" ]; then
    echo "[ERROR] No set provided to rebuild_set_based_off_v4_rerun. Exiting"
    exit 1
fi

download_path=/data/schuberg/new_runs_v4_specific_patients
echo "[INFO] Downloading set ${set} to ${download_path}"
download_set -s ${set} -p ${download_path}

echo "[INFO] Copying bachelor for ${set} from /data/cpct/runs"
bachelor_dir=/data/cpct/runs/${set}/bachelor
if [ ! -d ${bachelor_dir} ]; then
    echo "[ERROR] Bachelor does not exist: ${bachelor_dir}. Exiting"
    exit 1
fi

cp -r ${bachelor_dir} ${download_path}/${set}

echo "[INFO] Running gridss somatic filtering for ${set}"
do_run_gridss_somatic_filter ${download_path}/${set}

echo "[INFO] Running latest purple for ${set}"
do_run_purple_no_db ${download_path}/${set}

echo "[INFO] Running CHORD on ${set}"
#echo "[INFO] Running CHORD on ${set}. Planning is to rerun chord in batch mode later on!"
run_chord_prod ${download_path}/${set}
