#!bin/bash

set -e
set -x

source ./private/credentials.bash
source ./setup.bash
source ./checks.bash
source ./diagnose_lysate.bash
source ./standard_report.bash

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
    mspicture.exe -z 1 --binSum --mzLow 300 --mzHigh 1500 \
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
    return 0
  fi
}



main_loop () {
  while true; do
      date

      if [[ $(find ${FLAGS_DIR}/sc.jpg -mmin +"${LCREFRESHRATE}") ]]
      then 
        screenshot_hplc
      fi

      [[ -z "${FIRST_PASS_DONE}" ]] && FIRST_PASS_DONE=1 || sleep "${REFRESHRATE}"
      
      # Tries to find new files (more than 10 mb in size, newer than the last flag and mod more than a minute ago)
      # The more than a minute ago just prevents this to be triggered while the file is being scanned/generated
      new_ms_files=$(find "${DATA_DIR}" -name "*.raw" -size +10M -newer ${FLAGS_DIR}/.flag.flag -mmin +"${MINMINS}")

      if [[ -n "${new_ms_files}" ]]
      then
          # Renews the mod date of the log file
          touch ${FLAGS_DIR}/.flag.flag

          ls -lcth $new_ms_files |& tee ${FLAGS_DIR}/message.log
          echo "Found Something"

          # curl -F chat_id="${TARGET_CHAT_ID}" -F text="New File Found in the directory" \
          #     https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage
          curl -F chat_id="${TARGET_CHAT_ID}" -F text="$(cat ${FLAGS_DIR}/message.log)" \
             https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage

          standard_files=$( for i in $new_ms_files ; do echo "${i}" | grep -P "Standards" ; done )
          wash_files=$( for i in $standard_files ; do echo "${i}" | grep -P "wash" ; done )
          non_wash_standard_files=$( for i in $standard_files ; do echo "${i}" | grep -vP "wash" ; done )
          lysate_standards=$( for i in $non_wash_standard_files ; do echo "${i}" | grep -P "lysate.*.raw" ; done )
          non_standard_files=$( for i in $new_ms_files ; do echo "${i}" | grep -vP "Standards" ; done )

          for wash_file in $( for i in $wash_files ; do echo "${i}" ; done )
          do
            echo "Sending heatmap for ${wash_file}"
            send_heatmap "${wash_file}"
          done

          for ms_file in $( for i in $non_standard_files ; do echo "${i}" ; done )
          do
            echo "Running steps for ${ms_file}"

            send_heatmap "${ms_file}"
            run_crux "${ms_file}" && report_crux "${ms_file}"
          done
          
          for irt_standard_name in $( for i in $new_ms_files ; do echo "${i}" | grep -P "std|Std" ; done )
          do
            echo "Running report for ${irt_standard_name}"
            report_standard "${irt_standard_name}"
          done

          for std_lysate_name in $( for i in $lysate_standards ; do echo "${i}" ; done )
          do
            send_heatmap "${std_lysate_name}"
            echo "Found new lysate, running comet"

            run_crux "${std_lysate_name}" && report_crux "${std_lysate_name}"
          done

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
}

check_flags

main_loop || { 
  env 
  curl -F chat_id="${TARGET_CHAT_ID}" \
    -F text="Main Loop finished, check if something went wrong" \
    https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage ; }

# TODO 
# During sample loading, a raw file of size 34 kb is generated and not modified until it starts scanning
# Could use the modification of such file to monitor the loading time
