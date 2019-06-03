#!/bin/bash

set -x
set -e

run_crux () {
  "${STP_CRUXBINARY}" pipeline \
       --output-dir ${STP_OUTDIR} \
       --txt-output T \
       --output_txtfile 1 \
       --output_pepxmlfile 1 \
       --verbosity 40 \
       --variable_mod01 "15.9949 M 0 3 -1 0 0" \
       --fragment-tolerance 0.02 \
       --precursor-window 8 \
       --precursor-window-type ppm \
       --search-engine comet \
       --protein-enzyme trypsinp \
       --protein T \
       --decoy_search 2 \
       --overwrite T \
       --num-threads 2 \
       "$@" "${STP_FASTA}"
       #--require_variable_mod 1 \

  "${STP_CRUXBINARY}" extract-rows percolator.target.peptides.txt \
      --header T "percolator q-value" \
      --comparison lt 0.01 > qsig_percolator.target.peptides.txt

  "${STP_CRUXBINARY}" extract-rows percolator.target.psms.txt \
      --header T "percolator q-value" \
      --comparison lt 0.01 > qsig_percolator.target.psms.txt

  "${STP_CRUXBINARY}" extract-rows percolator.target.proteins.txt \
      --header T "q-value" \
      --comparison lt 0.01 > qsig_percolator.target.proteins.txt


  cd "${STP_OUTDIR}"

  # TODO check if it is posible to just use the path to the file instead of changing
  # the working diretory

  "${STP_CRUXBINARY}" extract-columns qsig_percolator.target.peptides.txt sequence > modsequences.txt
  "${STP_CRUXBINARY}" extract-columns qsig_percolator.target.psms.txt sequence > modsequencespsms.txt
  "${STP_CRUXBINARY}" extract-columns qsig_percolator.target.proteins.txt ProteinGroupId > proteinGroups.txt
}



set +x
set +e

report_crux () 
{
  scratch=$(mktemp -d -t tmp.cruxreport.XXXXXXXXXX)
  exitttrap () 
  {
    rm -rf "$scratch"
  }
  trap exittrap RETURN
  trap exittrap EXIT

  cd "${STP_OUTDIR}"

  echo "Number of Peptides: " >> "${scratch}"
  cat modsequencespsms.txt | sort | uniq | wc -l >> "${scratch}"

  echo "Unique peptide sequences: " >> "${scratch}"
  cat modsequences.txt | perl -p -e "s/(\[.*?\])|(\[.*?\])//g" \
    | sort | uniq | wc -l >> "${scratch}"

  echo "Number of protein groups: " >> "${scratch}"
  cat proteinGroups.txt | sort | uniq | wc -l >> "${scratch}"

  curl -F chat_id="${TARGET_CHAT_ID}" \
    -F document=@"${scratch}" \
    https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument
  curl -F chat_id="${TARGET_CHAT_ID}" \
    -F text="$( cat "${scratch}") \
    " https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage
}

report_crux 


# TODO, crux writes a line 
# FATAL: The file ./tmp/crux_lysate_diagnose/comet.target.txt does not exist.
# whenever the search fails, check for that line

#curl -X POST \
#       -H 'Content-Type: application/json' \
#       -d '{"chat_id": "455502653", "text": "$(cat report.txt)", "disable_notification": true}' \
#       https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage
