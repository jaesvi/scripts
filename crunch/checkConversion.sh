#!/bin/bash

## This script has to be executed from the
## sequence run output directory
## (there were the Data/Intensities dir)

SEPSTR='##'
RUNDIR=$PWD
RUNNAM=`basename $RUNDIR`
SSHEET=$RUNDIR'/SampleSheet.csv'
CONV_L=$RUNDIR'/conversionLog.txt'
CONV_E=$RUNDIR'/conversionError.txt'
RUNHMF=`cat $SSHEET | grep 'ExperimentName' | cut -d',' --output-delimiter ': ' -f 2`
RUNNAS=$RUNHMF'__'$RUNNAM


echo "";
echo "$SEPSTR currentDirectory pwd"
echo $PWD
#echo ""

echo "$SEPSTR runName SEQ"
echo $RUNNAM
#echo ""

echo "$SEPSTR runName HMF"
echo "$RUNHMF"
#echo ""

echo "$SEPSTR conversionLog cat";
cat $CONV_L; 
#echo ""

echo "$SEPSTR conversionError tail"
cat $CONV_E | tail -1; 
#echo ""

echo "$SEPSTR NAS NAME"
echo $RUNNAS

## print readme file path if present
README_FILE=$RUNDIR"/README"
if [[ -e $README_FILE ]]; 
then
    echo "# [README] $READMEFILE";
fi

echo "";
