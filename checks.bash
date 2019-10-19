#!/bin/bash

if ! [[ $(curl https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates) ]]
then
    echo "Bot does not seem to be correctly configured"
fi

if ! [[ $(ping "${LC_SERVER}" -n 1 -w 1) ]]
then
    echo "LC server does not seem to be connected to the network"
fi

if ! [[ $(ssh -q "${LC_USER}@${LC_SERVER}" "echo 'Connection Worked'") ]]
then
    echo "Cannot Connect Via SSH to the HPLC server"
fi

if ! [[ $(which mspicture.exe) ]]
then
    echo "MSPICTURE does not seem to be in the path, it will not send the heatmaps"
fi

if [[ -e "${STP_DEF_CRUXPARAMS}" ]]
then
    echo "Found ${STP_DEF_CRUXPARAMS}; using it as the default crux parameters file"
else
	echo "Unable to find the defined crux parameters: ${STP_DEF_CRUXPARAMS}"
fi


if false
then
    find . -regex ".*lysate.*.raw" -mmin -100 \
                -exec bash run_diagnose_lysate.bash {} \;
    exit
fi
