#!/bin/bash

### Definition of variables for later use
CPU=1
MEMR=1
SCRATCH=1
WALLT=1

### Reads the filename (e.g., myfile.inp)
echo "[PROMPT] Input the name of your file (including extension):"
read -e filename_path_input

### Splitting filename and extension from path; creating separate variables for filename and extension
filename_input=$(basename "$filename_path_input")
filename_length=${#filename_input}

if [[ -d ${filename_path_input::-$filename_length} ]]; then
    DATADIR="${filename_path_input%/*}"
else
    DATADIR=$(pwd)
fi

EXTENSION="${filename_input##*.}"
FILENAME="${filename_input%.*}"

### Check whether the input file exists.
if test -f "$filename_path_input"; then
    echo "[INFO] Successfully located '$DATADIR/$filename_input'."
else
    echo "[ERROR] Could not locate '$DATADIR/$filename_input', terminating process."
    exit 1
fi

### Option to specify an old checkpoint file (e.g., a .gbw file)
read -r -p "[PROMPT] Do you wish to specify an old checkpoint file (e.g., .gbw)? [Y/n]: " oldchk_response
oldchk_response=${oldchk_response,,}  # convert to lowercase

if [[ $oldchk_response =~ ^(yes|y| ) ]] || [[ -z $oldchk_response ]]; then
    echo "[PROMPT] Enter the old checkpoint file name (including extension, e.g., .gbw):"
    read -e oldchk_filename_input
    OLDCHK_FILENAME="${oldchk_filename_input%.*}"
    
    ### Validate if the old checkpoint file exists
    if test -f "$DATADIR/$oldchk_filename_input"; then
        echo "[INFO] Successfully located '$DATADIR/$oldchk_filename_input'."
        USE_OLDCHK=true
    else 
        echo "[ERROR] Could not locate '$DATADIR/$oldchk_filename_input', continuing without an old checkpoint file."
        USE_OLDCHK=false
    fi
else
    USE_OLDCHK=false
fi

### Write the submit file script
echo "[INFO] Generating submit script."

echo "#!/bin/bash
# Trap to copy back the output files from the scratch directory on job termination
trap 'cp -r \$SCRATCHDIR/{$FILENAME.out,$FILENAME.gbw} $DATADIR && clean_scratch' TERM 
# Copy the input file to the scratch directory
cp $DATADIR/$FILENAME.$EXTENSION \$SCRATCHDIR || exit 1" > ${DATADIR}/${FILENAME}.sh

if [[ $USE_OLDCHK == true ]]; then
    echo "[INFO] Adding command to copy old checkpoint file '$oldchk_filename_input' to scratch in '${FILENAME}.sh'"
    echo "cp $DATADIR/$oldchk_filename_input \$SCRATCHDIR || exit 1" >> ${DATADIR}/${FILENAME}.sh
fi

echo "cd \$SCRATCHDIR || exit 2
# Load ORCA module
module add orca/6.0.1
# Run ORCA using its full path
\$(which orca) $FILENAME.$EXTENSION > $FILENAME.out

# Copy .out and .gbw files to the data directory
for ext in out gbw; do
  if [ -e \"$FILENAME.\$ext\" ]; then
    cp \"$FILENAME.\$ext\" \"$DATADIR/\"
  else
    echo \"Warning: $FILENAME.\$ext not found and will not be copied.\"
  fi
done

# Create a compressed tarball of all files except .tmp files
archive_name=\"$FILENAME\_archive_\$(date +%Y%m%d%H%M%S).tar.gz\"
tar --exclude='*.tmp' -czf \"\$archive_name\" *

# Check if the archive was created successfully and copy it to the data directory
if [ -e \"\$archive_name\" ]; then
  cp \"\$archive_name\" \"$DATADIR/\"
else
  echo \"Warning: Archive \$archive_name was not created.\"
fi" >> ${DATADIR}/${FILENAME}.sh


echo "[INFO] Submit script '$DATADIR/${FILENAME}.sh' generated."

### Prompt user whether to submit the job
read -r -p "[PROMPT] Do you wish to submit '$filename_input' for calculation? [Y/n]: " response
response=${response,,}  # convert to lowercase

if [[ $response =~ ^(yes|y| ) ]] || [[ -z $response ]]; then
    :
else
    echo "[EOF] EXITING."
    exit 0	
fi

### Option to modify allocated resources
echo -e "--------------------\n[INFO] Currently allocated resources:\nncpus=$CPU\nmem=${MEMR}gb\nscratch_local=${SCRATCH}gb\nwalltime=${WALLT}:00:00\n--------------------"
read -r -p "[PROMPT] Do you wish to make any changes? [Y/n]: " response
response=${response,,}

if [[ $response =~ ^(yes|y| ) ]] || [[ -z $response ]]; then
    read -p "[ncpus]= " CPU
    until [[ $CPU =~ ^[+]?[0-9]+$ ]]; do 
        echo "[ERROR] Wrong format. Please input a positive integer."
        read -p "[ncpus]= " CPU
    done

    read -p "[mem]= " MEMR
    until [[ $MEMR =~ ^[+]?[0-9]+$ ]]; do
        echo "[ERROR] Wrong format. Please input a positive integer."
        read -p "[mem]= " MEMR
    done

    read -p "[scratch_local]= " SCRATCH
    until [[ $SCRATCH =~ ^[+]?[0-9]+$ ]]; do
        echo "[ERROR] Wrong format. Please input a positive integer."
        read -p "[scratch_local]= " SCRATCH
    done

    read -p "[walltime]= " WALLT
    until [[ $WALLT =~ ^[+]?[0-9]+$ ]]; do
        echo "[ERROR] Wrong format. Please input a positive integer."
        read -p "[walltime]= " WALLT
    done

    echo -e "--------------------\n[INFO] Newly allocated resources are:\nncpus=$CPU\nmem=${MEMR}gb\nscratch_local=${SCRATCH}gb\nwalltime=${WALLT}:00:00\n--------------------"
fi

### Execute submit file using qsub
echo "[INFO] Submitting Calculation."
qsub -l select=1:ncpus=${CPU}:mem=${MEMR}gb:scratch_local=${SCRATCH}gb -l walltime=${WALLT}:00:00 $DATADIR/$FILENAME.sh

### Uncomment the following lines if you wish to remove the submit script after execution
# echo "[INFO] Removing '$DATADIR/${FILENAME}.sh'."
# rm $DATADIR/$FILENAME.sh 


