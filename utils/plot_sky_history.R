#!/usr/bin/env Rscript

trapz <- function(x, y) {
    if (missing(y)) {
        if (length(x) == 0) return(0)
        y <- x
        x <- seq(along=x)
    }
    if (length(x) == 0 && length(y) == 0) return(0)
    if (!(is.numeric(x) || is.complex(x)) ||
            !(is.numeric(y) || is.complex(y)) )
        stop("Arguments 'x' and 'y' must be real or complex vectors.")
    m <- length(x)
    if (length(y) != m)
        stop("Arguments 'x', 'y' must be vectors of the same length.")
    if (m <= 1) return(0.0)

    #order_x <- rank(x, ties.method = "random")
    #x <- x[order_x]
    #y <- y[order_x]

    xp <- c(x, x[m:1])
    yp <- c(numeric(m), y[m:1])
    n <- 2*m
    p1 <- sum(xp[1:(n-1)]*yp[2:n]) + xp[n]*yp[1]
    p2 <- sum(xp[2:n]*yp[1:(n-1)]) + xp[1]*yp[n]

    return(0.5*(p1-p2))
}

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
    c("--out_int"),
    type="character", 
    default="out_int.png", 
    help="output file name for longitudinal intensity plot [default= %default]",
    metavar="character"),
  make_option(
    c("--out_rt"),
    type="character", 
    default="out_rt.png", 
    help="output file name for delta retention times plot [default= %default]",
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


delta_rt_gg <- dt2  %>%
    ungroup() %>%
    select(PeptideModifiedSequence, FileName, apex) %>% 
    unique() %>%
    group_by(PeptideModifiedSequence) %>%
    mutate(RTvsMedian = apex - median(apex)) %>%   
    ggplot(
        aes(x = FileName,
            y = RTvsMedian,
            colour = PeptideModifiedSequence,
            group = PeptideModifiedSequence)) + 
    geom_point() + 
    geom_line() + 
    theme_minimal() +
    theme(axis.text.x = element_text(angle = 90, hjust = 1))


intensities_gg <- dt2 %>% 
    group_by(PeptideModifiedSequence, FileName) %>%
    summarise(integral = trapz(Times, Intensities)) %>%
    ungroup() %>%
    mutate(FileName = as.factor(FileName)) %>%
    ggplot(
        aes(x = FileName,
            y = integral ,
            colour = PeptideModifiedSequence,
            group = PeptideModifiedSequence)) +
    geom_point() + 
    geom_line() + 
    theme_minimal() +
    theme(axis.text.x = element_text(angle = 90, hjust = 1))

ggsave(plot = intensities_gg, file = opt$out_int, height = 5, width = 10, dpi = 150)
ggsave(plot = delta_rt_gg, file = opt$out_rt, height = 5, width = 10, dpi = 150)

################
