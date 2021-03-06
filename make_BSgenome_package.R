#!/usr/bin/env Rscript


# The R command line script
#  (1) downloads GRCh38 genome sequences from Ensembl,
#  (2) downloads the U13369.1 rDNA sequence from NCBI/GenBank,
#  (3) builds a BSgenome object, and
#  (4) converts the BSgenome object into an R library.
#
# Author: Maurits Evers (maurits.evers@anu.edu.au)
# Date: 09/04/2018


## ------------------------------------------------------------------------
## Start clock
t0 <- Sys.time();


## ------------------------------------------------------------------------
## Load libraries
suppressWarnings(suppressMessages(library("optparse")));         # Python-style command line args
suppressWarnings(suppressMessages(library("yaml")));             # Parse YAML
suppressWarnings(suppressMessages(library("BSgenome")));         # for BSgenome
suppressWarnings(suppressMessages(library("devtools")));         # for build()


## ------------------------------------------------------------------------
## Parse command line arguments
option_list <- list(
    make_option(
        c("-i", "--input"),
        type = "character",
        default = NULL,
        help = "YAML config file",
        metavar = "character"),
#    make_option(
#        c("--seqdir"),
#        type = "character",
#        default = "seqs",
#        help = "Folder where sequence files are stored [default %default]",
#        metavar = "character"),
    make_option(
        c("--naming"),
        type = "character",
        default = "ensembl",
        help = "Set chromosome naming reference for BSgenome object;
                can be either \"ensembl\" or \"ucsc\" (without quotes).
                Note: ucsc uses chr1, chr2, ..., chrM
                      ensembl uses 1, 2, ..., MT
                [default %default]",
        metavar = "character"),
    make_option(
        c("-f", "--forceall"),
        type = "logical",
        action = "store_true",
        default = FALSE,
        help = "Force download (this will overwrite existing files)
                [default %default]",
        metavar = "character")
);
opt_parser <- OptionParser(option_list = option_list);
args <- parse_args(opt_parser);
if (is.null(args$input)) {
    print_help(opt_parser);
    stop("Must give YAML config file.\n", call. = FALSE);
}


## ------------------------------------------------------------------------
## Custom function to generate timestamp
ts <- function() {
    return(format(Sys.time(), "[%Y-%m-%d %H:%M:%S]"));
}


## ------------------------------------------------------------------------
# Custom function to download file (if condition is met)
cond_download <- function(url, fn, force, id) {
    if (force | !file.exists(fn)) {
        cat(sprintf(
            "%s Downloading %s file %s.\n", ts(), id, fn));
        download.file(url, fn, quiet = TRUE);
    } else {
        cat(sprintf(
            "%s File %s already exists. Skipping (use -f to force download).\n",
            ts(),
            fn));
    }
}


## ------------------------------------------------------------------------
## Global variables
input <- args$input;
#seqdir <- args$seqdir;
seqdir <- "seqs";
forceall <- args$forceall;
naming <- match.arg(tolower(args$naming), c("ensembl", "ucsc"));
cat(sprintf("%s Parameter summary\n", ts()));
cat(sprintf(" input          = %s\n", input));
cat(sprintf(" naming         = %s\n", naming));
#cat(sprintf(" seqdir         = %s\n", seqdir));
cat(sprintf(" forceall       = %s\n", forceall));


## ------------------------------------------------------------------------
# Check if input files and output directory exists
if (!file.exists(input)) {
    stop(
        sprintf("Input file %s does not exists.\n", input),
        call. = FALSE);
}
if (!dir.exists(seqdir)) {
    stop(
        sprintf("Folder %s does not exists.\n", seqdir),
        call. = FALSE);
}


## ------------------------------------------------------------------------
# Parse YAML config file
cfg <- read_yaml(input);


## Parse YAML chromosome mapping file
ensembl2ucsc <- read_yaml("ensembl2ucsc.yaml");


## ------------------------------------------------------------------------
# Create folders for sequence and annotation files (if necessary)
#if (!dir.exists(seqdir)) {
#    cat(sprintf("%s Creating folder %s\n", ts(), seqdir));
#    dir.create(seqdir);
#}


## ------------------------------------------------------------------------
# Download genome fa.gz sequences from Ensembl
chr <- eval(parse(text = cfg$seq$chr));
cat(sprintf("%s Downloading Ensembl genome sequence files...\n", ts()));
for (i in 1:length(chr)) {
    url <- paste0(
        cfg$download$baseurl_ensembl,
        "/fasta/homo_sapiens/dna/Homo_sapiens.GRCh38.dna_rm.chromosome.",
        chr[i],
        ".fa.gz");
    fn <- paste0(seqdir, "/", chr[i], ".fa.gz");
    cond_download(url, fn, forceall, "Ensembl sequence");
    # Check that files are not empty
    seq <- readDNAStringSet(fn, "fasta");
    if (length(seq) == 0L) {
        cat(sprintf("%s [ERROR] File %s seems to be empty.\n", ts(), fn));
        stop(sprintf("%s is not a FASTA file. Download failure?", fn));
    }
    # Store sequence files in UCSC chromosome notation if requested
    if (naming  == "ucsc") {
        fn.out <- gsub(
            paste0(chr[i], ".fa.gz"),
            paste0(ensembl2ucsc[[chr[i]]], ".fa.gz"),
            fn);
        if (!file.exists(fn.out)) {
            names(seq) <- sub(chr[i], ensembl2ucsc[[chr[i]]], names(seq));
            cat(sprintf(
                "%s Writing new file %s in UCSC chromosome notation.\n",
                ts(), fn.out));
            writeXStringSet(seq, fn.out, compress = TRUE, width = 60);
        }
    }
}


## ------------------------------------------------------------------------
# Download rDNA fa sequence from Dropbox
#cat(sprintf("%s Downloading rDNA sequence file...\n", ts()));
#url <- "https://www.dropbox.com/s/hiwz75voa0up011/U13369.1.fa.gz?dl=1";
fn <- paste0(seqdir, "/U13369.1.fa.gz");
#cond_download(url, fn, forceall, "rDNA sequence");


## ------------------------------------------------------------------------
# Write seed file (as Debian Control File)
cat(sprintf("%s Writing seed file...\n", ts()));
chr <- c(chr, "U13369.1");
seq.circ <- eval(parse(text = cfg$seq$chr_circ));
if (naming == "ucsc") {
    chr <- ifelse(
        !is.na(match(chr, names(ensembl2ucsc))),
        unlist(ensembl2ucsc[chr]),
        chr);
    seq.circ <- ifelse(
            !is.na(match(seq.circ, names(ensembl2ucsc))),
            unlist(ensembl2ucsc[seq.circ]),
            seq.circ)
}
cfg$BSgenome$seqnames <- sprintf(
    "c(%s)",
    paste0(paste0("'", chr, "'"), collapse = ", "));
cfg$BSgenome$circ_seqs <- sprintf(
    "c(%s)",
    paste0(paste0("'", seq.circ, "'"), collapse = ", "))
write.dcf(
    cfg$BSgenome,
    file = "BSgenome_seed.dcf",
    append = FALSE,
    width = 999);


### ------------------------------------------------------------------------
## Forge BSgenome
cat(sprintf("%s Forging BSgenome...\n", ts()));
if (forceall | !dir.exists(cfg$BSgenome$Package)) {
    if (forceall & dir.exists(cfg$BSgenome$Package)) {
        cat(sprintf("%s Deleting existing folder %s...\n",
        ts(),
        cfg$BSgenome$Package));
        unlink(cfg$BSgenome$Package, recursive = TRUE);
    }
    cat(sprintf(
        "%s Creating package source files in folder %s\n",
        ts(),
        cfg$BSgenome$Package));
    forgeBSgenomeDataPkg("BSgenome_seed.dcf", seqs_srcdir = seqdir);
} else {
    cat(sprintf(
        "%s Folder %s already exists. Skipping (use -f to force rebuild).
         %12s Or manually delete target folder (e.g. 'rm -rf %s').\n",
        ts(),
        cfg$BSgenome$Package,
        "",
        cfg$BSgenome$Package));
}


### ------------------------------------------------------------------------
## Build BSgenome package
cat(sprintf("%s Building BSgenome package...\n", ts()));
fn <- paste0(cfg$BSgenome$Package, "_", cfg$BSgenome$Version, ".tar.gz");
if (forceall | !file.exists(fn)) {
    fn <- devtools::build(cfg$BSgenome$Package);
    cat(sprintf("%s BSgenome package file %s created.\n",
                 ts(),
                 fn));
} else {
    cat(sprintf(
        "%s File %s already exists. Skipping (use -f to force rebuild).
         %12s Or manually delete target file (e.g. 'rm -f %s').\n",
        ts(),
        fn,
        "",
        fn));
}


### ------------------------------------------------------------------------
## Done
cat(sprintf("%s All done.\n", ts()));
cat(sprintf(
    "%s Install package with 'install.packages(\"%s\")'.\n",
    ts(),
    fn))
