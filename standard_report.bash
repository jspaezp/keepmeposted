
report_standard () {
  # This Section sends the apexes list
  # TODO sort this in order of elution and perhaps print an expected value

  [[ -e "${@}" ]] || return 1

  SCRATCH=$(mktemp -d -t tmp.irtreport.XXXXXXXXXX)

  trap "echo \"removing ${SCRATCH}\" ; rm -rf \"${SCRATCH}\"" RETURN

  #echo "${@}" > ${FLAGS_DIR}/stdstatus.log
  #echo "Found New Standard, Calculating Peak Apexes"
  #msaccess "${@}" \
  #  -x "sic mzCenter=487.2567 radius=5 radiusUnits=ppm" \
  #  -x "sic mzCenter=669.8381 radius=5 radiusUnits=ppm" \
  #  -x "sic mzCenter=622.8535 radius=5 radiusUnits=ppm" \
  #  -x "sic mzCenter=636.8692 radius=5 radiusUnits=ppm" \
  #  -o "${SCRATCH}" -v

  #echo "Peak Apexes (Retention Time, mins): " | tee --append ${FLAGS_DIR}/stdstatus.log
  #echo "" >> ${FLAGS_DIR}/stdstatus.log

  #APEX_RTS=$(find ${SCRATCH} -regex .*.summary.* -exec grep -oP "(?<=apex_rt: )\d+.\d+" {} \;)
  #APEX_INT=$(find ${SCRATCH} -regex .*.summary.* -exec grep -oP "(?<=apex_intensity: )\d+" {} \;)

  #for i in $APEX_RTS ; do echo print "${i} / 60" | \
  #  perl -l | tee --append ${FLAGS_DIR}/stdstatus.log ; done

  #echo "" >> ${FLAGS_DIR}/stdstatus.log
  #echo "Apex Intensities (10^6): " | tee --append ${FLAGS_DIR}/stdstatus.log
  #echo "" >> ${FLAGS_DIR}/stdstatus.log

  #for i in $APEX_INT ; do echo print "${i} / 1000000" | \
  #  perl -l | tee --append ${FLAGS_DIR}/stdstatus.log ; done

  #curl -F chat_id="${TARGET_CHAT_ID}" -F text="$(cat ${FLAGS_DIR}/stdstatus.log)" \
  #       https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage

  #date >> ${FLAGS_DIR}/perm_stdstatus.log
  #cat ${FLAGS_DIR}/stdstatus.log >> ${FLAGS_DIR}/perm_stdstatus.log

  ## Experimental section to plot using skyline
  "${STP_SKYLINE_RUNNER}" \
    --in="${STP_SKYLINE_BASE_FILE}" \
    --import-file="${@}" \
    --chromatogram-file="${SCRATCH}/transitions.tsv" \
    --chromatogram-products

  sleep 5

  "${STP_SKYLINE_RUNNER}" \
    --import-all="$(dirname "${@}")" \
    --import-on-or-after="$(date --date '2 weeks ago')" \
    --import-filename-pattern=".*(std|Std).*" \
    --in="${STP_SKYLINE_BASE_FILE}" \
    --out="${SCRATCH}/sky.sky" \
    --chromatogram-file="${SCRATCH}/transitions_history.tsv" \
    --chromatogram-products
    
  #"${STP_SKYLINE_RUNNER}" \
  #  --in="${STP_SKYLINE_PERM_FILE}" \
  #  --import-file="${@}" \
  #  --chromatogram-file="${SCRATCH}/transitions_history.tsv" \
  #  --chromatogram-products --save
    
  "${STP_RSCRIPT_EXE}" \
    --vanilla ./utils/plot_sky_report.R \
    --file "${SCRATCH}/transitions.tsv" \
    --out "${SCRATCH}/out.png"

  "${STP_RSCRIPT_EXE}" \
    --vanilla ./utils/plot_sky_history.R \
    --file "${SCRATCH}/transitions_history.tsv" \
    --out_int "${SCRATCH}/out_int_history.png" \
    --out_rt "${SCRATCH}/out_rt_history.png"

  # start "${SCRATCH}/out_int_history.png"
  # start "${SCRATCH}/out_rt_history.png"

  curl -F chat_id="${TARGET_CHAT_ID}" \
    -F document=@"${SCRATCH}/out.png" -F caption="${@}" \
    https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument

  curl -F chat_id="${TARGET_CHAT_ID}" \
    -F document=@"${SCRATCH}/out_int_history.png" -F caption="Standard Int History" \
    https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument

  curl -F chat_id="${TARGET_CHAT_ID}" \
    -F document=@"${SCRATCH}/out_rt_history.png" -F caption="Standard RT History" \
    https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument

  touch ${FLAGS_DIR}/.stdstatus.flag
  return 0
}