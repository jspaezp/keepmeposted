
library("optparse")
 
option_list <- list(
  make_option(
    c("-f", "--file"),
    type="character", default=NULL, 
    help=paste0(
        "Comet output text file with the q significant psms"),
    metavar="character"),
  make_option(
    c("--out_png"),
    type="character", 
    default="out.png", 
    help="output file name for longitudinal mass shift [default= %default]",
    metavar="character")
)
 
opt_parser <- OptionParser(option_list=option_list)
opt <- parse_args(opt_parser)

require(tidyverse)
require(hexbin)

infile <- opt$file

spectrum_data <- read_tsv(infile)

spectrum_data$mass_error <- spectrum_data$`spectrum neutral mass` - spectrum_data$`peptide mass`
spectrum_data <- spectrum_data %>% 
filter( mass_error < 0.5, mass_error > -0.5 ) %>%
mutate( mass_error =  (1e6*mass_error/`spectrum neutral mass`)/charge)

numscans <- nrow(spectrum_data)

g1 <- spectrum_data %>% 
    ggplot(data = ., aes(x = scan, y = mass_error)) +
    geom_hex(binwidth = c(numscans/20,0.5)) + 
    theme_bw() +
    scale_fill_viridis_c(direction = -1) +
    geom_hline(yintercept = c(-5, 0, 5), size = 1, colour = "red")
g1

g2 <- spectrum_data %>% 
    qplot(data = ., x = mass_error, geom = "histogram", binwidth = 0.1) + 
    theme_bw() + 
    geom_vline(xintercept = c(-5, 0, 5), size = 1, colour = "red")

g2

g3 <- cowplot::plot_grid(g1, g2)
ggsave(filename = opt$out_png, plot = g3, width = 12, height = 5, dpi = 150)
