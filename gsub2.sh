#!/bin/bash

###Definition of variables for later use
CPU=1
MEMR=1
SCRATCH=1
WALLT=1

###Reads filename (for example: myfile.gjf or myfile.com)
echo "[PROMPT] Input the name of your file (including extension):"
read -e filename_path_input

###Splitting filename.extension from path and creating separate variables from filename and extension
###If condition checks whether user has entered a path or not
filename_input=$(basename "$filename_path_input")

filename_length=${#filename_input}

if [[ -d ${filename_path_input::-$filename_length} ]]; then
	DATADIR="${filename_path_input%/*}"
else
	DATADIR=`pwd`
fi

EXTENSION="${filename_input##*.}"
FILENAME="${filename_input%.*}"

###Checking whether the inputted file exists. 
###Prevention of submitting non-existent files in case of typos etc.
if test -f "$filename_path_input"; then
	echo "[INFO] Succesfully located '~/$filename_input'."
else
	echo "[ERROR] Could not locate '~/$filename_input', terminating process."
	exit 1
fi

### Option to specify an old CHK file
read -r -p "[PROMPT] Do you wish to specify an old checkpoint file? [Y/n]:" oldchk_response
oldchk_response=${oldchk_response,,} ### Make lowercase

if [[ $oldchk_response =~ ^(yes|y| ) ]] || [[ -z $oldchk_response ]]; then
	echo "[PROMPT] Enter the old .chk file name (including .chk extension):"
	read -e oldchk_filename_input
	OLDCHK_FILENAME="${oldchk_filename_input%.*}"

	###Validate if the old checkpoint file exists
	if test -f "$DATADIR/$oldchk_filename_input"; then
		echo "[INFO] Successfully located '~/$oldchk_filename_input'."
		USE_OLDCHK=true
	else 
		echo "[ERROR] Could not locate '~/$oldchk_filename_input'. Continuing without an old .chk file."
		USE_OLDCHK=false
	fi
else
	USE_OLDCHK=false
fi

### Writes the submit file
echo "[INFO] Generating submit script."

echo "#!/bin/bash
trap 'cp -r $SCRATCHDIR/{$FILENAME.log,$FILENAME.chk} $DATADIR && clean_scratch' TERM 
cp $DATADIR/$FILENAME.$EXTENSION \$SCRATCHDIR || exit 1" > ${DATADIR}/${FILENAME}.sh

if [[ $USE_OLDCHK == true ]]; then
	echo "[INFO] Command to copy oldchk: '~/$OLDCHK_FILENAME.chk' to scratch added to '~/$FILENAME.sh'"
	echo "cp $DATADIR/$OLDCHK_FILENAME.chk \$SCRATCHDIR || exit 1" >> ${DATADIR}/${FILENAME}.sh
fi

echo "cd \$SCRATCHDIR || exit 2
module add g16-C.01
g16-prepare $FILENAME.$EXTENSION
g16 <$FILENAME.$EXTENSION > $FILENAME.log
cp $FILENAME.log $FILENAME.chk $DATADIR || export CLEAN_SCRATCH=false" >> ${DATADIR}/${FILENAME}.sh 

echo "[INFO] Submit script '~/$FILENAME.sh' generated."

### Prompts user if he really wishes to submit. Keeps the .sh file
read -r -p "[PROMPT] Do You wish to submit '~/$filename_input' for calculation? [Y/n]: " response
response=${response,,} ###Make lowercase

if [[ $response =~ ^(yes|y| ) ]] || [[ -z $response ]]; then
	:
else
	echo "[EOF] EXITING."
	exit 0	
fi

### Prompts user if he wishes to make any changes to resources allocated for the computation.
echo -e "--------------------\n[INFO]Currently allocated resources:\nncpus=$CPU\nmem=${MEMR}gb\nscratch_local=${SCRATCH}gb\nwalltime=${WALLT}:00:00\n--------------------"
read -r -p "[PROMPT]Do you wish to make any changes  ? [Y/n]" response
response=${response,,} ###Make lowercase

###If user chooses to make changes: Go through each resource and prompt user for a new value. 
###PUT IN ONLY INTEGER VALUES! And make sure they are correct! No error-proofing at this point yet.
if [[ $response =~ ^(yes|y| ) ]] || [[ -z $response ]]; then

	###Until loop forces the user to repeat his input if he uses the wrong file format. Error prevention.
        read -p "[ncpus]= " CPU

		until [[ $CPU =~ ^[+]?[0-9]+$ ]]
		do 
			echo "[ERROR] Wrong format. Please input a positive integer."
			read -p "[ncpus]= " CPU
 		done

	read -p "[mem]= " MEMR

                until [[ $MEMR =~ ^[+]?[0-9]+$ ]]
                do
                        echo "[ERROR] Wrong format. Please input a positive integer."
                        read -p "[mem]= " MEMR
                done

	read -p "[scratch_local]= " SCRATCH

                until [[ $SCRATCH =~ ^[+]?[0-9]+$ ]]
                do
                        echo "[ERROR] Wrong format. Please input a positive integer."
                        read -p "[scratch_local]= " SCRATCH
                done

	read -p "[walltime]= " WALLT

                until [[ $WALLT =~ ^[+]?[0-9]+$ ]]
                do
                        echo "[ERROR] Wrong format. Please input a positive integer."
                        read -p "[walltime]= " WALLT
                done

	echo -e "--------------------\n[INFO]Newly allocated resources are:\nncpus=$CPU\nmem=${MEMR}gb\nscratch_local=${SCRATCH}gb\nwalltime=${WALLT}:00:00\n--------------------"

else
        :
fi

### Executes submit file
echo "[INFO] Submitting Calculation."
qsub -l select=1:ncpus=${CPU}:mem=${MEMR}gb:scratch_local=${SCRATCH}gb -l walltime=${WALLT}:00:00 $DATADIR/$FILENAME.sh

###Remove comment if you wish to delete the submit script after execution
#echo "[INFO] Removing '~/$FILENAME.sh'."
#rm $DATADIR/$FILENAME.sh 

echo "[EOF] Submission Complete."

