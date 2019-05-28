
set -x
set -e

outdir="./tmp/crux_lysate_diagnose"
cruxbinary="/c/Users/Tao Lab/Documents/crux-3.2.Windows.AMD64/bin/crux.exe"
fastalocation="/c/Users/Tao Lab/Documents/UP000005640_9606.fasta/UP000005640_9606.fasta"
# fastalocation="/c/Users/Tao Lab/Documents/UP000000589_10090.fasta/UP000000589_10090.fasta" mice_fasta
# fastalocation="/c/Users/Tao Lab/Documents/UP000006548_3702.fasta/UP000006548_3702.fasta" plant_fasta
#fastalocation="/c/Users/Tao Lab/Documents/UP000005640_9606.fasta/UP000005640_9606.fasta" homosapient_fasta

"${cruxbinary}" pipeline \
     --output-dir ${outdir} \
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
     "$@" "${fastalocation}"
     #--require_variable_mod 1 \

cd "${outdir}"

"${cruxbinary}" extract-rows percolator.target.peptides.txt \
    --header T "percolator q-value" \
    --comparison lt 0.01 > qsig_percolator.target.peptides.txt

"${cruxbinary}" extract-rows percolator.target.psms.txt \
    --header T "percolator q-value" \
    --comparison lt 0.01 > qsig_percolator.target.psms.txt

"${cruxbinary}" extract-rows percolator.target.proteins.txt \
    --header T "q-value" \
    --comparison lt 0.01 > qsig_percolator.target.proteins.txt


"${cruxbinary}" extract-columns qsig_percolator.target.peptides.txt sequence > modsequences.txt
"${cruxbinary}" extract-columns qsig_percolator.target.psms.txt sequence > modsequencespsms.txt
"${cruxbinary}" extract-columns qsig_percolator.target.proteins.txt ProteinGroupId > proteinGroups.txt


set +x
set +e

allcommands () {
     echo "Number of Peptides: "
     cat modsequencespsms.txt | sort | uniq | wc -l

     echo "Unique peptide sequences: "
     cat modsequences.txt | perl -p -e "s/(\[.*?\])|(\[.*?\])//g" | sort | uniq | wc -l

     echo "Number of protein groups: "
     cat proteinGroups.txt | sort | uniq | wc -l
}

allcommands |& tee report_lysate.txt

curl -F chat_id="${TARGET_CHAT_ID}" -F document=@"report_lysate.txt" https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument
curl -F chat_id="${TARGET_CHAT_ID}" -F text="$( cat report_lysate.txt) " https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage

# TODO, crux writes a line 
# FATAL: The file ./tmp/crux_lysate_diagnose/comet.target.txt does not exist.
# whenever the search fails, check for that line

#curl -X POST \
#       -H 'Content-Type: application/json' \
#       -d '{"chat_id": "455502653", "text": "$(cat report.txt)", "disable_notification": true}' \
#       https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage
