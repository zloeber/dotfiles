export SPLUNK_URL=https://splunkent.nml.com:8000/
export SPLUNK_USERNAME=$$USERNAME

.PHONY: splunk/terraform
splunk/terraform: ## Runs terraform against the splunk path
	@$(MAKE) TF_PATH=$(ROOT_PATH)/splunk tf/init tf/plan tf/apply