//A checker to make sure all of the jobs finished, save results

	clear
	set more off
	local prefix "FILEPATH"
	set odbcmgr unixodbc
	local code "FILEPATH"
	local stata_shell "FILEPATH/stata_shell.sh"

	qui do FILEPATH/save_results_epi.ado
	qui do FILEPATH/get_best_model_versions.ado
	qui do FILEPATH/get_location_metadata.ado
	qui do FILEPATH/get_demographics.ado
	
	args output ver_desc
	local coal_workers_ac 1893
	local coal_workers_end 3052

	//// CHECK OUTPUTS -------------------------------------------------------------------------------

	//Collect Locations to check
	get_location_metadata, location_set_id(9) clear
	levelsof location_id, local(location_ids)

	//Get years to check
	get_demographics, gbd_team(epi) clear
	local years `r(year_id)'
	di `years'
	
	//figure out which locations are missing, if any
	local completes 0
	local incomplete 0
	local mislocs
	local num 0

	foreach loc_id of local location_ids{
		foreach year of local years{
			foreach sex in 1 2{
						cap confirm file "FILEPATH/5_`loc_id'_`year'_`sex'.csv"
						if !_rc{
							local completes =`completes' +1
						}
						else {
							local mislocs `loc_id' `mislocs'
							local incomplete = `incomplete' + 1
						}
						local num = `num' +1
			} //close sex
		} //close year
	} //close location
	
	local mislocs : list uniq mislocs
	di in red "THESE ARE THE MISSING LOCATIONS `mislocs'"
	di in red "`completes' MANY FILES WROTE SUCCESSFULLY"
	di in red "`completes'/`num' finished"

	/// SAVE RESULTS -------------------------------------------------------------------------------------

	get_best_model_versions, entity(modelable_entity) ids(`coal_workers_ac') clear
	levelsof model_version_id, local(best_model) clean	
		
	di "SAVING RESULTS"
	save_results_epi, modelable_entity_id(`coal_workers_end') description("Pneumo model `best_model' with proper zeros") input_file_pattern("{measure_id}_{location_id}_{year_id}_{sex_id}.csv") input_dir("FILEPATH") clear
	
	

	
