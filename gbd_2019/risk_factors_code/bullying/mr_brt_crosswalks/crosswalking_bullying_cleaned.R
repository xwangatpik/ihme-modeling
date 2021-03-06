#######################################################################################
### Date:     13th May 2018
### Purpose:  Estimate Sex-ratio and crosswalks for GBD2019
#######################################################################################

bundle_id <- 3122
acause <-"bullying"
covariates <- c("cv_low_bullying_freq", "cv_no_bullying_def_presented", 'cv_recall_1yr')
uses_csmr <- F
test_sex_by_super_region <- F
crosswalk_pairs <- 'FILEPATH.csv'
age_sex_split_estimates <- "FILEPATH.xlsx"
need_to_age_split <- F
need_save_bundle_version <- 1829 # Set as true to save bundle version, otherwise specify bundle version here
sex_ratio_by_age <- F

library(data.table)
library(openxlsx)
library(msm)

source("FILEPATH.R")
source("FILEPATH.R")
source("FILEPATH.R")
source("FILEPATH.R")
source("FILEPATH.R")
source("FILEPATH.R")
source("FILEPATH.R")
source("FILEPATH.R")

## Get latest review sheet ##
if(need_save_bundle_version == T){
  v_id <- save_bundle_version(bundle_id, "step2")$bundle_version_id
} else {
  v_id <- need_save_bundle_version
}
review_sheet <- get_bundle_version(v_id)

## Flag if age-split by regional pattern estimates exist ##
if(length(review_sheet[(grepl("age-split child", specificity)),unique(nid)]) > 0){
  print(paste0("STOP! The following nid still has age-split estimates by regional pattern in your bundle version: ", review_sheet[(grepl("age-split child", specificity)),unique(nid)]))
}

## Remove excluded estimates ##
review_sheet[is.na(group_review), group_review := 1]
review_sheet <- review_sheet[group_review == 1, ]
review_sheet[, study_covariate := "ref"]

review_sheet[is.na(standard_error) & !is.na(lower), standard_error := (upper - lower) / (qnorm(0.975,0,1)*2)]
review_sheet[is.na(standard_error) & measure == "prevalence", standard_error := sqrt(1/sample_size * mean * (1-mean) + 1/(4*sample_size^2)*qnorm(0.975,0,1)^2)]
review_sheet[is.na(standard_error) & measure %in% c("incidence", "remission"), standard_error :=  ifelse(mean*sample_size <= 5, ((5-mean*sample_size) / sample_size + mean * sample_size * sqrt(5/sample_size^2))/5, ((mean*sample_size)^0.5)/sample_size)]

##### Estimate and apply sex-ratios -----------------------------------------------------------------------

## Create paired dataset where each row is a sex pair ##
match_columns <- c("nid", "age_start", "age_end", "location_id", "site_memo", "year_start", "year_end", "measure", covariates)
males <- review_sheet[sex == "Male" & is_outlier == 0, c(match_columns, "mean", "standard_error"), with = F]
females <- review_sheet[sex == "Female" & is_outlier == 0, c(match_columns, "mean", "standard_error"), with = F]
setnames(males, "mean", "mean_m")
setnames(males, "standard_error", "se_m")
setnames(females, "mean", "mean_f")
setnames(females, "standard_error", "se_f")
sex_ratios <- merge(males, females, by = match_columns)

## Match on regions ##
locations <- get_location_metadata(location_set_id=9)
sex_ratios <- merge(sex_ratios, locations[,.(location_id, region_id, region_name, super_region_id, super_region_name)], by = "location_id")

sex_ratios[, `:=` (ratio = mean_m / mean_f, se = sqrt(((mean_m^2 / mean_f^2) * ((se_m^2) / (mean_m^2) + (se_f^2) / (mean_f^2)))),
                     mid_age = (age_start + age_end) / 2, mid_year = (year_start + year_end) / 2)]

sex_ratios[, mc_mid_age := mid_age - mean(mid_age)]
sex_ratios[, log_ratio := log(ratio)]
sex_ratios[, log_ratio_se := deltamethod(~log(x1), ratio, se^2), by = c("ratio", "se")]

table(sex_ratios[!is.na(ratio) & ratio != 0, measure])

# Create measure CVs
if(uses_csmr == T){sex_ratios <- sex_ratios[!(measure %in% c("mtstandard"))]}

measures <- unique(sex_ratios$measure)

for(m in measures){
  sex_ratios[, paste0("cv_", m) := ifelse(measure == m, 1, 0)]
}


# Create geographic CVs #
sex_locations <- unique(sex_ratios$super_region_id)
for(r in sex_locations){
  sex_ratios[, paste0("cv_", r) := ifelse(super_region_id == r, 1, 0)]
}


# Create covlist
for(c in paste0("cv_", measures)){
  cov <- cov_info(c, "X")
  if(c == paste0("cv_", measures)[1]){
    cov_list <- list(cov)
  } else {
    cov_list <- c(cov_list, list(cov))
  }
}

if(test_sex_by_super_region == T){
  for(c in paste0("cv_", sex_locations)){
    cov <- cov_info(c, "X")
    cov_list <- c(cov_list, list(cov))
  }
}

if(sex_ratio_by_age == T){ cov_list <- c(cov_list, list(cov_info("mc_mid_age", "X")))}

dir.create(file.path(paste0("FILEPATH/", acause, "/")), showWarnings = FALSE)

## Run MR-BRT ##
model <- run_mr_brt(
  output_dir = paste0("/FILEPATH/", acause, "/"),
  model_label = "sex",
  data = sex_ratios[!is.na(ratio) & ratio != 0 & ratio != Inf,],
  mean_var = "log_ratio",
  se_var = "log_ratio_se",
  covs = cov_list,
  remove_x_intercept = T,
  method = "trim_maxL",
  trim_pct = 0.1,
  study_id = "nid",
  overwrite_previous = TRUE,
  lasso = F)

sex_coefs  <- data.table(load_mr_brt_outputs(model)$model_coef)
sex_coefs[, `:=` (lower = beta_soln - sqrt(beta_var)*qnorm(0.975, 0, 1), upper = beta_soln + sqrt(beta_var)*qnorm(0.975, 0, 1))]
sex_coefs[, `:=` (sig = ifelse(lower * upper > 0, "Yes", "No"))]
sex_coefs

check_for_outputs(model)

eval(parse(text = paste0("sex_ratio <- expand.grid(", paste0(paste0("cv_", measures), "=c(0, 1)", collapse = ", "), ")")))
sex_ratio <- as.data.table(predict_mr_brt(model, newdata = sex_ratio)["model_summaries"])
names(sex_ratio) <- gsub("model_summaries.", "", names(sex_ratio))
names(sex_ratio) <- gsub("X_", "", names(sex_ratio))

sex_ratio[, measure := ""]
for(m in names(sex_ratio)[names(sex_ratio) %like% "cv_"]){
  sex_ratio[get(m) == 1, measure := ifelse(measure != "", paste0(measure, ", "), m)]
}
sex_ratio[, measure := gsub("cv_", "", measure)]
sex_ratio <- sex_ratio[measure %in% measures,]

sex_ratio[, `:=` (ratio = exp(Y_mean), ratio_se = (exp(Y_mean_hi) - exp(Y_mean_lo))/(2*qnorm(0.975,0,1)))]
sex_ratio[, (c(paste0("cv_", measures), "Y_mean", "Z_intercept", "Y_negp", "Y_mean_lo", "Y_mean_hi", "Y_mean_fe", "Y_negp_fe", "Y_mean_lo_fe", "Y_mean_hi_fe")) := NULL]

write.csv(sex_ratio, paste0("/FILEPATH/", acause, "/FILEPATH.csv"),row.names=F)

## Load in estimates that are age-sex split using the study sex-ratio
age_sex_split <- data.table(read.xlsx(age_sex_split_estimates))
sex_parents <- age_sex_split[age_sex_split == -1 & sex != "Both", seq]
age_parents <- age_sex_split[age_sex_split == -1 & sex == "Both", seq]
review_sheet[seq %in% c(sex_parents, age_parents) & group_review == 0,] # just checking if any are group-reviewed
review_sheet[seq %in% c(sex_parents, age_parents) & is_outlier == 1,] # just checking if any are outliered
age_sex_split <- age_sex_split[age_sex_split == 1, ]
age_sex_split[, seq := NA]

## Crosswalk both-sex data ##
review_sheet_both <- review_sheet[sex == "Both" & !(seq %in% age_parents), ]
review_sheet_both[, `:=` (crosswalk_parent_seq = NA)]

population <- get_population(location_id = unique(review_sheet_both$location_id), decomp_step = 'step2', age_group_id = c(1, 6:20, 30:32, 235), sex_id = c(1, 2), year_id = seq(min(review_sheet_both$year_start), max(review_sheet_both$year_end)))
age_ids <- get_ids('age_group')[age_group_id %in% c(1, 6:20, 30:32, 235),]
suppressWarnings(age_ids[, `:=` (age_start = as.numeric(unlist(strsplit(age_group_name, " "))[1]), age_end = as.numeric(unlist(strsplit(age_group_name, " "))[3])), by = "age_group_id"])
age_ids[age_group_id == 1, `:=` (age_start = 0, age_end = 4)]
age_ids[age_group_id == 235, `:=` (age_end = 99)]
population <- merge(population, age_ids, by = "age_group_id")

pop_agg <- function(l, a_s, a_e, y_s, y_e, s){
  a_ids <- age_ids[age_start %in% c(a_s:a_e-4) & age_end %in% c(a_s+4:a_e), age_group_id]
  pop <- population[location_id == l & age_group_id %in% a_ids & sex_id == s & year_id %in% c(y_s:y_e),sum(population)]
  return(pop)
}

review_sheet_both <- merge(review_sheet_both, sex_ratio, by = "measure")

review_sheet_both[, `:=` (mid_age = (age_start + age_end) / 2, age_start_r = round(age_start/5)*5, age_end_r = round(age_end/5)*5)]
review_sheet_both[age_start_r == age_end_r & mid_age < age_start_r, age_start_r := age_start_r - 5]
review_sheet_both[age_start_r == age_end_r & mid_age >= age_start_r, age_end_r := age_end_r + 5]
review_sheet_both[, age_end_r := age_end_r - 1]
review_sheet_both[, pop_m := pop_agg(location_id, age_start_r, age_end_r, year_start, year_end, s = 1), by = "seq"]
review_sheet_both[, pop_f := pop_agg(location_id, age_start_r, age_end_r, year_start, year_end, s = 2), by = "seq"]
review_sheet_both[, pop_b := pop_m + pop_f]

review_sheet_female <- copy(review_sheet_both)
review_sheet_female[, `:=` (sex = "Female", mean_n = mean * (pop_b), mean_d =(pop_f + ratio * pop_m),
                            var_n = (standard_error^2 * pop_b^2), var_d = ratio_se^2 * pop_m^2)]
review_sheet_female[, `:=` (mean = mean_n / mean_d, standard_error = sqrt(((mean_n^2) / (mean_d^2)) * (var_n / (mean_n^2) + var_d / (mean_d^2))))]
review_sheet_female[, `:=` (study_covariate = "sex", crosswalk_parent_seq = seq, seq = NA)]

review_sheet_male <- copy(review_sheet_both)
review_sheet_male[, `:=` (sex = "Male", mean_n = mean * (pop_b), mean_d =(pop_m + (1/ratio) * pop_f),
                            var_n = (standard_error^2 * pop_b^2), var_d = ratio_se^2 * pop_f^2)]
review_sheet_male[, `:=` (mean = mean_n / mean_d, standard_error = sqrt(((mean_n^2) / (mean_d^2)) * (var_n / (mean_n^2) + var_d / (mean_d^2))))]
review_sheet_male[, `:=` (study_covariate = "sex", crosswalk_parent_seq = seq, seq = NA)]

review_sheet_final <- rbind(review_sheet_male, review_sheet_female, review_sheet[sex != "Both",], fill = T)
col_remove <- c("mid_age", "age_start_r", "age_end_r", "pop_m", "pop_f", "pop_b", "mean_n", "mean_d", "var_n", "var_d", "ratio", "ratio_se")
review_sheet_final[, (col_remove) := NULL]

## Re-add estimates that are age-sex split using the study sex-ratio

setnames(age_sex_split, "age_parent", "crosswalk_parent_seq")
age_sex_split[, `:=` (study_covariate = "sex", sex_parent = NULL, seq = NULL)] 
age_sex_split[, `:=` (seq = NA)] #
review_sheet_final <- review_sheet_final[!(seq %in% c(sex_parents, age_parents)),]
review_sheet_final <- rbind(review_sheet_final, age_sex_split, fill = T) 

##### Estimate and apply study-level covariates -----------------------------------------------------------------------

covariates <- gsub("cv_", "d_", covariates)
for(c in covariates){
  cov <- cov_info(c, "X")
  if(c == covariates[1]){
    cov_list <- list(cov)
  } else {
    cov_list <- c(cov_list, list(cov))
  }
}

crosswalk_fit <- run_mr_brt(
  output_dir = paste0("FILEPATH/", acause, "/FILEPATH/"),
  model_label = "bullying",
  data = crosswalk_pairs,
  mean_var = "log_effect_size",
  se_var = "log_effect_size_se",
  covs = cov_list,
  remove_x_intercept = TRUE,
  method = "trim_maxL",
  trim_pct = 0.1,
  study_id = "id",
  overwrite_previous = TRUE,
  lasso = FALSE)

check_for_outputs(crosswalk_fit)

eval(parse(text = paste0("predicted <- expand.grid(", paste0(covariates, "=c(0, 1)", collapse = ", "), ")")))
predicted <- as.data.table(predict_mr_brt(crosswalk_fit, newdata = predicted)["model_summaries"])
names(predicted) <- gsub("model_summaries.", "", names(predicted))
names(predicted) <- gsub("X_d_", "cv_", names(predicted))
predicted[, `:=` (Y_se = (Y_mean_hi - Y_mean_lo)/(2*qnorm(0.975,0,1)))]
crosswalk_reporting <- copy(predicted) # for reporting later
predicted[, (c("Z_intercept", "Y_negp", "Y_mean_lo", "Y_mean_hi", "Y_mean_fe", "Y_negp_fe", "Y_mean_lo_fe", "Y_mean_hi_fe")) := NULL]

review_sheet_final <- merge(review_sheet_final, predicted, by=gsub("d_", "cv_", covariates))
review_sheet_final[, `:=` (log_mean = log(mean), log_se = deltamethod(~log(x1), mean, standard_error^2)), by = c("mean", "standard_error")]

review_sheet_final[Y_mean != predicted[1,Y_mean], `:=` (log_mean = log_mean - Y_mean, log_se = sqrt(log_se^2 + Y_se^2))]
review_sheet_final[Y_mean != predicted[1,Y_mean], `:=` (mean = exp(log_mean), standard_error = deltamethod(~exp(x1), log_mean, log_se^2)), by = c("log_mean", "log_se")]
review_sheet_final[Y_mean != predicted[1,Y_mean], `:=` (cases = NA, lower = NA, upper = NA)]
review_sheet_final[Y_mean != predicted[1,Y_mean] & is.na(crosswalk_parent_seq), `:=` (crosswalk_parent_seq = seq, seq = NA)]

for(c in covariates){
  c <- gsub("d_", "cv_", c)
  review_sheet_final[get(c) == 1, study_covariate := ifelse(is.na(study_covariate) | study_covariate == "ref", gsub("cv_", "", c), paste0(study_covariate, ", ", gsub("cv_", "", c)))]
}

review_sheet_final[, (c("Y_mean", "Y_se", "log_mean", "log_se")) := NULL]

# For upload validation #
review_sheet_final[study_covariate != "ref", `:=` (lower = NA, upper = NA, cases = NA, sample_size = NA)]
review_sheet_final[is.na(lower), uncertainty_type_value := NA]

review_sheet_final <- review_sheet_final[group_review == 1, ] # Some age-split estimates were group_reviewed 0 so mirroring that here

crosswalk_save_folder <- paste0("/FILEPATH/", acause, "/", bundle_id, "/FILEPATH/")
dir.create(file.path(crosswalk_save_folder), showWarnings = FALSE)
crosswalk_save_file <- paste0(crosswalk_save_folder, "crosswalk_", Sys.Date(), ".xlsx")
write.xlsx(review_sheet_final, crosswalk_save_file, sheetName = "extraction")

##### Upload crosswalked dataset to database -----------------------------------------------------------------------

save_crosswalk_version(v_id, crosswalk_save_file, description = "Post uncertainty correction")

## Save study-level covariates to a csv for later reporting ##

crosswalk_reporting[, covariate := ""]
for(c in names(crosswalk_reporting)[names(crosswalk_reporting) %like% "cv_"]){
  crosswalk_reporting[get(c) == 1, covariate := ifelse(covariate != "", paste0(covariate, ", "), c)]
}
crosswalk_reporting[, covariate := gsub("cv_", "", covariate)]
crosswalk_reporting <- crosswalk_reporting[covariate %in% gsub("d_", "", covariates),]

crosswalk_reporting <- crosswalk_reporting[,.(covariate, beta = Y_mean, beta_low = Y_mean_lo, beta_high = Y_mean_hi,
                                              exp_beta = exp(Y_mean), exp_beta_low = exp(Y_mean_lo), exp_beta_high = exp(Y_mean_hi))]
write.csv(crosswalk_reporting, paste0("/FILEPATH/", acause, "/FILEPATH.csv"),row.names=F)



