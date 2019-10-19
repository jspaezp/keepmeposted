

# Keepmeposted

## Is a simple utility to monitor mass spec performance and runs

This is a simple bash-based utility that checks user-set directories in a loop and
sends via telegram some data that represents the performance of the equipement.

Our current usage includes:

- Taking a virtual screenshot of our easy-nlc 1000.
- Every time a blank with an irt standard is run, it imports it to a skyline document
  and returns the chromatograms.
- Every time a lysate is run (K549 in our case), it runs comet and returns the number of psm, peptides and protein groups (not that the last one really matters ....)
- If there is a fasta file in any regular file location, it will also run comet and return the PSM-peptide-protein-modification metrics

## Local Dependencies

- [Git Bash](https://gitforwindows.org)
    - It provides the main runtime environment to call all other tools
- [Crux ms - MacCoss lab](http://crux.ms/)
    - Provides the comet-percolator-fido search pipeline 
- [Skyline Runner](https://skyline.ms/wiki/home/software/Skyline/page.view?name=documentation)
    - Provides the hability to create skyline files from the command line and output those reports.
- [The R programming language](https://www.r-project.org)
    - Provides the visualization of the standards and extracted ion chromatograms.


## Usage

... TODO ....
