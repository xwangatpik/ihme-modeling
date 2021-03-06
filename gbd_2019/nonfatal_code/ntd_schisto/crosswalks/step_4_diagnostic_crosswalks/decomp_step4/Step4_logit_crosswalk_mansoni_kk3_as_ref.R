# 

library(readxl)
library(dplyr)
library(data.table)
library(msm)
library(msm, lib.loc = "FILEPATH")
library(metafor, lib.loc = "FILEPATH")


readxl::excel_sheets("FILEPATH")
dx_data_m <- readxl::read_xlsx("FILEPATH", sheet = 'mansoni_kk3_as_ref')

#saving mansoni sheet it in ihme/ntds
openxlsx::write.xlsx(dx_data_m, file = 'FILEPATH')

mansoni_dx_data <- readxl::read_xlsx("FILEPATH")

df<- mansoni_dx_data

#calculating the ratio and se in logit space

library(boot)

df$se_logit_mean_1 <- sapply(1:nrow(df), function(i) {
  ratio_i <- df[i, "mean_1"]
  ratio_se_i <- df[i, "se_1"]
  deltamethod(~log(x1/(1-x1)), ratio_i, ratio_se_i^2)
})

df$se_logit_mean_2 <- sapply(1:nrow(df), function(a) {
  ratio_a <- df[a, "mean_2"]
  ratio_se_a <- df[a, "se_2"]
  deltamethod(~log(x1/(1-x1)), ratio_a, ratio_se_a^2)
})

df <- df %>%
  mutate(
    logit_mean_1 = logit(mean_1),
    logit_mean_2 = logit(mean_2),
    diff_logit = logit_mean_1 - logit_mean_2,
    se_diff_logit = sqrt(se_logit_mean_1^2 + se_logit_mean_2^2)
  )

library(data.table)
df2 <- select(df, ratio = diff_logit, ratio_se = se_diff_logit, comparison, NID)

#ratio = diff_logit
#ratio_se = se_diff_logit

#adding two more columns, that split the comparison column into alt and ref
df2[, c("alt", "ref")] <- do.call("rbind", strsplit(df2$comparison, split = "_"))

#saving all case definitions in a vector
case_defs <- unique(c(df2$alt, df2$ref))
#saving all alternative case defintions in a vector 
nonGBD_case_defs <- case_defs[!case_defs == "kk3"]

for (i in nonGBD_case_defs) df2[, i] <- ifelse(df2$alt == i, 1, ifelse(df2$ref == i, -1, 0))




#PULL IN MANSONI SEX SPLIT data from memory and make a copy

data_sex_adj_mansoni_for_dx<- subset(final_sex_split_data, case_name=="S mansoni" | case_name=="S intercalatum"| case_name=="S mekongi" |  case_name=="S guineesis")

data_sex_adj_mansoni_for_dx<- subset(data_sex_adj_mansoni_for_dx, sample_size!=cases)



#will term mean and standard error as pre-adjusted so we can compare the adjusted with these 
colnames(data_sex_adj_mansoni_for_dx)[colnames(data_sex_adj_mansoni_for_dx)=="mean"] <- "pre_adjusted_mean"
colnames(data_sex_adj_mansoni_for_dx)[colnames(data_sex_adj_mansoni_for_dx)=="standard_error"] <- "pre_adjusted_standard_error"
colnames(data_sex_adj_mansoni_for_dx)[colnames(data_sex_adj_mansoni_for_dx)=="upper"] <- "pre_adjusted_upper"
colnames(data_sex_adj_mansoni_for_dx)[colnames(data_sex_adj_mansoni_for_dx)=="lower"] <- "pre_adjusted_lower"


data_sex_adj_mansoni_for_dx$pre_adjusted_mean[data_sex_adj_mansoni_for_dx$cases==0] <- 0

unique(data_sex_adj_mansoni_for_dx$case_diagnostics)
# "kk1" "kk2" "kk3" "sed" "pcr" "fec" "cca"
# no elisa


data_sex_adj_mansoni_for_dx <- data_sex_adj_mansoni_for_dx %>%
  mutate(
    elisa = ifelse(case_diagnostics == "elisa", 1, 0),
    pcr = ifelse(case_diagnostics == "pcr", 1, 0),
    kk1 = ifelse(case_diagnostics == "kk1", 1, 0),
    kk2 = ifelse(case_diagnostics == "kk2", 1, 0),
    cca = ifelse(case_diagnostics == "cca", 1, 0),
    sed = ifelse(case_diagnostics == "sed", 1, 0),
    fec = ifelse(case_diagnostics == "fec", 1, 0)
  )

reference_var <- "case_diagnostics"
reference_value <- "kk3"
mean_var <- "pre_adjusted_mean"
se_var <- "pre_adjusted_standard_error"
cov_names <- c("elisa","kk1","kk2", "cca", "pcr", "sed", "fec") # can be a vector of names


# data for meta-regression model
# -- read in data frame
# -- identify variables for ratio and SE
#    NOTE: ratio must be specified as reference/alternative
dat_metareg <- df2
ratio_var <- "ratio"
ratio_se_var <- "ratio_se"


# create datasets with standardized variable names (the extra vars may change based on meta-reg inputs)
#meta-reg dataset
metareg_vars <- c(ratio_var, ratio_se_var)
extra_vars <- c("kk1", "kk2", "cca", "fec", "sed", "pcr", "elisa", "ref", "alt", "NID")
metareg_vars2 <- c(metareg_vars, extra_vars)
#excludes kk3 as that is the reference 

tmp_metareg <- as.data.frame(dat_metareg) %>%
  .[, metareg_vars2] %>%
  setnames(metareg_vars, c("ratio", "ratio_se"))

#original dataset
orig_vars <- c(mean_var, se_var, reference_var, cov_names)

tmp_orig <- as.data.frame(data_sex_adj_mansoni_for_dx) %>%
  .[, orig_vars] %>%
  setnames(orig_vars, c("mean", "se", "ref", cov_names)) %>%
  mutate(ref = if_else(ref == reference_value, 1, 0, 0))

######################
# logit transform the original data
# -- SEs transformed using the delta method 

tmp_orig$mean_logit <- logit(tmp_orig$mean)
tmp_orig$se_logit <- sapply(1:nrow(tmp_orig), function(i) {
  mean_i <- tmp_orig[i, "mean"]
  se_i <- tmp_orig[i, "se"]
  deltamethod(~log(x1/(1-x1)), mean_i, se_i^2)
})

tmp_metareg$intercept <- 1

# fit the MR-BRT model
repo_dir <- "FILEPATH"
source(paste0(repo_dir, "FILEPATH"))
source(paste0(repo_dir, "FILEPATH"))
source(paste0(repo_dir, "FILEPATH"))
source(paste0(repo_dir, "FILEPATH"))
source(paste0(repo_dir, "FILEPATH"))
source(paste0(repo_dir, "FILEPATH"))
source(paste0(repo_dir, "FILEPATH"))
source(paste0(repo_dir, "FILEPATH"))

cov_list <- lapply(nonGBD_case_defs, function(x) cov_info(x, "X"))

fit1 <- run_mr_brt(
  output_dir = "FILEPATH",
  model_label = "FILEPATH",
  data = tmp_metareg,
  mean_var = "ratio",
  se_var = "ratio_se",
  covs = cov_list,
  remove_x_intercept = TRUE,
  overwrite_previous = TRUE,
  study_id = "NID"
)

check_for_outputs(fit1)

# this creates a ratio prediction for each observation in the original data
df_pred <- as.data.frame(tmp_orig[, cov_names])
names(df_pred) <- cov_names
pred1 <- predict_mr_brt(fit1, newdata = df_pred) 
check_for_preds(pred1)
pred_object <- load_mr_brt_preds(pred1)
preds <- pred_object$model_summaries


tmp_preds <- preds %>%
  mutate(
    pred = Y_mean,
    # don't need to incorporate tau as with metafor; MR-BRT already included it in the uncertainty
    pred_se = (Y_mean_hi - Y_mean_lo) / 3.92  ) %>%
  select(pred, pred_se)

tmp_orig2 <- cbind(tmp_orig, tmp_preds) %>%
  mutate(
    mean_logit_tmp = mean_logit - pred, # adjust the mean estimate: log(mean_original) - (log(alt) - log(ref))
    #prediciton (alt-ref), 
    var_logit_tmp = se_logit^2 + pred_se^2, # adjust the variance
    #variance is additive 
    se_logit_tmp = sqrt(var_logit_tmp)
  )



# if original data point was a reference data point, leave as-is
tmp_orig3 <- tmp_orig2 %>%
  mutate(
    mean_logit_adjusted = if_else(ref == 1, mean_logit, mean_logit_tmp),
    se_logit_adjusted = if_else(ref == 1, se_logit, se_logit_tmp),
    lo_logit_adjusted = mean_logit_adjusted - 1.96 * se_logit_adjusted,
    hi_logit_adjusted = mean_logit_adjusted + 1.96 * se_logit_adjusted,
    mean_adjusted = inv.logit(mean_logit_adjusted),
    lo_adjusted = inv.logit(lo_logit_adjusted),
    hi_adjusted = inv.logit(hi_logit_adjusted))

tmp_orig3$se_adjusted <- sapply(1:nrow(tmp_orig3), function(i) {
  ratio_i <- tmp_orig3[i, "mean_logit_adjusted"]
  ratio_se_i <- tmp_orig3[i, "se_logit_adjusted"]
  deltamethod(~exp(x1)/(1+exp(x1)), ratio_i, ratio_se_i^2)
})



##to calculate standard errors for mean = 0 and mean =1
tmp_orig3$pred_se_invlogit <- sapply(1:nrow(tmp_orig3), function(i) {
  ratio_i <- tmp_orig3[i, "pred"]
  ratio_se_i <- tmp_orig3[i, "pred_se"]
  deltamethod(~exp(x1)/(1+exp(x1)), ratio_i, ratio_se_i^2)
})

tmp_orig3$se_adjusted_zero <- sqrt(tmp_orig3$se^2 + tmp_orig3$pred_se_invlogit^2)


#apply this se_adjusted_zero not only to mean = 0 but also mean =1
tmp_orig3$se_adjusted[tmp_orig3$mean_adjusted==0] <- tmp_orig3$se_adjusted_zero
tmp_orig3$se_adjusted[tmp_orig3$mean_adjusted==1] <- tmp_orig3$se_adjusted_zero

#calculate high and low CIs for those problematic datapoints
tmp_orig3$high_adjusted_zero_one<- (tmp_orig3$mean_adjusted + (1.96*tmp_orig3$se_adjusted))
tmp_orig3$low_adjusted_one<- (tmp_orig3$mean_adjusted - (1.96*tmp_orig3$se_adjusted))

#apply this high_adjusted_zer_one to mean = 0 and mean =1
tmp_orig3$hi_adjusted[tmp_orig3$mean_adjusted==0] <- tmp_orig3$high_adjusted_zero_one
tmp_orig3$hi_adjusted[tmp_orig3$mean_adjusted==1] <- 1

#apply this low_adjusted_one to mean 1 and mean=0
tmp_orig3$lo_adjusted[tmp_orig3$mean_adjusted==0] <- 0
tmp_orig3$lo_adjusted[tmp_orig3$mean_adjusted==1] <- tmp_orig3$low_adjusted_one

#applying celings to higher and lower CIs 
tmp_orig3$hi_adjusted[tmp_orig3$hi_adjusted>1] <- 1
tmp_orig3$lo_adjusted[tmp_orig3$lo_adjusted<0] <- 0


# 'final_data' is the original extracted data plus the new variables
final_data_mansoni_kk3_ref <- cbind(
  data_sex_adj_mansoni_for_dx, 
  tmp_orig3[, c("ref", "mean_adjusted", "se_adjusted", "lo_adjusted", "hi_adjusted")]
)

drops <- c("elisa","pcr", "kk1", "kk2", "cca", "sed", "fec", "ref")
final_data_mansoni_kk3_ref<- final_data_mansoni_kk3_ref[ , !(names(final_data_mansoni_kk3_ref) %in% drops)]

#renaming the adjusted mean and se to variables that wil be accepted by DISMOD
colnames(final_data_mansoni_kk3_ref)[colnames(final_data_mansoni_kk3_ref)=="mean_adjusted"] <- "mean"
colnames(final_data_mansoni_kk3_ref)[colnames(final_data_mansoni_kk3_ref)=="se_adjusted"] <- "standard_error"
colnames(final_data_mansoni_kk3_ref)[colnames(final_data_mansoni_kk3_ref)=="lo_adjusted"] <- "lower"
colnames(final_data_mansoni_kk3_ref)[colnames(final_data_mansoni_kk3_ref)=="hi_adjusted"] <- "upper"


write.csv(final_data_mansoni_kk3_ref, file="FILEPATH")

####BINDING ALL CROSSWALKED SPECIE FILES HERE###

final_crosswalked_data <- rbind(final_data_mansoni_kk3_ref, final_data_japon, final_data_hema)

#dropping sex id from here cause the age split code does not work with this column (coming up next)
drops <- "sex_id"
final_crosswalked_data<- final_crosswalked_data[ , !(names(final_crosswalked_data) %in% drops)]

#adding this so we can check which rows were age split in next step 
final_crosswalked_data$note_modeler<- ""


openxlsx::write.xlsx(final_crosswalked_data, sheetName = "extraction", file = "FILEPATH")

#now move on to age splitting

library(ggplot2)


ggplot(final_data_mansoni_kk3_ref, aes(x=pre_adjusted_mean, y=mean, color=case_diagnostics)) +
  geom_point(size=1.0) + 
  labs(color="Diagnostics", x="Unadjusted prevalence", y="Adjusted prevalence")+
  scale_color_brewer(palette="Dark2")

#to plot the logit differences
readxl::excel_sheets("FILEPATH")
model_coef <- readxl::read_xlsx("FILEPATH")


#this worked
p<- ggplot(model_coef, aes(x=Diagnostic, y=beta_soln, color=Diagnostic)) + 
  geom_line()+
  geom_point()+
  geom_errorbar(aes(ymin=lower_ci, ymax=upper_ci), width=.2,
                position=position_dodge(0.05)) 


p+labs(title="Predicted Logit Difference in reference to CCA", x="Diagnostic", y = "Predicted Logit Difference")


################testing: DO NOT RUN
# Box plot
bp + scale_fill_manual(breaks = c("2", "1", "0.5"), 
                       values=c("red", "blue", "green"))
# Scatter plot
sp + scale_color_manual(breaks = c("cca", "kk1", "kk2", "kk3", "sed", "fec", "elisa", "pcr"),
                        values=c("red", "blue", "black", "green", "orange", "yellow", "pink", "purple"))

sp + scale_fill_discrete(breaks=c("cca", "kk1", "kk2", "kk3", "sed", "fec", "elisa", "pcr"))


p<- ggplot(df2, aes(x=dose, y=len, group=supp, color=supp)) + 
  geom_line() +
  geom_point()+
  geom_errorbar(aes(ymin=len-sd, ymax=len+sd), width=.2,
                position=position_dodge(0.05))

library(ggplot2)
box <- ggplot(model_coef, aes(x=x_cov, y=beta_var, fill=x_cov)) + 
  geom_boxplot()
box

mean<- model_coef$beta_soln
lower<- model_coef$lower_ci
upper<- model_coef$upper_ci

plot(mean,
     ylim=range(-1.5, 1.5),
     size=1, pch=1, xlab="Measurements", ylab="Mean +/- SD",
     main="Scatter plot with std.dev error bars")



arrows(x, avg-sdev, x, avg+sdev, length=0.05, angle=90, code=3)




sp<- ggplot(final_data, aes(x=mean_unadjusted, y=mean_adjusted, color=case_diagnostics)) +
  geom_point(size=1.0) 

sp + scale_color_brewer(palette="Dark2")

sp + legend(x=1,y=1,legend="Diagnostics")


sp + labs(color = "Diagnostics")

sp<- ggplot(final_data, aes(x=mean_unadjusted, y=mean_adjusted, color=case_diagnostics)) +
  geom_point(size=1.0) + 
  labs(color="Diagnostics", x="Unadjusted prevalence", y="Adjusted prevalence")+
  scale_color_brewer(palette="Dark2")

