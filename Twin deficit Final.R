# =====================================================================
# TWIN DEFICITS: U.S., GERMANY, JAPAN   IMF WEO ANNUAL DATA
# Fiscal balance  = General government net lending(+)/borrowing(-), % of GDP
#                   (WEO code GGXCNL_NGDP)
# Current account = Current account balance, % of GDP (WEO code BCA_NGDPD)
# Twin deficits predicts a POSITIVE slope of CA on the fiscal balance.
#
# Fiscal and CA files are SEPARATE, so they are loaded, matched by the
# country code and indicator code stored INSIDE each file (not by file
# name), and merged on country + year. Mislabeled file names cannot
# cause a mix-up.
# =====================================================================

# install.packages(c("tidyr","sandwich","lmtest","tseries"))  # run once
library(tidyr)
library(sandwich)
library(lmtest)
library(tseries)

# ---------------------------------------------------------------------
# 0. SETTINGS (change only here)
# ---------------------------------------------------------------------
DIR <- "/Users/neelnanavati/Downloads/Independent study "   # folder with the csv files
FILES <- list.files(DIR, pattern = "^(US|Germany|Japan)[ _](FD|CA).*\\.csv$")
FILES

LAST_ACTUAL <- 2024        # last year of ACTUAL data (later = IMF projections). CONFIRM.
COMMON_START <- 2001       # common start year (U.S. fiscal data begins in 2001)
SPLIT        <- 2012       # early = year <= SPLIT, late = year > SPLIT
WINDOW       <- 10         # rolling-correlation window (years)
NW_LAG       <- 2          # Newey-West lag, same for every model
COVID        <- c(2020, 2021)
FD_CODE <- "GGXCNL_NGDP"
CA_CODE <- "BCA_NGDPD"

# ---------------------------------------------------------------------
# 1. LOAD: read every file into one long table
# ---------------------------------------------------------------------
read_weo <- function(path) {
  x <- read.csv(path, check.names = FALSE, fileEncoding = "UTF-8-BOM",
                stringsAsFactors = FALSE)
  yrs <- names(x)[grepl("^[0-9]{4}$", names(x))]          # year columns only
  do.call(rbind, lapply(seq_len(nrow(x)), function(i) {
    parts <- strsplit(x$SERIES_CODE[i], ".", fixed = TRUE)[[1]]  # e.g. USA.BCA_NGDPD.A
    data.frame(iso       = parts[1],
               indicator = parts[2],
               country   = x$COUNTRY[i],
               year      = as.numeric(yrs),
               value     = suppressWarnings(as.numeric(unlist(x[i, yrs]))),
               stringsAsFactors = FALSE)
  }))
}

all_long <- do.call(rbind, lapply(file.path(DIR, FILES), read_weo))

# ---------------------------------------------------------------------
# 2. CHECK what was loaded (look at this table before trusting anything)
# ---------------------------------------------------------------------
cover <- aggregate(year ~ iso + indicator, data = all_long[!is.na(all_long$value), ],
                   FUN = function(y) paste(min(y), "-", max(y)))
print(cover)
stopifnot(all(c(FD_CODE, CA_CODE) %in% all_long$indicator))
stopifnot(!any(duplicated(all_long[, c("iso", "indicator", "year")])))

# ---------------------------------------------------------------------
# 3. MERGE: fiscal + current account on country and year
# ---------------------------------------------------------------------
fd_long <- all_long[all_long$indicator == FD_CODE, c("iso", "country", "year", "value")]
ca_long <- all_long[all_long$indicator == CA_CODE, c("iso", "year", "value")]
names(fd_long)[4] <- "fd"
names(ca_long)[3] <- "ca"
panel <- merge(fd_long, ca_long, by = c("iso", "year"))

panel <- panel[panel$year <= LAST_ACTUAL, ]     # remove IMF projections
panel <- drop_na(panel)                          # keep complete years only
panel <- panel[order(panel$iso, panel$year), ]

cat("\nMerged panel (complete years, actual data only):\n")
print(aggregate(year ~ iso, data = panel,
                FUN = function(y) paste(min(y), "-", max(y), " n =", length(y))))

write.csv(panel, file.path(DIR, "twin_deficits_merged.csv"), row.names = FALSE)

# ---------------------------------------------------------------------
# 4. ANALYSIS FUNCTION: identical for every country and sample
# ---------------------------------------------------------------------
nw <- function(m) coeftest(m, vcov. = NeweyWest(m, lag = NW_LAG, prewhite = FALSE))
slope <- function(m) nw(m)["fd", c("Estimate", "Std. Error", "Pr(>|t|)")]

analyze <- function(d, label) {
  d  <- d[order(d$year), ]
  dd <- data.frame(year = d$year[-1], fd = diff(d$fd), ca = diff(d$ca))   # first differences
  
  m_lev   <- lm(ca ~ fd, data = d)
  m_levx  <- lm(ca ~ fd, data = d[!(d$year %in% COVID), ])
  m_dif   <- lm(ca ~ fd, data = dd)
  m_difx  <- lm(ca ~ fd, data = dd[!(dd$year %in% COVID), ])
  
  d$covid  <- as.numeric(d$year  %in% COVID)
  dd$covid <- as.numeric(dd$year %in% COVID)
  m_levD <- lm(ca ~ fd + covid, data = d)
  m_difD <- lm(ca ~ fd + covid, data = dd)
  
  e <- d[d$year <= SPLIT, ];  l <- d[d$year > SPLIT, ]
  ed <- dd[dd$year <= SPLIT, ]; ld <- dd[dd$year > SPLIT, ]
  
  # Rolling correlation (levels)
  rc <- rep(NA_real_, nrow(d))
  if (nrow(d) >= WINDOW) for (i in WINDOW:nrow(d)) {
    idx <- (i - WINDOW + 1):i
    rc[i] <- cor(d$fd[idx], d$ca[idx])
  }
  
  adfp <- function(x) tryCatch(suppressWarnings(adf.test(x)$p.value), error = function(e) NA)
  pop  <- tryCatch(suppressWarnings(po.test(cbind(d$ca, d$fd))$p.value), error = function(e) NA)
  
  cat("\n=====", label, ": n =", nrow(d), ",", min(d$year), "-", max(d$year), "=====\n")
  cat("Levels (Newey-West):\n");           print(nw(m_lev))
  cat("First differences (Newey-West):\n"); print(nw(m_dif))
  
  res <- data.frame(
    sample = label, n = nrow(d), first = min(d$year), last = max(d$year),
    lev_slope = slope(m_lev)[[1]], lev_se = slope(m_lev)[[2]], lev_p = slope(m_lev)[[3]],
    levX_slope = slope(m_levx)[[1]], levX_p = slope(m_levx)[[3]],
    dif_slope = slope(m_dif)[[1]], dif_se = slope(m_dif)[[2]], dif_p = slope(m_dif)[[3]],
    difX_slope = slope(m_difx)[[1]], difX_p = slope(m_difx)[[3]],
    levD_slope = slope(m_levD)[[1]], levD_p = slope(m_levD)[[3]],
    difD_slope = slope(m_difD)[[1]], difD_p = slope(m_difD)[[3]],
    cor_lev = cor(d$fd, d$ca), cor_dif = cor(dd$fd, dd$ca),
    cor_lev_early = cor(e$fd, e$ca), cor_lev_late = cor(l$fd, l$ca),
    cor_dif_early = cor(ed$fd, ed$ca), cor_dif_late = cor(ld$fd, ld$ca),
    adf_fd = adfp(d$fd), adf_ca = adfp(d$ca),
    adf_dfd = adfp(dd$fd), adf_dca = adfp(dd$ca),
    po_p = pop, row.names = NULL
  )
  list(res = res, roll = data.frame(year = d$year, rc = rc), data = d)
}

# ---------------------------------------------------------------------
# 5. RUN: (A) common sample for fair comparison, (B) each full sample
# ---------------------------------------------------------------------
isos   <- unique(panel$iso)
nice   <- c(USA = "U.S.", DEU = "Germany", JPN = "Japan")

common <- lapply(isos, function(i)
  analyze(panel[panel$iso == i & panel$year >= COMMON_START, ],
          paste0(nice[[i]], " (common ", COMMON_START, "-", LAST_ACTUAL, ")")))
full   <- lapply(isos, function(i)
  analyze(panel[panel$iso == i, ], paste0(nice[[i]], " (full)")))
names(common) <- names(full) <- isos

# ---------------------------------------------------------------------
# 6. COMPARISON TABLES (rows = statistics, columns = samples)
# ---------------------------------------------------------------------
tab_common <- do.call(rbind, lapply(common, function(z) z$res))
tab_full   <- do.call(rbind, lapply(full,   function(z) z$res))

show <- function(tab) {
  t_ <- t(as.matrix(tab[, -1]))        # drop the 'sample' label column
  colnames(t_) <- tab$sample
  print(round(t_, 3))
}
cat("\n\n######## COMMON SAMPLE (fair comparison) ########\n"); show(tab_common)
cat("\n######## FULL AVAILABLE SAMPLES ########\n");           show(tab_full)

write.csv(rbind(tab_common, tab_full), file.path(DIR, "twin_deficits_results.csv"),
          row.names = FALSE)

# ---------------------------------------------------------------------
# 7. PLOTS
# ---------------------------------------------------------------------
# 7a. Levels of both series, one panel per country (legend placed in the
#     top-left so it does not cover the lines)
par(mfrow = c(length(isos), 1), mar = c(4, 4, 2, 1))
for (i in isos) {
  d <- panel[panel$iso == i, ]
  plot(d$year, d$fd, type = "l", ylim = range(c(d$fd, d$ca)),
       xlab = "Year", ylab = "% of GDP", main = nice[[i]])
  lines(d$year, d$ca, col = "red")
  abline(h = 0, lty = 3)
  legend("topleft", c("Fiscal balance", "Current account"),
         col = c("black", "red"), lty = 1, bty = "n", cex = 0.8)
}

# 7b. Rolling correlation, all three countries (full available samples)
par(mfrow = c(1, 1), mar = c(5, 4, 4, 2))
cols <- c("black", "red", "blue")
plot(NA, xlim = range(panel$year), ylim = c(-1, 1), xlab = "Year",
     ylab = paste0(WINDOW, "-year rolling correlation"),
     main = "Fiscal balance vs current account balance")
for (k in seq_along(isos)) lines(full[[isos[k]]]$roll$year, full[[isos[k]]]$roll$rc, col = cols[k])
abline(h = 0, lty = 2)
legend("bottomright", nice[isos], col = cols, lty = 1, bty = "n")
# ---------------------------------------------------------------------
# NOTES
# * ADF/cointegration tests have low power with 24-45 annual observations.
#   Report them as indicative, not conclusive.
# * Next steps in the plan: add controls (saving, investment, real exchange
#   rate), formal structural-break tests, rolling regression coefficients,
#   and a long U.S. series (FRED federal balance) for 1980-2000.
# =====================================================================``

