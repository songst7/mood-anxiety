library(brms)
library(dplyr)
library(parallel)
library(cmdstanr)

set_cmdstan_path("/home/songtao/.cmdstanr/cmdstan-2.26.1")

project <- "late_diff"

df <- read.table('data/MAX_neutral_offset_agg_response.txt', header = TRUE, sep = ",")

df$Subj <- factor(df$Subj)
df$ROI <- factor(df$ROI_name)

print(paste0('Number of ROIs: ',nlevels(df$ROI)))
print(paste0('Number of subjects: ',nlevels(df$Subj)))
print(paste0("Number of conditions: ", df %>% select(cond) %>% n_distinct()))
print(paste0('Length of dataset: ', dim(df)[1]))

# filter data as early response only and select used columns
dataTable <- select(filter(df, Phase == "late"), Subj, ROI, cond, response, TRAIT, STATE)

# Transfer data into contrast coding as response_threat - response_safe

dataTable <- dataTable %>% left_join(dataTable, by = c("Subj", "ROI", "TRAIT", "STATE"))
dataTable <- dataTable %>% filter(cond.x == -0.5, cond.y == 0.5)
dataTable <- dataTable %>% mutate(diff = response.y - response.x)
dataTable <- dataTable %>% select(Subj, ROI, diff, TRAIT, STATE)
dataTable %>% head()

# Number of iterations for the MCMC sampling
iterations <- 20000
# Number of chains to run
chains <- 4
SCALE <- 1
ns <- iterations*chains/2

# number of sigfigs to show on the table
nfigs <- 4

# Set nuber of cores to use. 
# To run each chain on a single core, set number of core to 4
print(getOption("mc.cores"))
options(mc.cores = parallel::detectCores())
print(getOption("mc.cores"))

# Set the Bayesian model
mod <- '1 + TRAIT + STATE'
modelForm <- paste0('diff ~ ', mod, ' + (', mod, ' | gr(ROI, dist = "student")) + (1 | gr(Subj, dist = "student"))')

priorRBA <- get_prior(formula = modelForm, data = dataTable, family = "student")
# You can assign prior or your choice to any of the parameter in the table below. 
# For example. If you want to assign a student_t(3,0,10) prior to all parameters of class b, 
# the following line does that for you. Parameters in class b are the population effects (STATE and TRAIT)

priorRBA$prior[1] <- "student_t(3, 0, 2.5)"
priorRBA$prior[4] <- "lkj(2)"
priorRBA$prior[6:7] <- "gamma(3.325, 0.2)"
priorRBA$prior[9] <- "gamma(3.325, 0.2)"

print(priorRBA)

# Create a result directory
if (!dir.exists("results_offset")){dir.create("results_offset")}

# Generate the Stan code for our own reference
stan_code <- make_stancode(modelForm, data = dataTable,chains = chains, family = 'student', prior = priorRBA)
cat(stan_code, file = paste0("results_offset/model1/", project, "_only_stancode.stan"), sep='\n')

# Following run the BML model
# The number in threading() means the cores used for with-in chain parallelization,
# for example, here threading(12) means for each chain, there are 12 cores used.
# Thus, 12*4=48 cores were used for BML; you can change it according to your own computation power.
fm <- brm(modelForm,
          data = dataTable,
          chains = chains,
          family = 'student',
          prior = priorRBA,
          inits = 0, iter = iterations, 
          control = list(adapt_delta = 0.99, max_treedepth = 15), 
          backend = 'cmdstanr',
          threads = threading(12))

# Save the results as a RData file
save.image(file = paste0("results_offset/model1/", project, ".RData"))

# Shows the summary of the model
cat(capture.output(summary(fm)), sep = '\n', append = TRUE)