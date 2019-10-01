#!bin/bash

set -e
set -x

source ./private/credentials.bash
source ./setup.bash
source ./checks.bash
source ./diagnose_lysate.bash

CURRENTSETTINGS=$(echo "
Telegram Bot Connected
Looping every ${REFRESHRATE} seconds
LC screenshot sent every ${LCREFRESHRATE} mins
First Warning sent after ${WARNINGTIME} mins without new files
Additional warnings sent every ${TIMEBETWEENWARNS} Minutes")

curl -F chat_id="${TARGET_CHAT_ID}" \
    -F text="${CURRENTSETTINGS}" \
    https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage

check_flags () {
  if [[ ! -e ${FLAGS_DIR} ]] ; then mkdir ${FLAGS_DIR} ; fi 
  if [[ ! -e ${FLAGS_DIR}/stdstatus.log ]] ; then touch ${FLAGS_DIR}/stdstatus.log ; fi
  if [[ ! -e ${FLAGS_DIR}/.stdstatus.flag ]] ; then touch ${FLAGS_DIR}/.stdstatus.flag ; fi
  if [[ ! -e ${FLAGS_DIR}/.flag.flag ]] ; then touch ${FLAGS_DIR}/.flag.flag ; fi
  if [[ ! -e ${FLAGS_DIR}/.heatmap.flag ]] ; then touch ${FLAGS_DIR}/.heatmap.flag ; fi
  if [[ ! -e ${FLAGS_DIR}/sc.jpg ]] ; then touch ${FLAGS_DIR}/sc.jpg ; fi
  if [[ ! -e ${FLAGS_DIR}/message.log ]] ; then touch ${FLAGS_DIR}/message.log ; fi
}

screenshot_hplc () {
  ## Takes a screenshot of the hplc
  # Make sure RSA Keys are in place
  # the digital ocean tutorial is good to know how
  ssh "${LC_USER}@${LC_SERVER}" 'xwd -root -display :0 | convert - jpg:-  > screenshot.jpg'
  scp "${LC_USER}@${LC_SERVER}:screenshot.jpg" ${FLAGS_DIR}/sc.jpg
  touch ${FLAGS_DIR}/sc.jpg
  curl -F chat_id="${TARGET_CHAT_ID}" \
      -F document=@"${FLAGS_DIR}/sc.jpg" \
      -F caption="Current Screenshot of the LC" \
      https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument
}

send_heatmap () {
  # Makes the pictures of the XIC
  # TODO ADD HERE A NEW TEMP DIRECTORY AND AN EXIT TRAP
  ms_file="${@}"

  if [[ -f $ms_file ]] 
  then 
    mspicture.exe -z 1 --binSum --mzLow 300 --mzHigh 1500\
      -w 600 --height 1400 --outdir ${FLAGS_DIR} $ms_file
      # This loop is necessary because mspicture might output several images
      # When several ms1 scans are defined
      for i in $( find ${FLAGS_DIR}/*.ftms.png -newer ${FLAGS_DIR}/.heatmap.flag )
      do 
          echo "${i}" 
          curl -F chat_id="${TARGET_CHAT_ID}" \
              -F document=@"${i}" -F caption="${i}" \
              https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument
          touch ${FLAGS_DIR}/.heatmap.flag
      done
  else
    echo "Skipping ${ms_file} because the file does not exist"
  fi
}

report_standard () {
  # This Section sends the apexes list
  # TODO sort this in order of elution and perhaps print an expected value
  echo "" > ${FLAGS_DIR}/stdstatus.log
  echo "Found New Standard, Calculating Peak Apexes"
  msaccess "${@}" \
    -x "sic mzCenter=487.2567 radius=5 radiusUnits=ppm" \
    -x "sic mzCenter=669.8381 radius=5 radiusUnits=ppm" \
    -x "sic mzCenter=622.8535 radius=5 radiusUnits=ppm" \
    -x "sic mzCenter=636.8692 radius=5 radiusUnits=ppm" \
    -o 'tmp' -v

  echo "Peak Apexes (Retention Time, mins): " | tee --append ${FLAGS_DIR}/stdstatus.log
  echo "" >> ${FLAGS_DIR}/stdstatus.log

  APEX_RTS=$(find ${FLAGS_DIR} -regex .*.summary.* -newer ${FLAGS_DIR}/.stdstatus.flag -exec grep -oP "(?<=apex_rt: )\d+.\d+" {} \;)
  APEX_INT=$(find ${FLAGS_DIR} -regex .*.summary.* -newer ${FLAGS_DIR}/.stdstatus.flag -exec grep -oP "(?<=apex_intensity: )\d+" {} \;)

  for i in $APEX_RTS ; do echo print "${i} / 60" | \
    perl -l | tee --append ${FLAGS_DIR}/stdstatus.log ; done

  echo "" >> ${FLAGS_DIR}/stdstatus.log
  echo "Apex Intensities (10^6): " | tee --append ${FLAGS_DIR}/stdstatus.log
  echo "" >> ${FLAGS_DIR}/stdstatus.log

  for i in $APEX_INT ; do echo print "${i} / 1000000" | \
    perl -l | tee --append ${FLAGS_DIR}/stdstatus.log ; done

  curl -F chat_id="${TARGET_CHAT_ID}" -F text="$(cat ${FLAGS_DIR}/stdstatus.log)" \
         https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage

  date >> ${FLAGS_DIR}/perm_stdstatus.log
  cat ${FLAGS_DIR}/stdstatus.log >> ${FLAGS_DIR}/perm_stdstatus.log

  touch ${FLAGS_DIR}/.stdstatus.flag
}

while true; do
    check_flags

    if [[ $(find ${FLAGS_DIR}/sc.jpg -mmin +"${LCREFRESHRATE}") ]]
    then 
      screenshot_hplc
    fi

    sleep "${REFRESHRATE}"
    
    # Tries to find new files (more than 10 mb in size, newer than the last flag and mod more than a minute ago)
    # The more than a minute ago just prevents this to be triggered while the file is being scanned/generated
    new_ms_files=$(find "${DATA_DIR}" -name "*.raw" -size +10M -newer ${FLAGS_DIR}/.flag.flag -mmin +"${MINMINS}")

    if [[ -n "${new_ms_files}" ]]
    then
        ls -lcth $new_ms_files |& tee ${FLAGS_DIR}/message.log
        echo "Found Something"

        curl -F chat_id="${TARGET_CHAT_ID}" -F text="New File Found in the directory" \
            https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage
        curl -F chat_id="${TARGET_CHAT_ID}" -F text="$(cat ${FLAGS_DIR}/message.log)" \
           https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage

        for ms_file in $( echo $new_ms_files | grep -vP "std" | grep -vP "lysate.*.raw" )
        do
          send_heatmap "${ms_file}"
          run_crux "${ms_file}"
          report_crux "${ms_file}"
        done
        
        for standard_name in $(echo $new_ms_files | grep -P "std")
        do
          report_standard "${standard_name}"
        done

        for standard_name in $(echo $new_ms_files  | grep -P "lysate.*.raw")
        do
          "${standard_name}"
            # TODO find a way to store the lysate info or any output of find for that purpose
            echo "Found new lysate, running comet"

            run_crux "${standard_name}"
            report_crux "${standard_name}"
        done

        # Renews the mod date of the log file
        touch ${FLAGS_DIR}/.flag.flag
    
    # Warning section when too long has passed without modifications
    elif ! [[ $(find "${DATA_DIR}" -name "*.raw" -mmin -"${WARNINGTIME}") ]]
    then
        echo "There Seems to be inactivity"
        if ! [[ $(find ${FLAGS_DIR}/.warningflag.flag -mmin -"${TIMEBETWEENWARNS}") ]]
        then
            echo "Sending Warning due to inactivity"
            touch ${FLAGS_DIR}/.warningflag.flag
            curl -F chat_id="${TARGET_CHAT_ID}" \
                -F text="No new changes in ${WARNINGTIME} minutes,\
                you might want to check what went on ..." \
                https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage
        fi 
    else
        echo "Nothing New"
    fi
done


# TODO 
# During sample loading, a raw file of size 34 kb is generated and not modified until it starts scanning
# Could use the modification of such file to monitor the loading time
