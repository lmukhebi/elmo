module ModelSpecHelpers
  def create_report(klass, options)
    # handle option_set parameter
    if option_set = options.delete(:option_set)
      options[:option_set_choices_attributes] = [{option_set_id: option_set.id}]
    end

    # this is no longer the default
    options[:question_labels] ||= 'code'

    report = "Report::#{klass}Report".constantize.new(mission_id: get_mission.id)
    report.generate_default_name
    report.update_attributes!({name: "TheReport"}.merge(options))
    report
  end
end