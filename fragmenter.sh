#!/bin/bash

module add g16-C.01

if [ $# -lt 1 ]; then
  echo "Usage: $0 <logfile> [existing input file with fragment info]"
  exit 1
fi

LOGFILE="$1"
EXISTING_INPUT="$2"
if [ ! -f "$LOGFILE" ]; then
  echo "[ERROR] Log file '$LOGFILE' not found."
  exit 1
fi

ARCHIVE=$(pluck "$LOGFILE" | tr -d '\n')
if [ -z "$ARCHIVE" ]; then
  echo "[ERROR] Failed to extract calculation archive."
  exit 1
fi

METHOD=$(echo "$ARCHIVE" | grep -oP '(?<=\\#p ).+?(?=\\)')
CHARGE=$(echo "$ARCHIVE" | grep -oP '(?<=\\)[-]?\d+(?=,)')
MULTIPLICITY=$(echo "$ARCHIVE" | grep -oP '(?<=,)[-]?\d+(?=\\)')
ATOMS=$(echo "$ARCHIVE" | grep -oP '[A-Z][a-z]*,[-.\d]+,[-.\d]+,[-.\d]+(?=\\)')

TOTAL_ATOMS=$(echo "$ATOMS" | wc -l)

echo "Method: $METHOD"
echo "Charge: $CHARGE"
echo "Multiplicity: $MULTIPLICITY"
echo "Total Atoms: $TOTAL_ATOMS"
echo "Atoms and Coordinates:"
echo "$ATOMS" | nl -w2 -s': '

expand_ranges() {
  local INPUT="$1"
  echo "$INPUT" | awk -F, '{
    for (i = 1; i <= NF; i++) {
      if ($i ~ /-/) {
        split($i, range, "-");
        for (j = range[1]; j <= range[2]; j++) printf j " ";
      } else {
        printf $i " ";
      }
    }
  }'
}

if [ -n "$EXISTING_INPUT" ]; then
  if [ ! -f "$EXISTING_INPUT" ]; then
    echo "[ERROR] Specified input file '$EXISTING_INPUT' not found."
    exit 1
  fi

  echo "[INFO] Reading fragment information from '$EXISTING_INPUT'."
  EXISTING_ATOMS=$(grep -E "^[[:space:]]*[A-Z]\(Fragment=[0-9]+.*\)" "$EXISTING_INPUT")
  EXISTING_TOTAL_ATOMS=$(echo "$EXISTING_ATOMS" | wc -l)

  if [ "$EXISTING_TOTAL_ATOMS" -ne "$TOTAL_ATOMS" ]; then
    echo "[ERROR] Atom count mismatch between '$LOGFILE' and '$EXISTING_INPUT'."
    exit 1
  fi

  FRAGMENTS=()
  for ((i=1; i<=TOTAL_ATOMS; i++)); do
    FRAGMENT=$(echo "$EXISTING_ATOMS" | sed -n "${i}p" | grep -oP '(?<=Fragment=)[0-9]+')
    if [ -n "$FRAGMENT" ]; then
      FRAGMENTS[$FRAGMENT]="${FRAGMENTS[$FRAGMENT]} $i"
    else
      echo "[ERROR] Missing fragment information for atom $i in '$EXISTING_INPUT'."
      exit 1
    fi
  done

  echo "[INFO] Fragment assignments loaded from '$EXISTING_INPUT':"
  for FRAG in "${!FRAGMENTS[@]}"; do
    echo "Fragment $FRAG: ${FRAGMENTS[$FRAG]}"
  done
else
  while true; do
    echo "How many fragments do you have?"
    read -r NUM_FRAGMENTS

    if [[ "$NUM_FRAGMENTS" =~ ^[0-9]+$ ]] && [ "$NUM_FRAGMENTS" -gt 0 ]; then
      break
    else
      echo "[ERROR] Invalid number of fragments. Please enter a positive integer."
    fi
  done

  declare -a FRAGMENTS
  REMAINING_ATOMS=$(seq 1 $TOTAL_ATOMS)
  ASSIGNED_ATOMS=""

  for ((i=1; i<=NUM_FRAGMENTS; i++)); do
    if [[ $i -eq $NUM_FRAGMENTS ]]; then
      while true; do
        echo "For the last fragment, do you want to include all remaining atoms? (y/n)"
        read -r INCLUDE_REMAINING
        if [[ "$INCLUDE_REMAINING" =~ ^[yYnN]$ ]]; then
          if [[ "$INCLUDE_REMAINING" == "y" || "$INCLUDE_REMAINING" == "Y" ]]; then
            FRAGMENTS[$i]="$REMAINING_ATOMS"
            ASSIGNED_ATOMS="$ASSIGNED_ATOMS $REMAINING_ATOMS"
            REMAINING_ATOMS=""
          fi
          break
        else
          echo "[ERROR] Invalid response. Please enter 'y' or 'n'."
        fi
      done
      if [[ "$INCLUDE_REMAINING" == "y" || "$INCLUDE_REMAINING" == "Y" ]]; then
        continue
      fi
    fi

    while true; do
      echo "Enter indices for fragment $i (e.g., 1-6,11-16,20):"
      read -r FRAGMENT

      EXPANDED=$(expand_ranges "$FRAGMENT")

      # Validate expanded indices
      VALID=1
      OVERLAPS=""
      for INDEX in $EXPANDED; do
        if ! [[ "$INDEX" =~ ^[0-9]+$ ]] || [ "$INDEX" -lt 1 ] || [ "$INDEX" -gt "$TOTAL_ATOMS" ]; then
          VALID=0
          break
        fi
        if [[ " $ASSIGNED_ATOMS " =~ " $INDEX " ]]; then
          OVERLAPS+="$INDEX ";
          VALID=0
        fi
      done

      if [ "$VALID" -eq 0 ]; then
        if [ -n "$OVERLAPS" ]; then
          echo "[ERROR] Overlapping indices detected: $OVERLAPS. Please enter non-overlapping indices."
        else
          echo "[ERROR] Invalid indices detected. Ensure all indices are numbers between 1 and $TOTAL_ATOMS. Please try again."
        fi
      elif [ -z "$EXPANDED" ]; then
        echo "[ERROR] No valid indices provided. Please try again."
      else
        break
      fi
    done

    echo "[DEBUG] Expansion: $EXPANDED"
    FRAGMENTS[$i]="$EXPANDED"

    # Update assigned and remaining atoms
    ASSIGNED_ATOMS="$ASSIGNED_ATOMS $EXPANDED"
    REMAINING_ATOMS=$(echo "$REMAINING_ATOMS" | tr ' ' '\n' | grep -v -w -F -f <(echo "$EXPANDED" | tr ' ' '\n') | tr '\n' ' ')

    echo "[DEBUG] Remaining atoms after assigning fragment $i: $REMAINING_ATOMS"
  done

  if [ -n "$REMAINING_ATOMS" ]; then
    echo "[ERROR] Not all atoms were assigned to fragments: $REMAINING_ATOMS"
    exit 1
  fi

  echo "[DEBUG] Fragment assignments:"
  for ((i=1; i<=NUM_FRAGMENTS; i++)); do
    echo "Fragment $i: ${FRAGMENTS[$i]}"
  done
fi

while true; do
  echo "Enter the output GJF filename (!without extension!):"
  read -r OUTPUT_FILE
  if [ -n "$OUTPUT_FILE" ]; then
    break
  else
    echo "[ERROR] Filename cannot be empty. Please try again."
  fi
done

{
  echo "%chk=$OUTPUT_FILE.chk"
  echo "#p $METHOD"

  echo ""
  echo "Generated Gaussian Input"
  echo ""

  echo "$CHARGE $MULTIPLICITY"

  for FRAG in "${!FRAGMENTS[@]}"; do
    for INDEX in ${FRAGMENTS[$FRAG]}; do
      LINE=$(echo "$ATOMS" | sed -n "${INDEX}p")
      ELEMENT=$(echo "$LINE" | cut -d',' -f1)
      COORD1=$(echo "$LINE" | cut -d',' -f2)
      COORD2=$(echo "$LINE" | cut -d',' -f3)
      COORD3=$(echo "$LINE" | cut -d',' -f4)
      echo "$ELEMENT(Fragment=$FRAG)   0   $COORD1   $COORD2   $COORD3"
    done
  done

  echo ""
  echo ""
} > "$OUTPUT_FILE.gjf"

echo "GJF file '$OUTPUT_FILE' created successfully."
