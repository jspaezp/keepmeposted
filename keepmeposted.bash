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

if ! [[ -e ./tmp/stdstatus.log ]] ; then touch ./tmp/stdstatus.log ; fi
if ! [[ -e ./tmp/.flag.flag ]] ; then touch ./tmp/.flag.flag ; fi
if ! [[ -e ./tmp/sc.jpg ]] ; then touch ./tmp/sc.jpg ; fi
if ! [[ -e ./tmp/message.log ]] ; then touch ./tmp/message.log ; fi


while true; do
    sleep "${REFRESHRATE}"
    
    # Tries to find new files (more than 10 mb in size, newer than the last flag and mod more than a minute ago)
    # The more than a minute ago just prevents this to be triggered while the file is being scanned/generated
    if [[ $(find . -name "*.raw" -size +10M -newer ./tmp/.flag.flag -mmin +"${MINMINS}") ]]
    then
        find . -name "*.raw" -size +10M -newer ./tmp/.flag.flag -mmin +"${MINMINS}" -exec ls \
            -lcth {} \; |& tee ./tmp/message.log
            
        echo "Found Something"

        # Sends messages to the group

        curl -F chat_id="${TARGET_CHAT_ID}" -F text="New File Found in the directory" \
            https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage
        curl -F chat_id="${TARGET_CHAT_ID}" -F text="$(cat ./tmp/message.log)" \
           https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage

        # Makes the pictures of the XIC
        # TODO ADD HERE A NEW TEMP DIRECTORY AND AN EXIT TRAP
        find . -name "*.raw" -size +10M -newer ./tmp/.flag.flag -mmin +"${MINMINS}" -exec \
            mspicture.exe -z 1 --binSum --mzLow 300 --mzHigh 1500\
            -w 600 --height 1400 \
            --outdir ./tmp {} \;
        
        # This loop is necessary because mspicture might output several images
        # When several ms1 scans are defined
        for i in $( find ./tmp/*.ftms.png -mmin -20 )
        do 
            echo "${i}" 
            curl -F chat_id="${TARGET_CHAT_ID}" \
                -F document=@"${i}" -F caption="${i}" \
                https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument
        done

        # This Section sends the apexes list
        # TODO sort this in order of elution and perhaps print an expected value
        if [[ $(find ./Standards/. -size +1M -regex ".*std.*.raw" -mmin -30) ]] 
        then
            echo "" > ./tmp/stdstatus.log
            echo "Found New Standard, Calculating Peak Apexes"
            find . -regex ".*std.*.raw" -mmin -30 \
                -exec \
                msaccess {} \
                -x "sic mzCenter=487.2567 radius=5 radiusUnits=ppm" \
                -x "sic mzCenter=669.8381 radius=5 radiusUnits=ppm" \
                -x "sic mzCenter=622.8535 radius=5 radiusUnits=ppm" \
                -x "sic mzCenter=636.8692 radius=5 radiusUnits=ppm" \
                -o 'tmp' -v \;

            echo "Peak Apexes (Retention Time, mins): " | tee --append ./tmp/stdstatus.log
            echo "" >> ./tmp/stdstatus.log

            MYVAR=$(find ./tmp -regex .*.summary.* -mmin -30 -exec grep -oP "(?<=apex_rt: )\d+.\d+" {} \;)
            for i in $MYVAR ; do echo print "${i} / 60" | perl -l | tee --append ./tmp/stdstatus.log ; done

            echo "" >> ./tmp/stdstatus.log
            echo "Apex Intensities (10^6): " | tee --append ./tmp/stdstatus.log
            echo "" >> ./tmp/stdstatus.log

            MYVAR=$(find ./tmp -regex .*.summary.* -mmin -30 -exec grep -oP "(?<=apex_intensity: )\d+" {} \;)
            for i in $MYVAR ; do echo print "${i} / 1000000" | perl -l | tee --append ./tmp/stdstatus.log ; done

            curl -F chat_id="${TARGET_CHAT_ID}" -F text="$(cat ./tmp/stdstatus.log)" \
                   https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage
        fi

        # TODO find a way to store the lysate info or any output of find for that purpose
        if [[ $(find ./Standards/. -size +1M -regex ".*lysate.*.raw" -mmin -30) ]] 
        then
            echo "Found new lysate, running comet"
            echo "" > ./tmp/lysatestatus.log
            find ./Standards/. -size +1M -regex ".*lysate.*.raw" -mmin -30 \
                -exec bash run_diagnose_lysate.bash {} \;
        fi

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

        if [[ $(find ./tmp/sc.jpg -mmin +"${LCREFRESHRATE}") ]]
        then 
            # TODO check for bug when the ./tmp/sc.jpg file does not exist

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
        fi
    fi
done


# TODO 
# During sample loading, a raw file of size 34 kb is generated and not modified until it starts scanning
# Could use the modification of such file to monitor the loading time
