#!/bin/bash

run_crux () {

  if [[ -e "$@" ]]; then
    FASTA_FILE=$(find $(dirname "$@") -regex ".*fasta$")
    if [[ ! -e "${FASTA_FILE}" ]]; then
      echo "Unable to find a correct fasta file for the search, returning to default"
      FASTA_FILE="${STP_FASTA}"
    else
      echo "Found fasta file in directory, will use it for search"
      echo "${FASTA_FILE}"
    fi
  else
    exit 0
  fi

  if [[ -e "$@" ]]; then
    PARAMS_FILE=$(find $(dirname "$@") -regex ".*params$")
    echo "Found parameters file in directory, will use it for search"
    echo "${PARAMS_FILE}"
  fi

  "${STP_CRUXBINARY}" pipeline \
       --output-dir ${STP_OUTDIR_CRUX} \
       --txt-output T \
       --output_txtfile 1 \
       --output_pepxmlfile 1 \
       --verbosity 40 \
       --variable_mod01 "15.9949 M 0 3 -1 0 0" \
       --fragment-tolerance 0.6 \
       --precursor-window 8 \
       --precursor-window-type ppm \
       --search-engine comet \
       --protein-enzyme trypsinp \
       --protein T \
       --decoy_search 2 \
       --overwrite T \
       --num-threads 2 \
       --parameter-file "${PARAMS_FILE}" \
       "$@" "${FASTA_FILE}"

  "${STP_CRUXBINARY}" extract-rows \
      ${STP_OUTDIR_CRUX}/percolator.target.peptides.txt \
      --header T "percolator q-value" \
      --comparison lt 0.01 > \
      ${STP_OUTDIR_CRUX}/qsig_percolator.target.peptides.txt

  "${STP_CRUXBINARY}" extract-rows \
      ${STP_OUTDIR_CRUX}/percolator.target.psms.txt \
      --header T "percolator q-value" \
      --comparison lt 0.01 > \
      ${STP_OUTDIR_CRUX}/qsig_percolator.target.psms.txt

  "${STP_CRUXBINARY}" extract-rows \
      ${STP_OUTDIR_CRUX}/percolator.target.proteins.txt \
      --header T "q-value" \
      --comparison lt 0.01 > \
      ${STP_OUTDIR_CRUX}/qsig_percolator.target.proteins.txt

  "${STP_CRUXBINARY}" extract-columns \
       ${STP_OUTDIR_CRUX}/qsig_percolator.target.peptides.txt sequence > \
       ${STP_OUTDIR_CRUX}/modsequences.txt

  "${STP_CRUXBINARY}" extract-columns \
      ${STP_OUTDIR_CRUX}/qsig_percolator.target.psms.txt sequence > \
      ${STP_OUTDIR_CRUX}/modsequencespsms.txt

  "${STP_CRUXBINARY}" extract-columns \
      ${STP_OUTDIR_CRUX}/qsig_percolator.target.proteins.txt ProteinGroupId > \
      ${STP_OUTDIR_CRUX}/proteinGroups.txt

  # TODO check if it is posible to just use the path to the file instead of changing
  # the working diretory
}


report_crux () {
  scratch=$(mktemp -d -t tmp.cruxreport.XXXXXXXXXX)
  exitttrap () {
    rm -rf "$scratch"
  }
  trap exittrap RETURN
  trap exittrap EXIT

  cd "${STP_OUTDIR}"

  echo "Number of Peptides: " >> "${scratch}"
  cat ${STP_OUTDIR_CRUX}/modsequencespsms.txt | \
      sort | uniq | wc -l >> "${scratch}"

  echo "Unique peptide sequences: " >> "${scratch}"
  cat ${STP_OUTDIR_CRUX}/modsequences.txt | \
      perl -p -e "s/(\[.*?\])|(\[.*?\])//g" | \
      sort | uniq | wc -l >> "${scratch}"

  echo "Number of protein groups: " >> "${scratch}"
  cat ${STP_OUTDIR_CRUX}/proteinGroups.txt | \
      sort | uniq | wc -l >> "${scratch}"

  curl -F chat_id="${TARGET_CHAT_ID}" \
    -F document=@"${scratch}" \
    https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument

  curl -F chat_id="${TARGET_CHAT_ID}" \
    -F text="$( cat "${scratch}")" \
    https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage
}

# TODO, crux writes a line 
# FATAL: The file ./tmp/crux_lysate_diagnose/comet.target.txt does not exist.
# whenever the search fails, check for that line

#curl -X POST \
#       -H 'Content-Type: application/json' \
#       -d '{"chat_id": "455502653", "text": "$(cat report.txt)", "disable_notification": true}' \
#       https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage
