#!/usr/bin/env Rscript
library("optparse")
 
option_list <- list(
  make_option(
    c("-f", "--file"),
    type="character", default=NULL, 
    help=paste0(
        "dataset file name output from  ",
        "./SkylineDailyRunner.exe --in=sky.sky ",
        "--chromatogram-file=\"foo.tsv\" ",
        "--chromatogram-products"),
    metavar="character"),
  make_option(
    c("-o", "--out"),
    type="character", 
    default="out.png", 
    help="output file name [default= %default]",
    metavar="character")
)
 
opt_parser <- OptionParser(option_list=option_list)
opt <- parse_args(opt_parser)

require(tidyverse)

dt <- read_tsv(opt$file) %>% 
    as_tibble() %>% 
    mutate(
       Times = purrr::map(
          strsplit(Times, split = ","),
          as.double),
       Intensities = purrr::map(
        strsplit(Intensities, split = ","),
        as.double)
    ) %>%
    unnest(cols = c(Times, Intensities))

dt2 <- dt %>% 
   group_by(PeptideModifiedSequence, FileName, Times ) %>%
   mutate(time_sum = sum((Intensities))) %>%
   ungroup() %>%
   group_by(PeptideModifiedSequence, FileName) %>%
   mutate(apex = unique(Times[time_sum == max(time_sum)])) %>%
   mutate(apex_close = (Times < (apex + 0.25)) & (Times > (apex - 0.25))) %>%
   filter(apex_close)

g <- dt2 %>% 
    ggplot(
      aes(
        x = Times, y = Intensities,
        colour = FragmentIon,
        group = interaction(
          FragmentIon, 
          PeptideModifiedSequence,
                  ProductCharge ))) +
    geom_line(size = 0.1) + 
    geom_line(colour = "black", mapping = aes(y = time_sum)) +
    geom_point(alpha = 0.7) +
    facet_wrap(~ PeptideModifiedSequence, scales = "free") +
    theme_minimal()

ggsave(plot = g, file = opt$out, height = 5, width = 10, dpi = 150)