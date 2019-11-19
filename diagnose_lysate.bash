#!/bin/bash

run_crux () {

  if [[ -e "$@" ]]; then
    FASTA_FILE=$(find $(dirname "$@") -maxdepth 1 -regex ".*fasta$")
    if [[ -e "${FASTA_FILE}" ]]; then
      echo "Found fasta file in directory, will use it for search"
      echo "${FASTA_FILE}"
      DEFAULTED_FASTA=0
    else
      echo "Unable to find a correct fasta file for the search, returning to default"
      FASTA_FILE="${STP_FASTA}"
      DEFAULTED_FASTA=1     
    fi
  else
    return 1
  fi

  if [[ -e "$@" ]]; then
    PARAMS_FILE=$(find $(dirname "$@") -maxdepth 1 -regex ".*params$" )

    if [[ -e "${PARAMS_FILE}" ]]; then
      echo "Found parameters file in directory, will use it for search"
      echo "${PARAMS_FILE}"
      DEFAULTED_PARAMS=0
    else
      PARAMS_FILE="${STP_DEF_CRUXPARAMS}"
      echo "Not found parameters file in directory, will use the default"
      echo "${PARAMS_FILE}"
      DEFAULTED_PARAMS=1
    fi
  fi

  if [[ $DEFAULTED_PARAMS -eq 1 ]] && [[ $DEFAULTED_FASTA -eq 1 ]] ; then return 1 ; fi

  "${STP_CRUXBINARY}" pipeline \
      --output-dir ${STP_OUTDIR_CRUX} \
      --txt-output T \
      --output_txtfile 1 \
      --output_pepxmlfile 1 \
      --protein T \
      --decoy_search 2 \
      --overwrite T \
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

  "${STP_RSCRIPT_EXE}" \
    --vanilla ./utils/plot_mass_shifts.R \
    --file "${STP_OUTDIR_CRUX}/qsig_percolator.target.psms.txt" \
    --out "${STP_OUTDIR_CRUX}/out_png.png"

  # TODO check if it is posible to just use the path to the file instead of changing
  # the working diretory
}


report_crux () {
  scratch=$(mktemp -d -t tmp.cruxreport.XXXXXXXXXX)
  out_file=$(mktemp -p ${scratch} -t tmp.cruxreport.XXXXXXXXXX)

  trap "echo \"removing ${scratch}\" ; rm -rf \"${scratch}\"" RETURN

  echo "Number of Peptides: " >> "${out_file}"
  cat ${STP_OUTDIR_CRUX}/modsequencespsms.txt | \
      sort | uniq | wc -l >> "${out_file}"

  echo "Unique peptide sequences: " >> "${out_file}"
  cat ${STP_OUTDIR_CRUX}/modsequences.txt | \
      perl -p -e "s/(\[.*?\])|(\[.*?\])//g" | \
      sort | uniq | wc -l >> "${out_file}"

  echo "Number of protein groups: " >> "${out_file}"
  cat ${STP_OUTDIR_CRUX}/proteinGroups.txt | \
      sort | uniq | wc -l >> "${out_file}"

  echo "Modified AA count in PSM per modification mass: " >> "${out_file}"
  cat ${STP_OUTDIR_CRUX}/modsequencespsms.txt | \
      grep -oP "\[.*?\]" | sort | uniq -c >> "${out_file}"

  echo "Modified AA count in Peptide per modification mass: " >> "${out_file}"
  cat ${STP_OUTDIR_CRUX}/modsequences.txt | \
      grep -oP "\[.*?\]" | sort | uniq -c >> "${out_file}"
  
  echo "Number of peptides per missed cleavage (trypsin): " >> "${out_file}"
  cat ${STP_OUTDIR_CRUX}/modsequences.txt | \
      grep -P "[KR]\s+$" | \
      sed 's/[^KR]//g' | \
      awk '{ print length - 1}' |\
      sort | uniq -c >> "${out_file}"

  #curl -F chat_id="${TARGET_CHAT_ID}" \
  #  -F document=@"${out_file}" \
  #  https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument

  curl -F chat_id="${TARGET_CHAT_ID}" \
    -F text="$( cat "${out_file}")" \
    https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage

  curl -F chat_id="${TARGET_CHAT_ID}" \
    -F document=@"${STP_OUTDIR_CRUX}/out_png.png" -F caption="Mass Shifts" \
    https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument
}

# TODO, crux writes a line 
# FATAL: The file ./tmp/crux_lysate_diagnose/comet.target.txt does not exist.
# whenever the search fails, check for that line

#curl -X POST \
#       -H 'Content-Type: application/json' \
#       -d '{"chat_id": "455502653", "text": "$(cat report.txt)", "disable_notification": true}' \
#       https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage
