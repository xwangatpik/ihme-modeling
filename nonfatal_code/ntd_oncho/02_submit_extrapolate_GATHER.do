/*====================================================================
project:       GBD2016
Dependencies:  IHME
----------------------------------------------------------------------
Do-file version:  GBD2016 GATHER      
Output:           Submit script to extrapolate GBD2013 prevalence draws
====================================================================*/

/*====================================================================
                        0: Program set up
====================================================================*/

	version 13.1
	drop _all
	set more off

	set maxvar 32000
	if c(os) == "Unix" {
		local j "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		local j "J:"
	}
	

* Directory Paths
	*gbd version (i.e. gbd2013)
	local gbd = "gbd2016"
	*model step
	local step 02
	*local root
	local localRoot "FILEPATH"
	*cluster root
	local clusterRoot "FILEPATH"
	*directory for code
	local code_dir "FILEPATH"
	*directory for external inputs
	local in_dir "FILEPATH"
	*directory for temporary outputs on cluster to be utilized through process
	local tmp_dir "FILEPATH"
	*local temporary directory for other things:
	local local_tmp_dir "FILEPATH"
	*directory for output of draws > on ihme/scratch
	local out_dir "FILEPATH"
	*directory for logs
	local log_dir "FILEPATH"
	*directory for progress files
	local progress_dir "FILEPATH"

* Make and Clear Directories
	
	*make all directories
	local make_dirs code in tmp local_tmp out log progress_dir
	foreach dir in `make_dirs' {
		capture mkdir `dir'_dir
	}
	*clear tempfiles, logs and progress files
	foreach dir in log progress tmp {
		capture cd `dir'_dir
		capture shell rm *
	}
	*clear temp files and output files created by this script
	local clear_output_dirs 1494 1495 2620 2515 2621 1496 1497 1498 1499
	foreach output_meid_dir in `clear_output_dirs' {
		capture cd `output_meid_dir'_dir
		capture shell rm *
	}
	

*Directory for standard code files
	adopath + FILEPATH


	*****start log*********
	capture log close
	local date = string(date(c(current_date),"DMY"),"%tdDD.NN.CCYY")
	local time = subinstr("$S_TIME", ":" , "", .)
	log using "`log_dir'/02b_submit_extrapolate_log_`date'_`time'.smcl", replace
	***********************	

	*print macros in log
	macro dir


/*====================================================================
                        1: Get GBD Info
====================================================================*/


*--------------------1.1: Demographics

	get_demographics, gbd_team("epi") clear
		local gbdages `r(age_group_ids)'
		local gbdyears `r(year_ids)'
		local gbdsexes `r(sex_ids)'

*--------------------1.2: Location Metadata
		
	get_location_metadata, location_set_id(35) clear
		keep if most_detailed==1
		levelsof location_id,local(gbdlocs)clean
		save "`local_tmp_dir'/metadata.dta", replace

*--------------------1.3: GBD Skeleton

	get_population, location_id("`gbdlocs'") sex_id("`gbdsexes'") age_group_id("`gbdages'") year_id("`gbdyears'") clear
		save "`local_tmp_dir'/skeleton.dta", replace

			
/*====================================================================
                        2: Submit Extrapolation Script to Qsub 
====================================================================*/


*--------------------2.1: Create Zeroes File
	
	*Edit skeleton to accomodate all Oncho Outcomes
		gen modelable_entity_id=.
		expand 9
		bysort age_group_id location_id year_id sex_id: gen id=_n
		
		local meids 1494 1495 2620 2515 2621 1496 1497 1498 1499
		local i 1
		foreach meid in `meids' {
			replace modelable_entity_id = `meid' if id ==`i'
			local ++i
		}
		
		*1494 onchocerciasis
		*1495 mild skin disease
		*2620 mild skin disease without itch
		*2515 severe skin disease
		*2621 severe skin disease without itch
		*1496 moderate skin disease
		*1497 moderate vision impairment (unsqueezed)
		*1498 severe vision impairment (unsqueezed)
		*1499 blindness (unsqueezed)

	*Fill values with zeroes
		forval i=0/999{
			gen draw_`i'=0
		}

	*Format and save
		capture drop population
		capture drop process*
		gen measure_id=5

		save "`local_tmp_dir'/zeroes.dta", replace

*--------------------2.2: ENDEMIC (OCP + APOC): Submit Extrapolation Scropt

	*Loop over ocp and apoc datasets
		foreach set in ocp apoc {
			
			*Pull in the dataset and get local list of locations
				use "`in_dir'/`set'_GBD2016_PreppedData.dta", clear
				levelsof location_id,local(locations_`set') clean

			*Loop over each location to create temp draws file and submit extrapolation script to qsub
				foreach location in `locations_`set''{

					*save temp file
						preserve
							keep if location_id==`location'
							save `tmp_dir'/`set'_preextrapolated_draws_`location'.dta, replace
						restore
						drop if location_id == `location'
						
					*submit qsub
						!qsub -o FILEPATH -e FILEPATH -P proj_custom_models -pe multi_slot 8 -N onchoNF_`location' "`localRoot'/submit_extrapolate.sh" "`location'" "`set'"
						
				}
		}

*--------------------2.3: NON-ENDEMIC (ALL ELSE): Submit Zeroes Script

	*Compile local lists of endemic and nonendemic locations			
		local endemic `locations_ocp' `locations_apoc'
		local nonendemic: list gbdlocs - endemic

	*Use zeroes file
		use "`local_tmp_dir'/zeroes.dta", clear
			
	*Loop over each location to create temp zeroes file for all output meids and submit zeroes script to qsub
		foreach location in `nonendemic' {
			
			*save temp file
				preserve
					keep if location_id == `location'
					save `tmp_dir'/nonendemic_allmeids_zeroes_`location'.dta, replace
				restore
				drop if location_id == `location'
			
			*submit qsub
				!qsub -o FILEPATH -e FILEPATH -P proj_custom_models -pe multi_slot 8 -N onchoNF_`location' "`localRoot'/submit_nonendemiczeroes.sh" "`location'" "`meid'"				
						
		}


/*====================================================================
                        4: Monitor Submission
====================================================================*/



*--------------------6.1: CREATE DATASET OF locations TO MARK COMPLETION STATUS

	    clear
	    set obs `=wordcount("`gbdlocs'")'
	    generate location_id = .
	    
	    forvalues i = 1 / `=wordcount("`gbdlocs'")' {
	                    quietly replace location_id = `=word("`gbdlocs'", `i')' in `i'
	                    }
	                    
	    generate complete = 0

*--------------------6.2: GET READY TO CHECK IF ALL locations ARE COMPLETE

	    local pause 2
	    local complete 0
	    local incompleteLocations `gbdlocs'
	    
	    display _n "Checking to ensure all locations are complete" _n

                
*--------------------6.3: ITERATIVELY LOOP THROUGH ALL locations TO ASSESS PROGRESS UNTIL ALL ARE COMPLETE              
       
		while `complete'==0 {
        
		*Are all locations complete?
			foreach location of local incompleteLocations {
			            capture confirm file /`progress_dir'/`location'.txt 
			            if _rc == 0 quietly replace complete = 1 if location_id==`location'
			            }
			            
			quietly count if complete==0
          
		*If all locations are complete submit save results jobs 
			if `r(N)'==0 {
				display "All locations complete!!!"
				local complete 1
			}
        

         *If all locations are not complete, inform the user and pause before checking again
			else {
				quietly levelsof location_id if complete==0, local(incompleteLocations) clean
					display "The following locations remain incomplete:" _n _col(3) "`incompleteLocations'" _n "Pausing for `pause' minutes" _continue

					forvalues sleep = 1/`=`pause'*6' {
						sleep 10000
						if mod(`sleep',6)==0 di "`=`sleep'/6'" _continue
						else di "." _continue
					}
					
					di _n

				}
			}
        


/*====================================================================
                        5: Save Results
====================================================================*/

/*
*SAVE RESULTS

run "FILEPATH/save_results.do"

save_results, modelable_entity_id(10568) mark_best(no) env(prod) file_pattern({location_id}.csv) description($S_DATE $S_TIME Results Model `model_version_id') in_dir(FILEPATH/output_`model_version_id')

*/



log close
exit
/* End of do-file */

><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><><

Notes:
1.
2.
3.

