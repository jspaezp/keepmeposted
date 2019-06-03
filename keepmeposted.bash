#!bin/bash

#set -x
#set -e

source ./private/credentials.bash
source ./checks.bash

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
  if [[ ! -e ./tmp/stdstatus.log ]] ; then touch ./tmp/stdstatus.log ; fi
  if [[ ! -e ./tmp/.stdstatus.flag ]] ; then touch ./tmp/.stdstatus.flag ; fi
  if [[ ! -e ./tmp/.flag.flag ]] ; then touch ./tmp/.flag.flag ; fi
  if [[ ! -e ./tmp/.heatmap.flag ]] ; then touch ./tmp/.heatmap.flag ; fi
  if [[ ! -e ./tmp/sc.jpg ]] ; then touch ./tmp/sc.jpg ; fi
  if [[ ! -e ./tmp/message.log ]] ; then touch ./tmp/message.log ; fi
}

screenshot_hplc () {
  ## Takes a screenshot of the hplc
  # Make sure RSA Keys are in place
  # the digital ocean tutorial is good to know how
  ssh hplc@172.16.0.106 'xwd -root -display :0 | convert - jpg:-  > screenshot.jpg'
  scp hplc@172.16.0.106:screenshot.jpg ./tmp/sc.jpg
  touch ./tmp/sc.jpg
  curl -F chat_id="${TARGET_CHAT_ID}" \
      -F document=@"./tmp/sc.jpg" \
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
      -w 600 --height 1400 --outdir ./tmp $ms_file
      # This loop is necessary because mspicture might output several images
      # When several ms1 scans are defined
      for i in $( find ./tmp/*.ftms.png -newer ./tmp/.heatmap.flag )
      do 
          echo "${i}" 
          curl -F chat_id="${TARGET_CHAT_ID}" \
              -F document=@"${i}" -F caption="${i}" \
              https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument
          touch ./tmp/.heatmap.flag
      done
  else
    echo "Skipping ${ms_file} because the file does not exist"
  fi
}

report_standard () {
  # This Section sends the apexes list
  # TODO sort this in order of elution and perhaps print an expected value
  echo "" > ./tmp/stdstatus.log
  echo "Found New Standard, Calculating Peak Apexes"
  msaccess "${@}" \
    -x "sic mzCenter=487.2567 radius=5 radiusUnits=ppm" \
    -x "sic mzCenter=669.8381 radius=5 radiusUnits=ppm" \
    -x "sic mzCenter=622.8535 radius=5 radiusUnits=ppm" \
    -x "sic mzCenter=636.8692 radius=5 radiusUnits=ppm" \
    -o 'tmp' -v

  echo "Peak Apexes (Retention Time, mins): " | tee --append ./tmp/stdstatus.log
  echo "" >> ./tmp/stdstatus.log

  APEX_RTS=$(find ./tmp -regex .*.summary.* -newer ./tmp/.stdstatus.flag -exec grep -oP "(?<=apex_rt: )\d+.\d+" {} \;)
  APEX_INT=$(find ./tmp -regex .*.summary.* -newer ./tmp/.stdstatus.flag -exec grep -oP "(?<=apex_intensity: )\d+" {} \;)

  for i in $APEX_RTS ; do echo print "${i} / 60" | \
    perl -l | tee --append ./tmp/stdstatus.log ; done

  echo "" >> ./tmp/stdstatus.log
  echo "Apex Intensities (10^6): " | tee --append ./tmp/stdstatus.log
  echo "" >> ./tmp/stdstatus.log

  for i in $APEX_INT ; do echo print "${i} / 1000000" | \
    perl -l | tee --append ./tmp/stdstatus.log ; done

  curl -F chat_id="${TARGET_CHAT_ID}" -F text="$(cat ./tmp/stdstatus.log)" \
         https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage

  touch ./tmp/.stdstatus.flag
}

while true; do
    check_flags

    if [[ $(find ./tmp/sc.jpg -mmin +"${LCREFRESHRATE}") ]]
    then 
      screenshot_hplc
    fi

    sleep "${REFRESHRATE}"
    
    # Tries to find new files (more than 10 mb in size, newer than the last flag and mod more than a minute ago)
    # The more than a minute ago just prevents this to be triggered while the file is being scanned/generated
    new_ms_files=$(find . -name "*.raw" -size +10M -newer ./tmp/.flag.flag -mmin +"${MINMINS}")

    if [[ -n "${new_ms_files}" ]]
    then
        ls -lcth $new_ms_files |& tee ./tmp/message.log
        echo "Found Something"

        curl -F chat_id="${TARGET_CHAT_ID}" -F text="New File Found in the directory" \
            https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage
        curl -F chat_id="${TARGET_CHAT_ID}" -F text="$(cat ./tmp/message.log)" \
           https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage

        for ms_file in $new_ms_files 
        do
          send_heatmap
        done
        
        for standard_name in $(echo $new_ms_files | grep -P "Standard")
        do
          report_standard "${standard_name}"
        done

        for standard_name in $(echo $new_ms_files | grep -P "lysate.*.raw")
        do
            # TODO find a way to store the lysate info or any output of find for that purpose
            echo "Found new lysate, running comet"
            echo "" > ./tmp/lysatestatus.log
            bash run_diagnose_lysate.bash "${standard_name}"
        done

        # Renews the mod date of the log file
        touch ./tmp/.flag.flag
    
    # Warning section when too long has passed without modifications
    elif ! [[ $(find . -name "*.raw" -mmin -"${WARNINGTIME}") ]]
    then
        echo "There Seems to be inactivity"
        if ! [[ $(find ./tmp/.warningflag.flag -mmin -"${TIMEBETWEENWARNS}") ]]
        then
            echo "Sending Warning due to inactivity"
            touch ./tmp/.warningflag.flag
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
